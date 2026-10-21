import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/theme/tokens/app_palette.dart';
import '../../../core/services/api_service.dart';
import '../../alertas/services/bodega_polling_service.dart';
import '../../ventas/controllers/cart_controller.dart';
import '../../../core/theme/theme_controller.dart';
import '../models/auth_user_model.dart';

// Claves de almacenamiento seguro para sesión
const String _tokenKey = 'access_token';
const String _rolKey = 'user_rol';
const String _idRolKey = 'user_id_rol';
const String _sucursalKey = 'user_sucursal_id';
const String _sucursalNombreKey = 'user_sucursal_nombre';
const String _nombreUsuarioKey = 'user_nombre_completo';
const String _userEmailKey = 'user_email';
const String _userModelKey = 'user_model_json';

// Claves de almacenamiento seguro para enrolamiento de terminal
const String _enrolledUserIdKey = 'enrolled_user_id';
const String _enrolledUserEmailKey = 'enrolled_user_email';
const String _enrolledUserNameKey = 'enrolled_user_name';

// ─────────────────────────────────────────────────────────────────────────────
// MODELOS DE RESULTADO (evita mezclar lógica HTTP en la UI)
// ─────────────────────────────────────────────────────────────────────────────
enum AuthErrorType {
  none,
  network,      // Wi-Fi / Conexión / Servidor inalcanzable
  credentials,  // Email o contraseña incorrectos, o PIN incorrecto
  server,       // Falla 500, base de datos u otro error del backend
}

class AuthResult {
  final bool success;
  final String? errorMessage;
  final AuthErrorType errorType;
  final AuthUserModel? user;

  const AuthResult.ok([this.user])
      : success = true,
        errorMessage = null,
        errorType = AuthErrorType.none;

  const AuthResult.fail(
    this.errorMessage, {
    this.errorType = AuthErrorType.server,
  })  : success = false,
        user = null;

  bool get isNetworkError => errorType == AuthErrorType.network;
  bool get isCredentialsError => errorType == AuthErrorType.credentials;
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICIO PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────
class AuthService {
  /// Caché en memoria del usuario autenticado (evita estados "Cargando..." o parpadeos en vistas)
  static AuthUserModel? _currentUserCache;

  /// Retorna inmediatamente el modelo de usuario cacheado en memoria si existe
  static AuthUserModel? get cachedUser => _currentUserCache;

  /// Permite inyectar o limpiar el usuario en memoria para pruebas unitarias
  @visibleForTesting
  static void setMockUserCache(AuthUserModel? user) {
    _currentUserCache = user;
  }

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  /// Lectura segura de storage que previene crasheos por claves corruptas de Android KeyStore (BadPaddingException).
  static Future<String?> _readSafe(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint("⚠️ [AUTH_STORAGE] Error leyendo clave '$key': $e. Limpiando clave corrupta...");
      try {
        await _storage.delete(key: key);
      } catch (_) {}
      return null;
    }
  }

  /// Captura excepciones de red y genera una respuesta limpia sin filtrar IPs ni trazas técnicas.
  static AuthResult _manejarExcepcionAuth(Object e) {
    final str = e.toString().toLowerCase();
    if (e is SocketException ||
        e is TimeoutException ||
        e is http.ClientException ||
        str.contains('socketexception') ||
        str.contains('clientexception') ||
        str.contains('connection refused') ||
        str.contains('failed host lookup') ||
        str.contains('no address associated') ||
        str.contains('connection reset') ||
        str.contains('network') ||
        str.contains('tiempo de espera') ||
        str.contains('timeout')) {
      return const AuthResult.fail(
        'No se pudo conectar con el servidor. Verifique su conexión Wi-Fi o de red corporativa.',
        errorType: AuthErrorType.network,
      );
    }
    return const AuthResult.fail(
      'Ocurrió un problema de comunicación con el servidor. Intente nuevamente.',
      errorType: AuthErrorType.server,
    );
  }

