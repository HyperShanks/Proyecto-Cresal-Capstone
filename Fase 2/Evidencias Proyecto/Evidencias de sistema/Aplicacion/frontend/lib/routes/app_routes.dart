import 'package:flutter/material.dart';
import '../features/auth/presentation/screens/enrolamiento_screen.dart';
import '../features/auth/presentation/screens/pin_login_screen.dart';
import '../features/home/presentation/screens/home_screen.dart';
import '../features/caja/presentation/screens/caja_main_screen.dart';
import '../features/ventas/presentation/screens/ventas_main_screen.dart';
import '../features/recepcion/presentation/screens/recepcion_home_screen.dart';
import '../features/recepcion/presentation/screens/recepcion_vehiculo_screen.dart';
import '../features/tickets/presentation/screens/tickets_screen.dart';
import '../features/paletizado/presentation/screens/paletizado_screen.dart';
import '../features/paletizado/presentation/screens/etiqueta_preview_screen.dart';
import '../features/paletizado/presentation/screens/forzar_ingreso_screen.dart';
import '../features/paletizado/services/paletizado_service.dart';
import '../features/alertas/presentation/screens/alertas_screen.dart';
import '../features/inventario/presentation/screens/buscador_screen.dart';
import '../features/ventas/presentation/screens/catalogo_screen.dart';
import '../features/ventas/presentation/screens/checkout_crm_screen.dart';
import '../features/ventas/presentation/screens/bandeja_precios_screen.dart';
import '../features/ventas/presentation/screens/entregas_envios_screen.dart';
import '../features/ventas/presentation/screens/checkout_wizard_screen.dart';
import '../features/gerencia/presentation/screens/dashboard_gerencia_view.dart';

/// Registro central de rutas y guardas de seguridad RBAC.
class AppRoutes {
  static const String enrolamiento = '/enrolamiento';
  static const String login = '/login';
  static const String home = '/home';
  static const String ventasMain = '/ventas_main';
  static const String caja = '/caja';
  static const String gerencia = '/gerencia';
  static const String recepcion = '/recepcion';
  static const String recepcionRegistro = '/recepcion/registro';
  static const String tickets = '/tickets';
  static const String paletizado = '/paletizado';
  static const String paletizadoDetallePrefix = '/paletizado/detalle';
  static const String etiquetaPreview = '/etiqueta-preview';
  static const String alertas = '/alertas';
  static const String buscador = '/buscador';
  static const String catalogo = '/catalogo';
  static const String checkoutCrm = '/checkout_crm';
  static const String checkoutWizard = '/checkout_wizard';
  static const String bandejaPrecios = '/bandeja_precios';
  static const String entregasEnvios = '/entregas-envios';
  static const String reingresos = '/reingresos';
  static const String forzarIngreso = '/forzar-ingreso';

  /// Rutas públicas y comunes a cualquier estado de autenticación.
  static const List<String> _publicAndCommonRoutes = [
    enrolamiento,
    login,
    tickets,
    '/',
  ];

  /// Rutas autorizadas para Bodeguero (id_rol == 1).
  static const List<String> _bodegaRoutes = [
    home,
    paletizado,
    etiquetaPreview,
    buscador,
    alertas,
    reingresos,
    forzarIngreso,
  ];

  /// Rutas autorizadas para Recepción de Patio (id_rol == 9).
  static const List<String> _recepcionRoutes = [
    recepcion,
    recepcionRegistro,
  ];

  /// Rutas autorizadas para Vendedor (id_rol == 2, 7) y Jefe de Ventas (id_rol == 6).
  static const List<String> _ventasRoutes = [
    ventasMain,
    catalogo,
    '/carrito',
    checkoutCrm,
    checkoutWizard,
    bandejaPrecios,
    entregasEnvios,
  ];

  /// Rutas autorizadas para Caja (id_rol == 3).
  static const List<String> _cajaRoutes = [
    caja,
  ];

  /// Retorna la ruta inicial o panel principal correspondiente a un rol (SSOT).
  static String getHomeRouteForRole(int? idRol) {
    if (idRol == 9) return recepcion;
    if (idRol == 4 || idRol == 8) return gerencia;
    if (idRol == 3) return caja;
    if (idRol == 2 || idRol == 6 || idRol == 7) return ventasMain;
    return home;
  }

  /// Valida si una ruta específica está permitida para un rol determinado según el RBAC.
  static bool isRouteAllowedForRole(int? idRol, String route) {
    // Rutas públicas / de soporte siempre permitidas
    if (_publicAndCommonRoutes.contains(route)) {
      return true;
    }

    // Sin rol autenticado: no tiene acceso a rutas privadas
    if (idRol == null) {
      return false;
    }

    // Administrador (5) y Gerente General (4): Acceso global
    if (idRol == 4 || idRol == 5) {
      return true;
    }

    // Auditor / Gerente Solo Lectura (8): Acceso restringido exclusivamente a vistas gerenciales
    if (idRol == 8) {
      return route == gerencia;
    }

    // Caja (id_rol == 3)
    if (idRol == 3) {
      return _cajaRoutes.contains(route);
    }

    // Recepción Patio (id_rol == 9)
    if (idRol == 9) {
      return _recepcionRoutes.contains(route);
    }

    // Bodeguero (id_rol == 1)
    if (idRol == 1) {
      if (route.startsWith(paletizadoDetallePrefix)) return true;
      return _bodegaRoutes.contains(route);
    }

    // Vendedor (2, 7) y Jefe de Ventas (6)
    if (idRol == 2 || idRol == 6 || idRol == 7) {
      return _ventasRoutes.contains(route);
    }

    return false;
  }

  /// Manejador de rutas dinámicas (/paletizado/detalle/{id}).
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    if (settings.name != null && settings.name!.startsWith('$paletizadoDetallePrefix/')) {
      final id = settings.name!.substring('$paletizadoDetallePrefix/'.length);
      return MaterialPageRoute(
        builder: (context) => PaletizadoScreen(numeroIngresoInicial: id),
        settings: settings,
      );
    }
    return null;
  }

  /// Mapa global de rutas de la aplicación.
  static Map<String, WidgetBuilder> getRoutes() {
    return {
      enrolamiento: (context) => const EnrolamientoScreen(),
      login: (context) => const PinLoginScreen(),
      home: (context) => const HomeScreen(),
      caja: (context) => const CajaMainScreen(),
      gerencia: (context) => const DashboardGerenciaView(),
      ventasMain: (context) => const VentasMainScreen(),
      recepcion: (context) => const RecepcionHomeScreen(),
      recepcionRegistro: (context) => const RecepcionVehiculoScreen(),
      tickets: (context) => const TicketsScreen(),
      paletizado: (context) {
        final args = ModalRoute.of(context)?.settings.arguments as String?;
        return PaletizadoScreen(numeroIngresoInicial: args);
      },
      etiquetaPreview: (context) => const EtiquetaPreviewScreen(),
      alertas: (context) => const AlertasScreen(),
      buscador: (context) => const BuscadorScreen(),
      catalogo: (context) => const CatalogoScreen(),
      checkoutCrm: (context) => const CheckoutCrmScreen(),
      checkoutWizard: (context) => const CheckoutWizardScreen(),
      bandejaPrecios: (context) => const BandejaPreciosScreen(),
      entregasEnvios: (context) => const EntregasEnviosScreen(),
      reingresos: (context) => const AlertasScreen(),
      forzarIngreso: (context) {
        final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>;
        return ForzarIngresoScreen(
          vehiculoData: args,
          paletizadoService: PaletizadoService(), // Import it if needed, or I'll just add the import at top
        );
      },
    };
  }
}

