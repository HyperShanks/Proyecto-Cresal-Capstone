package com.example.frontend

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketTimeoutException
import java.nio.charset.StandardCharsets
import kotlin.concurrent.thread

/**
 * MainActivity con soporte Multi-Network Routing para Android.
 * Permite abrir sockets TCP industriales forzados a través de la interfaz Wi-Fi local
 * (Router Huawei / Honeywell PC42E-T), mientras el sistema operativo mantiene
 * los Datos Móviles (4G/5G) como conexión principal para la API en Render y Supabase.
 */
class MainActivity : FlutterActivity() {
    private val CHANNEL = "cl.cresal/printer_channel"
    private var activeWifiNetwork: Network? = null
    private var connectivityManager: ConnectivityManager? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        connectivityManager = getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        registrarEscuchaWifi()
    }

    private fun registrarEscuchaWifi() {
        val cm = connectivityManager ?: return
        try {
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                .build()

            cm.registerNetworkCallback(request, object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    activeWifiNetwork = network
                }

                override fun onLost(network: Network) {
                    if (activeWifiNetwork == network) {
                        activeWifiNetwork = null
                    }
                }
            })
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun obtenerRedLocal(): Network? {
        val cm = connectivityManager ?: return null
        if (activeWifiNetwork != null) return activeWifiNetwork

        // Fallback: explorar todas las redes físicas activas del dispositivo (Wi-Fi o Ethernet)
        return try {
            cm.allNetworks.firstOrNull { net ->
                val caps = cm.getNetworkCapabilities(net)
                caps != null && (
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
                )
            }
        } catch (e: Exception) {
            null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "consultarEstadoFisico" -> {
                    val ip = call.argument<String>("ip") ?: "192.168.8.50"
                    val port = call.argument<Int>("port") ?: 9100
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 2500

                    thread {
                        try {
                            val respuestaHs = ejecutarDiagnosticoHsEnWifi(ip, port, timeoutMs)
                            runOnUiThread { result.success(respuestaHs) }
                        } catch (e: IllegalStateException) {
                            if (e.message == "NO_WIFI") {
                                runOnUiThread { result.error("NO_WIFI", "El dispositivo no está conectado a la red Wi-Fi de la bodega.", null) }
                            } else {
                                runOnUiThread { result.error("COMMUNICATION_ERROR", e.message, null) }
                            }
                        } catch (e: SocketTimeoutException) {
                            runOnUiThread { result.error("TIMEOUT", e.message, null) }
                        } catch (e: java.net.ConnectException) {
                            runOnUiThread { result.error("CONNECT_ERROR", e.message, null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("COMMUNICATION_ERROR", e.message, null) }
                        }
                    }
                }
                "transmitirZpl" -> {
                    val ip = call.argument<String>("ip") ?: "192.168.8.50"
                    val port = call.argument<Int>("port") ?: 9100
                    val zpl = call.argument<String>("zpl") ?: ""
                    val timeoutMs = call.argument<Int>("timeoutMs") ?: 3000

                    thread {
                        try {
                            val exito = ejecutarTransmisionZplEnWifi(ip, port, zpl, timeoutMs)
                            runOnUiThread { result.success(exito) }
                        } catch (e: IllegalStateException) {
                            if (e.message == "NO_WIFI") {
                                runOnUiThread { result.error("NO_WIFI", "El dispositivo no está conectado a la red Wi-Fi de la bodega.", null) }
                            } else {
                                runOnUiThread { result.error("COMMUNICATION_ERROR", e.message, null) }
                            }
                        } catch (e: SocketTimeoutException) {
                            runOnUiThread { result.error("TIMEOUT", e.message, null) }
                        } catch (e: java.net.ConnectException) {
                            runOnUiThread { result.error("CONNECT_ERROR", e.message, null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("COMMUNICATION_ERROR", e.message, null) }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun crearSocketEnRed(network: Network?, timeoutMs: Int): Socket {
        val socket = if (network != null) {
            try {
                val s = network.socketFactory.createSocket()
                network.bindSocket(s)
                s
            } catch (e: Exception) {
                val plain = Socket()
                try { network.bindSocket(plain) } catch (_: Exception) {}
                plain
            }
        } else {
            Socket()
        }
        socket.soTimeout = timeoutMs
        return socket
    }

    private fun ejecutarDiagnosticoHsEnWifi(ip: String, port: Int, timeoutMs: Int): String {
        val localNet = obtenerRedLocal()
            ?: throw IllegalStateException("NO_WIFI")

        val socket = crearSocketEnRed(localNet, timeoutMs)
        try {
            socket.connect(InetSocketAddress(ip, port), timeoutMs)
            val output: OutputStream = socket.getOutputStream()
            output.write("~HS\r\n".toByteArray(StandardCharsets.UTF_8))
            output.flush()

            val inputStream: InputStream = socket.getInputStream()
            val buffer = ByteArray(1024)
            val sb = StringBuilder()
            val startTime = System.currentTimeMillis()

            while (System.currentTimeMillis() - startTime < timeoutMs) {
                if (inputStream.available() > 0) {
                    val count = inputStream.read(buffer)
                    if (count > 0) {
                        val chunk = String(buffer, 0, count, StandardCharsets.UTF_8)
                        sb.append(chunk)
                        if (sb.contains("\u0003") || sb.split("\n").size >= 3) {
                            break
                        }
                    } else if (count == -1) {
                        break
                    }
                } else {
                    Thread.sleep(50)
                }
            }
            return sb.toString()
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }

    private fun ejecutarTransmisionZplEnWifi(ip: String, port: Int, zpl: String, timeoutMs: Int): Boolean {
        val localNet = obtenerRedLocal()
            ?: throw IllegalStateException("NO_WIFI")

        val socket = crearSocketEnRed(localNet, timeoutMs)
        try {
            socket.connect(InetSocketAddress(ip, port), timeoutMs)
            val output: OutputStream = socket.getOutputStream()
            val bytes = zpl.toByteArray(StandardCharsets.UTF_8)
            output.write(bytes)
            output.flush()
            return true
        } finally {
            try { socket.close() } catch (_: Exception) {}
        }
    }
}
