import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../auth/services/auth_service.dart';
import '../../../../core/widgets/update_dialog.dart';
import '../../../../core/services/app_update_service.dart';

/// Sidebar / Drawer lateral para el Módulo de Caja.
/// Diseñado con AppPalette.tertiary (#004C89) y AppTypography.
class CajaDrawer extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int>? onSectionSelected;

  const CajaDrawer({
    super.key,
    this.selectedIndex = 0,
    this.onSectionSelected,
  });

  Future<void> _handleLogout(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppPalette.surfaceLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: AppPalette.neutral.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppPalette.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppPalette.error,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Cerrar Sesión',
                style: AppTypography.title.copyWith(
                  color: AppPalette.textPrimaryLight,
                ),
              ),
            ],
          ),
          content: Text(
            '¿Está seguro de que desea cerrar la sesión del turno de caja actual?',
            style: AppTypography.body.copyWith(
              color: AppPalette.textPrimaryLight,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'CANCELAR',
                style: AppTypography.button.copyWith(
                  color: AppPalette.textSecondaryLight,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'CERRAR SESIÓN',
                style: AppTypography.button.copyWith(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await AuthService.logout();
      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppPalette.tertiary,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Divider(
              color: Colors.white.withValues(alpha: 0.15),
              height: 1,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                children: [
                  _buildMenuItem(
                    context: context,
                    icon: Icons.point_of_sale_rounded,
                    title: 'Bandeja de Cobros',
                    subtitle: 'Órdenes pendientes de pago',
                    isSelected: selectedIndex == 0,
                    onTap: () {
                      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                        Navigator.of(context).pop();
                      }
                      onSectionSelected?.call(0);
                    },
                  ),
                  const SizedBox(height: 6),
                  _buildMenuItem(
                    context: context,
                    icon: Icons.history_edu_rounded,
                    title: 'Historial de Órdenes y Pagos',
                    subtitle: 'Consultas y comprobantes',
                    isSelected: selectedIndex == 1,
                    onTap: () {
                      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                        Navigator.of(context).pop();
                      }
                      onSectionSelected?.call(1);
                    },
                  ),
                  const SizedBox(height: 6),
                  _buildMenuItem(
                    context: context,
                    icon: Icons.contact_support_rounded,
                    title: 'Tickets de Soporte',
                    subtitle: 'Reporte de incidencias',
                    isSelected: selectedIndex == 2,
                    onTap: () {
                      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                        Navigator.of(context).pop();
                      }
                      if (onSectionSelected != null) {
                        onSectionSelected!(2);
                      } else {
                        Navigator.of(context).pushNamed('/tickets');
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  _buildMenuItem(
                    context: context,
                    icon: Icons.system_update_alt_rounded,
                    title: 'Buscar Actualizaciones',
                    subtitle: 'Comprobar nueva versión',
                    isSelected: false,
                    onTap: () {
                      if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                        Navigator.of(context).pop();
                      }
                      AppUpdateChecker.check(context, showIfUpToDate: true);
                    },
                  ),
                ],
              ),
            ),
            Divider(
              color: Colors.white.withValues(alpha: 0.15),
              height: 1,
            ),
            _buildLogoutButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return FutureBuilder<Map<String, String?>>(
      future: _loadUserData(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final nombre = data?['nombre'] ?? 'Operario de Caja';
        final sucursal = data?['sucursal'] ?? 'Sucursal Casa Matriz';
        final rol = data?['rol'] ?? 'CAJA';

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppPalette.tertiary,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppPalette.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre,
                          style: AppTypography.title.copyWith(
                            fontSize: 15,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            rol.toUpperCase(),
                            style: AppTypography.small.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.storefront_rounded,
                    size: 15,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      sucursal,
                      style: AppTypography.small.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, String?>> _loadUserData() async {
    final nombre = await AuthService.getNombreUsuario();
    final sucursal = await AuthService.getNombreSucursal();
    final rol = await AuthService.getRol();
    return {
      'nombre': (nombre != null && nombre.isNotEmpty) ? nombre : 'Operario de Caja',
      'sucursal': (sucursal != null && sucursal.isNotEmpty) ? sucursal : 'Sucursal Activa',
      'rol': (rol != null && rol.isNotEmpty) ? rol : 'CAJA',
    };
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.75),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.body.copyWith(
                        color: Colors.white,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.small.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 13,
                  color: Colors.white,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                foregroundColor: Colors.white,
                backgroundColor: AppPalette.error.withValues(alpha: 0.25),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: AppPalette.error.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
              ),
              icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.white),
              label: Text(
                'CERRAR SESIÓN',
                style: AppTypography.button.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              onPressed: () => _handleLogout(context),
            ),
          ),
          const SizedBox(height: 10),
          FutureBuilder<String>(
            future: AppUpdateService().getCurrentVersion(),
            builder: (context, snapshot) {
              return Center(
                child: Text(
                  'Cresal App v${snapshot.data ?? "..."}',
                  style: AppTypography.small.copyWith(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
