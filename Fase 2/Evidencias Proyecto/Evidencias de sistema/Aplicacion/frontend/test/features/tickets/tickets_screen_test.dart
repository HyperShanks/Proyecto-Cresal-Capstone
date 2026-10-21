import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/features/tickets/models/ticket_model.dart';
import 'package:frontend/features/tickets/presentation/screens/tickets_screen.dart';
import 'package:frontend/features/tickets/presentation/screens/crear_ticket_screen.dart';
import 'package:frontend/features/tickets/presentation/widgets/soporte_desktop_view.dart';
import 'package:frontend/features/tickets/presentation/widgets/ticket_card.dart';
import 'package:frontend/features/tickets/presentation/widgets/ticket_detail_dialog.dart';
import 'package:frontend/features/caja/presentation/screens/caja_main_screen.dart';
import 'package:frontend/features/caja/presentation/widgets/caja_drawer.dart';
import 'package:frontend/features/auth/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorage = {};

  setUp(() {
    mockStorage.clear();
    FlutterSecureStorage.setMockInitialValues(mockStorage);
  });

  group('HU-06: Tickets de Soporte UI & Navigation Tests', () {
    testWidgets('TicketsScreen renderiza vista Desktop estructurada o TabBar Móvil según resolución', (tester) async {
      // 1. Test en Desktop (Caja / Web ancho >= 768) -> SoporteDesktopView
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: TicketsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MÓDULO DE INCIDENCIAS'), findsOneWidget);
      expect(find.text('Soporte Técnico'), findsOneWidget);
      expect(find.text('Crear Ticket'), findsOneWidget);
      expect(find.text('Mis Tickets'), findsOneWidget);
      expect(find.text('Nuevo Ticket de Soporte'), findsOneWidget);

      // 2. Test en Mobile / PDA (ancho < 768) -> TabBar Dark Mode
      tester.view.physicalSize = const Size(412, 732);
      await tester.pumpWidget(
        const MaterialApp(
          home: TicketsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Soporte Técnico e Incidencias'), findsOneWidget);
      expect(find.text('CREAR TICKET'), findsOneWidget);
      expect(find.text('MIS TICKETS'), findsOneWidget);
      expect(find.text('Nuevo Requerimiento de Soporte'), findsOneWidget);
    });

    testWidgets('SoporteDesktopView conmuta entre Crear Ticket y Mis Tickets con filtros de estado', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SoporteDesktopView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Inicialmente en Crear Ticket
      expect(find.text('Nuevo Ticket de Soporte'), findsOneWidget);

      // Tap en Mis Tickets
      await tester.tap(find.text('Mis Tickets'));
      await tester.pumpAndSettle();

      // Valida cabeceras de la tabla
      expect(find.text('FOLIO / FECHA'), findsOneWidget);
      expect(find.text('TIPO'), findsOneWidget);
      expect(find.text('ASUNTO'), findsOneWidget);
      expect(find.text('PRIORIDAD'), findsOneWidget);
      expect(find.text('ESTADO'), findsOneWidget);
      expect(find.text('ACCIÓN'), findsOneWidget);

      // Valida filtros
      expect(find.text('Todos'), findsOneWidget);
      expect(find.text('Abiertos'), findsOneWidget);
      expect(find.text('En Proceso'), findsOneWidget);
      expect(find.text('Resueltos'), findsOneWidget);

      // Cambiar filtro
      await tester.tap(find.text('Abiertos'));
      await tester.pumpAndSettle();
    });

    testWidgets('CrearTicketScreen renderiza todos los campos obligatorios de CA-01', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CrearTicketScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Categoría / Tipo
      expect(find.text('TIPO DE TICKET (CATEGORÍA)'), findsOneWidget);
      expect(find.text('Error de App'), findsOneWidget);

      // Prioridades
      expect(find.text('NIVEL DE PRIORIDAD'), findsOneWidget);
      expect(find.text('Baja'), findsOneWidget);
      expect(find.text('Media'), findsOneWidget);
      expect(find.text('Alta'), findsOneWidget);
      expect(find.text('Urgente'), findsOneWidget);

      // Asunto y Descripción
      expect(find.text('ASUNTO DEL REPORTE (MÁX 150 CARACTERES)'), findsOneWidget);
      expect(find.text('DESCRIPCIÓN DETALLADA (MÁX 1000 CARACTERES)'), findsOneWidget);

      // Botón Enviar
      expect(find.text('ENVIAR TICKET DE SOPORTE'), findsOneWidget);
    });

    testWidgets('CrearTicketScreen bloquea el envío con validación ante campos vacíos', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CrearTicketScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Presionar enviar sin llenar nada (asegurar visibilidad)
      final sendBtn = find.text('ENVIAR TICKET DE SOPORTE');
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(find.text('El asunto no puede estar vacío'), findsOneWidget);
      expect(find.text('La descripción no puede estar vacía'), findsOneWidget);
    });

    testWidgets('CrearTicketScreen valida longitud mínima de asunto y descripción', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CrearTicketScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textFields = find.byType(TextFormField);
      expect(textFields, findsNWidgets(2));

      // Asunto < 5 caracteres
      await tester.enterText(textFields.first, '123');
      // Descripción < 10 caracteres
      await tester.enterText(textFields.last, '12345');

      final sendBtn = find.text('ENVIAR TICKET DE SOPORTE');
      await tester.ensureVisible(sendBtn);
      await tester.tap(sendBtn);
      await tester.pumpAndSettle();

      expect(find.text('El asunto debe tener al menos 5 caracteres'), findsOneWidget);
      expect(find.text('La descripción debe tener al menos 10 caracteres'), findsOneWidget);
    });

    testWidgets('CrearTicketScreen permite cambiar la prioridad táctilmente', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CrearTicketScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap en Urgente
      await tester.tap(find.text('Urgente'));
      await tester.pumpAndSettle();

      // Tap en Baja
      await tester.tap(find.text('Baja'));
      await tester.pumpAndSettle();
    });

    testWidgets('TicketCard renderiza correctamente metadatos, estado y responde a onTap', (tester) async {
      bool tapped = false;
      final ticket = TicketModel(
        idTicket: 'uuid-ticket-1',
        tipoTicket: 'Error de App',
        prioridad: 'Alta',
        asunto: 'Error al imprimir comprobante de pago',
        descripcion: 'La impresora térmica emite un pitido y no procesa el papel.',
        idUsuarioCreador: 'user-uuid-1',
        estadoTicket: 'Abierto',
        fechaCreacion: '2026-08-25T14:30:00Z',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TicketCard(
              ticket: ticket,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TCK-UUIDTI • ERROR DE APP'), findsOneWidget);
      expect(find.text('Error al imprimir comprobante de pago'), findsOneWidget);
      expect(find.text('Alta'), findsOneWidget);
      expect(find.text('Abierto'), findsOneWidget);

      await tester.tap(find.byType(TicketCard));
      expect(tapped, isTrue);
    });

    testWidgets('TicketDetailDialog muestra modal centrado de escritorio con observación de cierre', (tester) async {
      final ticket = TicketModel(
        idTicket: 'TCK-1039',
        tipoTicket: 'Consulta',
        prioridad: 'Baja',
        asunto: 'Consulta sobre anulación de boleta electrónica',
        descripcion: '¿Cuál es el procedimiento autorizado para reemitir una boleta?',
        idUsuarioCreador: 'user-uuid-1',
        estadoTicket: 'Resuelto',
        observacionCierre: 'Procedimiento enviado al correo institucional.',
        fechaCreacion: '2026-08-25T10:00:00Z',
        fechaCierre: '2026-08-25T12:00:00Z',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () => TicketDetailDialog.mostrar(context, ticket),
                  child: const Text('Abrir Dialog'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('CONSULTA'), findsOneWidget);
      expect(find.text('TCK-1039 — Consulta sobre anulación de boleta electrónica'), findsOneWidget);
      expect(find.text('DESCRIPCIÓN DEL REPORTE'), findsOneWidget);
      expect(find.text('RESOLUCIÓN DE TI'), findsOneWidget);
      expect(find.text('Procedimiento enviado al correo institucional.'), findsOneWidget);

      await tester.tap(find.text('Cerrar Detalle'));
      await tester.pumpAndSettle();
      expect(find.text('RESOLUCIÓN DE TI'), findsNothing);
    });

    testWidgets('CajaMainScreen: Navegar a Soporte en el Sidebar lateral cambia a vista SoporteDesktopView', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: CajaMainScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Inicialmente en Bandeja de Cobros
      expect(find.text('Bandeja de Cobros'), findsWidgets);

      // Clic en item Soporte del Sidebar
      final soporteSidebarBtn = find.widgetWithText(InkWell, 'Soporte');
      expect(soporteSidebarBtn, findsOneWidget);
      await tester.tap(soporteSidebarBtn);
      await tester.pumpAndSettle();

      // Debe mostrar Soporte Técnico en el header y la vista de tickets
      expect(find.text('MÓDULO DE INCIDENCIAS'), findsOneWidget);
      expect(find.text('Nuevo Ticket de Soporte'), findsOneWidget);
    });

    testWidgets('CajaDrawer: Cierre de sesión muestra diálogo de confirmación y purga token al confirmar (CA-04 y CA-05)', (tester) async {
      await const FlutterSecureStorage().write(key: 'access_token', value: 'jwt-dummy-token');
      await const FlutterSecureStorage().write(key: 'user_nombre', value: 'María Jesús');
      expect(await AuthService.getToken(), 'jwt-dummy-token');

      bool navigatedToLogin = false;

      await tester.pumpWidget(
        MaterialApp(
          routes: {
            '/login': (context) {
              navigatedToLogin = true;
              return const Scaffold(body: Text('LOGIN_PIN_SCREEN'));
            },
          },
          home: const Scaffold(
            drawer: CajaDrawer(),
            body: Text('MAIN_CAJA'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Abrir el Drawer
      final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
      scaffoldState.openDrawer();
      await tester.pumpAndSettle();

      // Presionar CERRAR SESIÓN en el Drawer
      expect(find.text('CERRAR SESIÓN'), findsOneWidget);
      await tester.tap(find.text('CERRAR SESIÓN'));
      await tester.pumpAndSettle();

      // Diálogo de confirmación (CA-04)
      expect(find.text('Cerrar Sesión'), findsOneWidget);
      expect(find.text('¿Está seguro de que desea cerrar la sesión del turno de caja actual?'), findsOneWidget);
      expect(find.text('CANCELAR'), findsOneWidget);

      // Confirmar cierre de sesión
      final confirmButton = find.widgetWithText(ElevatedButton, 'CERRAR SESIÓN');
      await tester.tap(confirmButton);
      await tester.pumpAndSettle();

      // Verificar purga de token en Secure Storage (CA-04)
      expect(await AuthService.getToken(), isNull);

      // Verificar redirección con destrucción de pila a /login (CA-05)
      expect(navigatedToLogin, isTrue);
      expect(find.text('LOGIN_PIN_SCREEN'), findsOneWidget);
    });

    testWidgets('TicketsScreen es Theme-Aware: Renderiza correctamente en Desktop con Dark Theme y en Móvil con Light Theme', (tester) async {
      // Caso 1: Desktop con Dark Mode (ej. Jefe de Bodega en pantalla ancha)
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const TicketsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('MÓDULO DE INCIDENCIAS'), findsOneWidget);
      expect(find.text('Soporte Técnico'), findsOneWidget);
      expect(find.byType(SoporteDesktopView), findsOneWidget);

      // Caso 2: Móvil con Light Mode (ej. Cajero en pantalla estrecha)
      tester.view.physicalSize = const Size(400, 750);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: const TicketsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Soporte Técnico e Incidencias'), findsOneWidget);
      expect(find.text('CREAR TICKET'), findsOneWidget);
      expect(find.text('MIS TICKETS'), findsOneWidget);
    });

    testWidgets('TicketDetailDialog es Theme-Aware: Renderiza sin desbordes ni errores en Dark Mode y Light Mode', (tester) async {
      const mockTicket = TicketModel(
        idTicket: 'TCK-2026-0099',
        tipoTicket: 'Técnico',
        prioridad: 'Alta',
        asunto: 'Error en sincronización RFID',
        descripcion: 'La pistola Zebra no actualiza el tag RFID en el sector B4.',
        idUsuarioCreador: 'user-bodega-1',
        estadoTicket: 'Abierto',
        fechaCreacion: '2026-09-08T10:00:00Z',
      );

      // Render en Dark Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const Scaffold(
            body: TicketDetailDialog(ticket: mockTicket),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('TÉCNICO'), findsOneWidget);
      expect(find.text('TCK-2026-0099 — Error en sincronización RFID'), findsOneWidget);
      expect(find.text('DESCRIPCIÓN DEL REPORTE'), findsOneWidget);

      // Render en Light Mode
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: const Scaffold(
            body: TicketDetailDialog(ticket: mockTicket),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('TÉCNICO'), findsOneWidget);
      expect(find.text('TCK-2026-0099 — Error en sincronización RFID'), findsOneWidget);
      expect(find.text('DESCRIPCIÓN DEL REPORTE'), findsOneWidget);
    });
  });
}

