import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/widgets/cresal_logo.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../routes/app_routes.dart';
import '../../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SPLASH SCREEN — Punto de entrada de la app
// Lee el token guardado y decide hacia dónde navegar:
//   • Token presente → /home
//   • Sin token      → /login
// ─────────────────────────────────────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Animación de fade-in del logo
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();

    // Verificar sesión después del fade
    _checkSession();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _checkSession() async {
    // Mínimo de tiempo de splash para que el logo sea visible
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    try {
      final token = await AuthService.getToken();

      if (!mounted) return;

      if (token != null && token.isNotEmpty) {
        await AuthService.getAuthUser();
        final idRol = await AuthService.getIdRol();
        ThemeController.actualizarPorRol(idRol);
        if (!mounted) return;
        final targetRoute = AppRoutes.getHomeRouteForRole(idRol);
        Navigator.of(context).pushReplacementNamed(targetRoute);
      } else {
        final isEnrolled = await AuthService.isTerminalEnrolled();
        if (!mounted) return;
        if (isEnrolled) {
          Navigator.of(context).pushReplacementNamed('/login');
        } else {
          Navigator.of(context).pushReplacementNamed('/enrolamiento');
        }
      }
    } catch (e) {
      debugPrint("⚠️ [SPLASH] Error al verificar sesión en KeyStore: $e. Redirigiendo a pantalla de acceso.");
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/enrolamiento');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo corporativo
              const CresalLogo(size: 100),
              const SizedBox(height: 24),
              Text(
                'CRESAL',
                style: AppTypography.headline.copyWith(fontSize: 30, letterSpacing: 8),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sistema Industrial de Operaciones',
                style: AppTypography.small,
              ),
              const SizedBox(height: 48),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  color: AppPalette.primary,
                  strokeWidth: 2.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
