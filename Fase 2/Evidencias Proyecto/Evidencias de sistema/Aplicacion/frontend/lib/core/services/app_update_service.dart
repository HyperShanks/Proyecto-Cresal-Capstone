import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../constants/api_constants.dart';

class UpdateInfo {
  final bool updateAvailable;
  final String latestVersion;
  final String currentVersion;
  final String releaseName;
  final String releaseNotes;
  final String? downloadUrl;
  final String? assetName;
  final int assetSize;

  UpdateInfo({
    required this.updateAvailable,
    required this.latestVersion,
    required this.currentVersion,
    required this.releaseName,
    required this.releaseNotes,
    this.downloadUrl,
    this.assetName,
    this.assetSize = 0,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json, String currentVersion) {
    final latest = json['latest_version']?.toString() ?? currentVersion;
    final isActuallyNewer = AppUpdateService.compareVersions(latest, currentVersion) > 0;
    final rawAvailable = json['update_available'] == true;

    return UpdateInfo(
      updateAvailable: rawAvailable && isActuallyNewer,
      latestVersion: latest,
      currentVersion: currentVersion,
      releaseName: json['release_name'] ?? 'Actualización disponible',
      releaseNotes: json['release_notes'] ?? 'Mejoras de estabilidad y rendimiento.',
      downloadUrl: json['download_url'],
      assetName: json['asset_name'],
      assetSize: json['asset_size'] ?? 0,
    );
  }
}

typedef UpdateProgressCallback = void Function(double progress, int received, int total);

class AppUpdateService {
  static final AppUpdateService _instance = AppUpdateService._internal();
  factory AppUpdateService() => _instance;
  AppUpdateService._internal();

  /// Versión actual declarada en el código fuente Dart (fuente de verdad)
  static const String appVersion = '1.0.10';
  static const String appBuildNumber = '11';
  static const String appFullVersion = '1.0.10+11';

  /// Convierte '1.0.2+3' o 'v1.0.2' en [major, minor, patch, build]
  static List<int> parseVersion(String vStr) {
    if (vStr.isEmpty) return [0, 0, 0, 0];
    final clean = vStr.replaceAll(RegExp(r'^[vV]'), '');
    final parts = clean.split('+');
    final semver = parts[0]
        .split('.')
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    while (semver.length < 3) {
      semver.add(0);
    }
    final buildNum = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return [...semver.take(3), buildNum];
  }

  /// Compara dos versiones semánticas (retorna 1 si v1 > v2, -1 si v1 < v2, 0 si iguales)
  static int compareVersions(String v1, String v2) {
    final t1 = parseVersion(v1);
    final t2 = parseVersion(v2);
    for (int i = 0; i < 4; i++) {
      if (t1[i] > t2[i]) return 1;
      if (t1[i] < t2[i]) return -1;
    }
    return 0;
  }

  /// Obtiene la versión actual de la aplicación (ej: "1.0.3+4")
  Future<String> getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final platVersion = '${info.version}+${info.buildNumber}';

      // Si la versión nativa del binario es inferior a la del código Dart en ejecución
      // (por ejemplo si CMake en Windows no recompiló el .exe al empaquetar),
      // se prioriza la versión más alta entre la nativa y la del código fuente Dart.
      if (compareVersions(appFullVersion, platVersion) > 0) {
        return appFullVersion;
      }
      return platVersion;
    } catch (e) {
      debugPrint('[AppUpdateService] Error al obtener PackageInfo: $e');
      return appFullVersion;
    }
  }

  /// Identifica la plataforma de ejecución
  String get platformName {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return 'other';
  }

  /// Consulta al backend si hay una actualización disponible
  Future<UpdateInfo?> checkForUpdates() async {
    if (kIsWeb) return null;
    final currentPlatform = platformName;
    if (currentPlatform != 'android' && currentPlatform != 'windows') {
      return null;
    }

    try {
      final currentVersion = await getCurrentVersion();
      final uri = Uri.parse(
        '${ApiConstants.updatesEndpoint}/check?current_version=$currentVersion&platform=$currentPlatform',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return UpdateInfo.fromJson(data, currentVersion);
      } else {
        debugPrint('[AppUpdateService] Error response status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error al verificar actualizaciones: $e');
      return null;
    }
  }

  /// Descarga el archivo de instalación informando el progreso en tiempo real
  Future<File?> downloadUpdate({
    required String downloadUrl,
    required UpdateProgressCallback onProgress,
  }) async {
    try {
      String fullUrl = downloadUrl;
      if (downloadUrl.startsWith('/')) {
        final baseUri = Uri.parse(ApiConstants.baseUrl);
        fullUrl = '${baseUri.scheme}://${baseUri.authority}$downloadUrl';
      }

      final request = http.Request('GET', Uri.parse(fullUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200 && response.statusCode != 302) {
        debugPrint('[AppUpdateService] Falló la descarga, código: ${response.statusCode}');
        return null;
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      // Obtener directorio temporal
      final tempDir = await getTemporaryDirectory();
      final isAndroid = Platform.isAndroid;
      final fileName = isAndroid ? 'cresal_update.apk' : 'Cresal_Setup.exe';
      final file = File('${tempDir.path}/$fileName');

      if (await file.exists()) {
        await file.delete();
      }

      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final progress = receivedBytes / totalBytes;
          onProgress(progress.clamp(0.0, 1.0), receivedBytes, totalBytes);
        } else {
          onProgress(-1.0, receivedBytes, 0); // Indeterminado
        }
      }

      await sink.flush();
      await sink.close();

      return file;
    } catch (e) {
      debugPrint('[AppUpdateService] Error durante la descarga: $e');
      return null;
    }
  }

  /// Ejecuta la instalación según la plataforma
  Future<bool> installUpdate(File file) async {
    try {
      if (Platform.isAndroid) {
        // En Android, abrir el APK mediante OpenFilex dispara el PackageInstaller nativo
        final result = await OpenFilex.open(
          file.path,
          type: 'application/vnd.android.package-archive',
        );
        debugPrint('[AppUpdateService] Resultado de instalación Android: ${result.message}');
        return result.type == ResultType.done;
      } else if (Platform.isWindows) {
        // En Windows, ejecutar el instalador generado por Inno Setup
        // /SILENT: sin interacción
        // /RESTARTAPPLICATIONS: reabre Cresal automáticamente al terminar
        await Process.start(
          file.path,
          ['/SILENT', '/RESTARTAPPLICATIONS'],
          mode: ProcessStartMode.detached,
        );

        // Salir de la app para liberar los DLLs y permitir la sobreescritura limpia
        exit(0);
      }
      return false;
    } catch (e) {
      debugPrint('[AppUpdateService] Error al ejecutar instalador: $e');
      return false;
    }
  }
}
