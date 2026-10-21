import 'package:flutter/material.dart';
import '../services/app_update_service.dart';
import '../theme/tokens/app_palette.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
  });

  static Future<void> show(BuildContext context, UpdateInfo updateInfo) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UpdateDialog(updateInfo: updateInfo),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  final AppUpdateService _updateService = AppUpdateService();
  bool _isDownloading = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  String _statusText = 'Descargando actualización...';

  Future<void> _startDownload() async {
    final downloadUrl = widget.updateInfo.downloadUrl;
    if (downloadUrl == null) {
      setState(() {
        _errorMessage = 'No hay enlace de descarga disponible para este dispositivo.';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _statusText = 'Iniciando descarga...';
    });

    try {
      final file = await _updateService.downloadUpdate(
        downloadUrl: downloadUrl,
        onProgress: (progress, received, total) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _receivedBytes = received;
              _totalBytes = total;
              _statusText = 'Descargando actualización (${(progress * 100).toStringAsFixed(0)}%)...';
            });
          }
        },
      );

      if (!mounted) return;

      if (file != null && await file.exists()) {
        setState(() {
          _statusText = 'Instalando actualización...';
        });

        final success = await _updateService.installUpdate(file);
        if (mounted) {
          setState(() {
            _isDownloading = false;
            if (!success) {
              _errorMessage = 'No se pudo iniciar el instalador automáticamente. Verifica los permisos de instalación.';
            }
          });
        }
      } else {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Error al descargar el paquete de instalación. Reintenta.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Ocurrió un error inesperado: $e';
        });
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppPalette.surface : AppPalette.surfaceLight;
    final textColor = isDark ? AppPalette.textPrimary : AppPalette.textPrimaryLight;
    final subtextColor = isDark ? AppPalette.textSecondary : AppPalette.textSecondaryLight;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Encabezado con Icono
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppPalette.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.system_update_rounded,
                  size: 44,
                  color: AppPalette.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Título
            Center(
              child: Text(
                '¡Nueva versión disponible!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Badge de Versión
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppPalette.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppPalette.primary.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'v${widget.updateInfo.currentVersion}',
                      style: TextStyle(color: subtextColor, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.0),
                      child: Icon(Icons.arrow_forward_rounded, size: 16, color: AppPalette.primary),
                    ),
                    Text(
                      'v${widget.updateInfo.latestVersion}',
                      style: const TextStyle(
                        color: AppPalette.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Novedades
            Text(
              'Novedades:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppPalette.background : AppPalette.backgroundLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? Colors.white10 : AppPalette.borderLight,
                ),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.updateInfo.releaseNotes.trim().isEmpty
                      ? 'Mejoras de rendimiento y corrección de errores.'
                      : widget.updateInfo.releaseNotes,
                  style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Mensaje de Error (si ocurre)
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppPalette.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppPalette.error.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppPalette.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppPalette.error, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Barra de progreso interactiva (si está descargando)
            if (_isDownloading) ...[
              Text(
                _statusText,
                style: TextStyle(fontSize: 13, color: subtextColor, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _progress >= 0 ? _progress : null,
                backgroundColor: isDark ? Colors.white12 : Colors.black12,
                valueColor: const AlwaysStoppedAnimation<Color>(AppPalette.primary),
                borderRadius: BorderRadius.circular(6),
                minHeight: 8,
              ),
              const SizedBox(height: 8),
              if (_totalBytes > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(_progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)}',
                      style: TextStyle(fontSize: 12, color: subtextColor),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
            ],

            // Acciones / Botones
            if (!_isDownloading)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Más tarde',
                        style: TextStyle(color: subtextColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppPalette.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      onPressed: _startDownload,
                      child: const Text(
                        'Actualizar',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Helper para invocar la comprobación desde cualquier parte de la app
class AppUpdateChecker {
  static Future<void> check(BuildContext context, {bool showIfUpToDate = false}) async {
    try {
      final service = AppUpdateService();
      final updateInfo = await service.checkForUpdates();

      if (!context.mounted) return;

      if (updateInfo != null && updateInfo.updateAvailable) {
        UpdateDialog.show(context, updateInfo);
      } else if (showIfUpToDate) {
        final currentVersion = await service.getCurrentVersion();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tu aplicación está al día (v$currentVersion).'),
            backgroundColor: AppPalette.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[AppUpdateChecker] Error: $e');
    }
  }
}