  /// Enrola el terminal vinculándolo al usuario corporativo vía email y contraseña.
  /// Guarda el JWT de sesión y fija el `enrolled_user_id`, `enrolled_user_email` y `enrolled_user_name`.
  static Future<AuthResult> enrolarTerminal(String email, String password) async {
    try {
      final uri = Uri.parse('${ApiConstants.authEndpoint}/login');

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim().toLowerCase(),
              'password': password,
            }),
          )
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw Exception('Tiempo de espera agotado al conectar con el servidor.'),
          );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final token = body['access_token'] as String;
        final usuarioMap = body['usuario'] as Map<String, dynamic>?;
        String rolText = usuarioMap?['nombre_rol']?.toString() ??
            usuarioMap?['rol']?['nombre_rol']?.toString() ??
            '';
        final dynamic rawIdRol = usuarioMap?['id_rol'] ?? usuarioMap?['rol']?['id_rol'];
        final int? idRol = rawIdRol is int ? rawIdRol : int.tryParse(rawIdRol?.toString() ?? '');

        if (rolText.isEmpty && idRol != null) {
          if (idRol == 1) rolText = 'Bodeguero';
          if (idRol == 2) rolText = 'Vendedor';
          if (idRol == 3) rolText = 'Caja';
          if (idRol == 4) rolText = 'Gerente';
          if (idRol == 5) rolText = 'Administrador';
          if (idRol == 6) rolText = 'Jefe de Ventas';
          if (idRol == 7) rolText = 'Vendedor Online';
          if (idRol == 8) rolText = 'Auditor';
          if (idRol == 9) rolText = 'Recepción';
        }
        final sucursalId = usuarioMap?['id_sucursal']?.toString();
        final sucursalNombre = usuarioMap?['nombre_sucursal']?.toString() ??
            usuarioMap?['sucursal']?['nombre_sucursal']?.toString() ??
            '';
        final nombres = usuarioMap?['nombres']?.toString() ?? '';
        final apellidos = usuarioMap?['apellidos']?.toString() ?? '';
        final rutUsuario = usuarioMap?['rut_usuario']?.toString() ?? '';
        final userEmail = usuarioMap?['email']?.toString() ?? email.trim().toLowerCase();
        final idUsuario = usuarioMap?['id_usuario']?.toString() ?? '';
        final nombreCompleto = '$nombres $apellidos'.trim();

        final userModel = AuthUserModel(
          idUsuario: idUsuario,
          rutUsuario: rutUsuario,
          nombres: nombres,
          apellidos: apellidos,
          email: userEmail,
          idRol: idRol ?? 0,
          nombreRol: rolText,
          idSucursal: int.tryParse(sucursalId ?? '1') ?? 1,
        );

        // Guardar token, rol, id_rol, sucursal, email y modelo de usuario
        await _storage.write(key: _tokenKey, value: token);
        await _storage.write(key: _rolKey, value: rolText);
        if (idRol != null) {
          await _storage.write(key: _idRolKey, value: idRol.toString());
        }
        if (sucursalId != null) {
          await _storage.write(key: _sucursalKey, value: sucursalId);
        }
        if (sucursalNombre.isNotEmpty) {
          await _storage.write(key: _sucursalNombreKey, value: sucursalNombre);
        }
        if (nombreCompleto.isNotEmpty) {
          await _storage.write(key: _nombreUsuarioKey, value: nombreCompleto);
        }
        if (userEmail.isNotEmpty) {
          await _storage.write(key: _userEmailKey, value: userEmail);
        }
        await _storage.write(key: _userModelKey, value: jsonEncode(userModel.toJson()));
        _currentUserCache = userModel;

        // Guardar datos de enrolamiento del terminal
        if (idUsuario.isNotEmpty) {
          await _storage.write(key: _enrolledUserIdKey, value: idUsuario);
        }
        if (userEmail.isNotEmpty) {
          await _storage.write(key: _enrolledUserEmailKey, value: userEmail);
        }
        if (nombreCompleto.isNotEmpty) {
          await _storage.write(key: _enrolledUserNameKey, value: nombreCompleto);
        }

        _loggearExpiracionToken(token);
        unawaited(CartController.instance.cargarDesdeAlmacenamiento());
        return AuthResult.ok(userModel);
      }

      if (response.statusCode == 401) {
        return const AuthResult.fail(
          'Credenciales inválidas, verifica tu correo o contraseña.',
          errorType: AuthErrorType.credentials,
        );
      }

      final detail = body['message_user'] ?? body['detail'] ?? 'Error del servidor al enrolar terminal.';
      return AuthResult.fail(detail.toString(), errorType: AuthErrorType.server);
    } on Object catch (e) {
      return _manejarExcepcionAuth(e);
    }
  }

  /// Envía el PIN junto al ID del usuario previamente enrolado al backend.
  /// Persiste el nuevo JWT de sesión y los datos del usuario si la autenticación es exitosa.
  static Future<AuthResult> loginConPin(String pin, [String? idUsuarioEnrolado]) async {
    try {
      final targetUserId = idUsuarioEnrolado ?? await getEnrolledUserId();
      if (targetUserId == null || targetUserId.isEmpty) {
        return const AuthResult.fail('Terminal no enrolada, contacte a su administrador.');
      }

      final uri = Uri.parse('${ApiConstants.authEndpoint}/login-pin');

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'pin_acceso': pin,
              'id_usuario': targetUserId,
            }),
          )
          .timeout(
            const Duration(seconds: 45),
            onTimeout: () => throw Exception('Tiempo de espera agotado al verificar PIN.'),
          );

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        final token = body['access_token'] as String;
        final usuarioMap = body['usuario'] as Map<String, dynamic>?;
        String rolText = usuarioMap?['nombre_rol']?.toString() ??
            usuarioMap?['rol']?['nombre_rol']?.toString() ??
            '';
        final dynamic rawIdRol = usuarioMap?['id_rol'] ?? usuarioMap?['rol']?['id_rol'];
        final int? idRol = rawIdRol is int ? rawIdRol : int.tryParse(rawIdRol?.toString() ?? '');

        if (rolText.isEmpty && idRol != null) {
          if (idRol == 1) rolText = 'Bodeguero';
          if (idRol == 2) rolText = 'Vendedor';
          if (idRol == 3) rolText = 'Caja';
          if (idRol == 4) rolText = 'Gerente';
          if (idRol == 5) rolText = 'Administrador';
          if (idRol == 6) rolText = 'Jefe de Ventas';
          if (idRol == 7) rolText = 'Vendedor Online';
          if (idRol == 8) rolText = 'Auditor';
          if (idRol == 9) rolText = 'Recepción';
        }
        final sucursalId = usuarioMap?['id_sucursal']?.toString();
        final sucursalNombre = usuarioMap?['nombre_sucursal']?.toString() ??
            usuarioMap?['sucursal']?['nombre_sucursal']?.toString() ??
            '';
        final nombres = usuarioMap?['nombres']?.toString() ?? '';
        final apellidos = usuarioMap?['apellidos']?.toString() ?? '';
        final rutUsuario = usuarioMap?['rut_usuario']?.toString() ?? '';
        final email = usuarioMap?['email']?.toString() ?? '';
        final idUsuario = usuarioMap?['id_usuario']?.toString() ?? targetUserId;
        final nombreCompleto = '$nombres $apellidos'.trim();

        final userModel = AuthUserModel(
          idUsuario: idUsuario,
          rutUsuario: rutUsuario,
          nombres: nombres,
          apellidos: apellidos,
          email: email,
          idRol: idRol ?? 0,
          nombreRol: rolText,
          idSucursal: int.tryParse(sucursalId ?? '1') ?? 1,
        );

        // Guardar token y datos de sesión activa
        await _storage.write(key: _tokenKey, value: token);
        await _storage.write(key: _rolKey, value: rolText);
        if (idRol != null) {
          await _storage.write(key: _idRolKey, value: idRol.toString());
        }
        if (sucursalId != null) {
          await _storage.write(key: _sucursalKey, value: sucursalId);
        }
        if (sucursalNombre.isNotEmpty) {
          await _storage.write(key: _sucursalNombreKey, value: sucursalNombre);
        }
        if (nombreCompleto.isNotEmpty) {
          await _storage.write(
            key: _nombreUsuarioKey,
            value: nombreCompleto,
          );
        }
        if (email.isNotEmpty) {
          await _storage.write(key: _userEmailKey, value: email);
        }
        await _storage.write(key: _userModelKey, value: jsonEncode(userModel.toJson()));
        _currentUserCache = userModel;

        // Asegurar que las claves de enrolamiento se mantengan persistidas
        await _storage.write(key: _enrolledUserIdKey, value: idUsuario);
        if (email.isNotEmpty) {
          await _storage.write(key: _enrolledUserEmailKey, value: email);
        }
        if (nombreCompleto.isNotEmpty) {
          await _storage.write(key: _enrolledUserNameKey, value: nombreCompleto);
        }

        _loggearExpiracionToken(token);
        unawaited(CartController.instance.cargarDesdeAlmacenamiento());
        return AuthResult.ok(userModel);
      }

      if (response.statusCode == 401) {
        return const AuthResult.fail(
          'PIN incorrecto para este terminal.',
          errorType: AuthErrorType.credentials,
        );
      }

      // Camino triste: el backend retornó un error (422, 500, etc.)
      final detail = body['message_user'] ?? body['detail'] ?? 'Error desconocido del servidor';
      return AuthResult.fail(detail.toString(), errorType: AuthErrorType.server);
    } on Object catch (e) {
      return _manejarExcepcionAuth(e);
    }
  }

  /// Recupera el ID del usuario previamente enrolado en este terminal.
  static Future<String?> getEnrolledUserId() => _readSafe(_enrolledUserIdKey);

  /// Recupera el email del usuario enrolado en este terminal.
  static Future<String?> getEnrolledUserEmail() => _readSafe(_enrolledUserEmailKey);

  /// Recupera el nombre completo del usuario enrolado en este terminal.
  static Future<String?> getEnrolledUserName() => _readSafe(_enrolledUserNameKey);

  /// Comprueba si el terminal actual cuenta con un usuario enrolado.
  static Future<bool> isTerminalEnrolled() async {
    final id = await getEnrolledUserId();
    return id != null && id.isNotEmpty;
  }

  /// Desenrola completamente el terminal eliminando tanto la sesión activa como el enrolamiento.
  static Future<void> desenrolarTerminal() async {
    await clearToken();
    await _storage.delete(key: _enrolledUserIdKey);
    await _storage.delete(key: _enrolledUserEmailKey);
    await _storage.delete(key: _enrolledUserNameKey);
  }

  /// Recupera el token almacenado (útil para inyectarlo en peticiones futuras).
  static Future<String?> getToken() => _readSafe(_tokenKey);

  /// Recupera el rol textual almacenado (ej. "Bodeguero", "Vendedor", "Caja", "Jefe de Ventas").
  static Future<String?> getRol() => _readSafe(_rolKey);

  /// Recupera el ID numérico del rol del usuario (ej. 1=Bodega, 2=Ventas, 3=Caja, 5=Admin, 6=Jefe).
  static Future<int?> getIdRol() async {
    final val = await _readSafe(_idRolKey);
    return val != null ? int.tryParse(val) : null;
  }

  /// Verifica si el usuario actual pertenece al rol Caja (id_rol == 3).
  static Future<bool> esCaja() async {
    final idRol = await getIdRol();
    if (idRol != null) return idRol == 3;
    final rol = await getRol();
    final rLower = rol?.toLowerCase() ?? '';
    return rLower == 'caja' || rLower == 'operario de caja';
  }

  /// Verifica si el usuario actual posee rol Administrador (id_rol == 5).
  static Future<bool> esAdmin() async {
    final idRol = await getIdRol();
    if (idRol != null) return idRol == 5;
    final rol = await getRol();
    final rLower = rol?.toLowerCase() ?? '';
    return rLower == 'administrador' || rLower == 'admin';
  }

  /// Verifica si el usuario actual posee rol Gerente (id_rol == 4) o Auditor / Gerente Auditor (id_rol == 8).
  static Future<bool> esGerente() async {
    final idRol = await getIdRol();
    if (idRol != null) return idRol == 4 || idRol == 8;
    final rol = await getRol();
    final rLower = rol?.toLowerCase() ?? '';
    return rLower == 'gerente' || rLower == 'auditor';
  }

  /// Verifica si el usuario actual posee rol Auditor / Gerente Solo Lectura (id_rol == 8).
  static Future<bool> esAuditor() async {
    final idRol = await getIdRol();
    if (idRol != null) return idRol == 8;
    final rol = await getRol();
    final rLower = rol?.toLowerCase() ?? '';
    return rLower == 'auditor';
  }

  /// Verifica si el usuario actual es un Auditor de Sucursal Satélite (id_rol == 8 y id_sucursal != 1).
  /// Estos usuarios tienen acceso restringido exclusivamente al inventario/catálogo para consulta de stock.
  static Future<bool> esAuditorSucursal() async {
    final auditor = await esAuditor();
    if (!auditor) return false;
    final sucursalId = await getSucursalId();
    return sucursalId != null && sucursalId != 1;
  }

  /// Determina de forma sincrónica e inmediata (0 ms) si el usuario en memoria RAM
  /// es un Auditor de Sucursal Satélite (id_rol == 8 y id_sucursal != 1).
  /// Útil para inicializar estados de UI en el Frame 0 sin parpadeos visuales (FOUC).
  static bool get esAuditorSucursalSync =>
      _currentUserCache != null &&
      _currentUserCache!.idRol == 8 &&
      _currentUserCache!.idSucursal != 1;

  /// Verifica si el usuario actual tiene permisos para tasar o fijar precios.
  /// Solo disponible para Gerencia General (4), Administrador (5) y Jefe de Ventas (6).
  /// Excluye al Auditor / Gerente Solo Lectura (8).
  static Future<bool> puedeTasar() async {
    final idRol = await getIdRol();
    if (idRol != null) return idRol == 4 || idRol == 5 || idRol == 6;
    final rol = await getRol();
    final rLower = rol?.toLowerCase() ?? '';
    return rLower == 'gerente' || rLower == 'administrador' || rLower == 'admin' || rLower == 'jefe de ventas';
  }

  /// Verifica si el usuario actual pertenece al módulo de ventas (Vendedor [2], Jefe de Ventas [6], Vendedor Online [7]).
  static Future<bool> esModuloVentas() async {
    final idRol = await getIdRol();
    if (idRol != null && (idRol == 2 || idRol == 6 || idRol == 7)) return true;
    final rol = await getRol();
    final rLower = rol?.toLowerCase() ?? '';
    return rLower == 'vendedor' ||
        rLower == 'vendedoronline' ||
        rLower == 'vendedor online' ||
        rLower == 'jefe de ventas';
  }

  /// Verifica si el usuario actual es VendedorOnline (id_rol == 7).
  static Future<bool> esVendedorOnline() async {
    final idRol = await getIdRol();
    if (idRol == 7) return true;
    final rol = await getRol();
    final rLower = rol?.toLowerCase() ?? '';
    return rLower == 'vendedoronline' || rLower == 'vendedor online';
  }

  /// Verifica si el usuario actual posee permisos de Jefe de Ventas (id_rol == 6).
  static Future<bool> esJefeDeVentas() async {
    final idRol = await getIdRol();
    if (idRol == 6) return true;
    final rol = await getRol();
    final rLower = rol?.toLowerCase() ?? '';
    return rLower == 'jefe de ventas';
  }

  /// Recupera el ID de sucursal del usuario autenticado (para Radar de Stock).
  static Future<int?> getSucursalId() async {
    final val = await _readSafe(_sucursalKey);
    return val != null ? int.tryParse(val) : null;
  }

  /// Alias de getSucursalId para compatibilidad
  static Future<int?> getIdSucursal() => getSucursalId();

  /// Recupera el nombre de la sucursal del usuario autenticado.
  static Future<String?> getNombreSucursal() =>
      _readSafe(_sucursalNombreKey);

  /// Recupera el nombre completo del usuario autenticado de forma rápida.
  static Future<String?> getNombreUsuario() async {
    if (_currentUserCache != null && _currentUserCache!.nombres.isNotEmpty) {
      return '${_currentUserCache!.nombres} ${_currentUserCache!.apellidos}'.trim();
    }
    return _readSafe(_nombreUsuarioKey);
  }

  /// Recupera el correo electrónico del usuario autenticado (sin hardcodear datos de sesión).
  static Future<String?> getEmailUsuario() async {
    if (_currentUserCache != null && _currentUserCache!.email.isNotEmpty) {
      return _currentUserCache!.email;
    }
    final direct = await _readSafe(_userEmailKey);
    if (direct != null && direct.isNotEmpty) return direct;

    final user = await getAuthUser();
    if (user != null && user.email.isNotEmpty) return user.email;

    return _readSafe(_enrolledUserEmailKey);
  }

  /// Recupera el modelo completo de sesión AuthUserModel si está disponible.
  static Future<AuthUserModel?> getAuthUser() async {
    if (_currentUserCache != null) return _currentUserCache;

    final jsonStr = await _readSafe(_userModelKey);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        _currentUserCache = AuthUserModel.fromJson(map);
        return _currentUserCache;
      } catch (_) {}
    }
    // Reconstruir con claves sueltas si no existe el JSON compuesto
    final token = await getToken();
    if (token == null) return null;
    final idRol = await getIdRol() ?? 0;
    final rol = await getRol() ?? '';
    final nombreCompleto = await getNombreUsuario() ?? '';
    final email = await _readSafe(_userEmailKey) ?? await _readSafe(_enrolledUserEmailKey) ?? '';
    final sucursalId = await getSucursalId() ?? 1;

    final recontructed = AuthUserModel(
      idUsuario: '',
      rutUsuario: '',
      nombres: nombreCompleto,
      apellidos: '',
      email: email,
      idRol: idRol,
      nombreRol: rol,
      idSucursal: sucursalId,
    );
    _currentUserCache = recontructed;
    return recontructed;
  }

  /// Retorna true si el usuario autenticado posee rol de Recepción Patio (id_rol == 9).
  static Future<bool> esRecepcion() async {
    final idRol = await getIdRol();
    return idRol == 9;
  }

  /// Elimina el token, rol y datos de sesión activa (para logout o sesiones expiradas),
  /// liberando las reservas del carrito en backend y preservando la vinculación/enrolamiento del terminal.
  static Future<void> clearToken() async {
    _currentUserCache = null;
    try {
      await CartController.instance.liberarYVaciarEnBackend();
    } catch (_) {
      CartController.instance.vaciarCarrito();
    }
    ThemeController.reset();
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _rolKey);
    await _storage.delete(key: _idRolKey);
    await _storage.delete(key: _sucursalKey);
    await _storage.delete(key: _sucursalNombreKey);
    await _storage.delete(key: _nombreUsuarioKey);
    await _storage.delete(key: _userEmailKey);
    await _storage.delete(key: _userModelKey);
  }

  /// Alias de clearToken para logout explícito
  static Future<void> logout() => clearToken();

  /// Manejador global invocado cuando se detecta un 401 Unauthorized
  /// Invalida las claves de sesión activa sin destruir ni vaciar el carrito del usuario,
  /// permitiendo que al reingresar el PIN en el terminal conserve sus productos intactos.
  static Future<void> manejarSesionExpirada() async {
    if (kDebugMode) {
      debugPrint('[AUTH] 401 detectado -> Redirigiendo automáticamente a pantalla de PIN sin vaciar carrito');
    }
    _currentUserCache = null;
    ThemeController.reset();
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _rolKey);
    await _storage.delete(key: _idRolKey);
    await _storage.delete(key: _sucursalKey);
    await _storage.delete(key: _sucursalNombreKey);
    await _storage.delete(key: _nombreUsuarioKey);
    await _storage.delete(key: _userEmailKey);
    await _storage.delete(key: _userModelKey);

    BodegaPollingService.instance.reset();

    // Redirigir a login
    final navigator = ApiService.navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushNamedAndRemoveUntil('/login', (route) => false);
    }

    // Mostrar SnackBar explicativo
    final messenger = ApiService.scaffoldMessengerKey.currentState;
    if (messenger != null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'Tu sesión ha expirado. Ingresa tu PIN nuevamente',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppPalette.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  /// Comprueba si existe una sesión activa actualmente (token almacenado no nulo ni vacío).
  static Future<bool> hasActiveSession() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  /// Manejador global invocado tras 10 minutos de inactividad de usuario en cualquier vista o rol.
  /// Cierra la pantalla y navegación actual sin guardar el estado en pantalla ("no parado donde estaba")
  /// y redirige limpiamente a la pantalla de PIN (/login).
  static Future<void> bloquearPorInactividad() async {
    if (kDebugMode) {
      debugPrint(
        '[AUTH] ⏰ Inactividad de 10 min detectada -> Redirigiendo a PIN y cerrando vista actual.',
      );
    }
    _currentUserCache = null;
    ThemeController.reset();
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userModelKey);

    BodegaPollingService.instance.reset();

    // Redirigir a login cerrando cualquier subpantalla, modal o diálogo previo
    final navigator = ApiService.navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushNamedAndRemoveUntil('/login', (route) => false);
    }

    // Mostrar SnackBar explicativo
    final messenger = ApiService.scaffoldMessengerKey.currentState;
    if (messenger != null) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'Sesión bloqueada por inactividad (10 min). Ingresa tu PIN.',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppPalette.secondary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  /// Extrae e imprime la fecha/hora de expiración del token JWT de forma segura sin exponer credenciales completas.
  static void _loggearExpiracionToken(String token) {
    if (!kDebugMode) return;
    try {
      final parts = token.split('.');
      if (parts.length >= 2) {
        String normalized = base64Url.normalize(parts[1]);
        final payloadString = utf8.decode(base64Url.decode(normalized));
        final payload = jsonDecode(payloadString) as Map<String, dynamic>;
        if (payload.containsKey('exp')) {
          final expSeconds = payload['exp'] as int;
          final expDate = DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000).toLocal();
          final formatted = expDate.toIso8601String().replaceFirst('T', ' ').substring(0, 19);
          debugPrint('[AUTH] Token válido hasta: $formatted');
        }
      }
    } catch (_) {}
  }
}
