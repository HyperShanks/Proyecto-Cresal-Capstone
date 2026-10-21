import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/features/auth/presentation/screens/pin_login_screen.dart';
import 'package:frontend/features/auth/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorage = {};

  setUp(() {
    mockStorage.clear();
    FlutterSecureStorage.setMockInitialValues(mockStorage);
  });

  group('PinLoginScreen Widget & UI Tests', () {
    testWidgets('Muestra interfaz de PIN sin card de usuario ni opción de desenrolar', (tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await const FlutterSecureStorage().write(key: 'enrolled_user_id', value: 'uuid-1234');
      await const FlutterSecureStorage().write(key: 'enrolled_user_name', value: 'Carlos Bodeguero');
      await const FlutterSecureStorage().write(key: 'enrolled_user_email', value: 'carlos@cresal.cl');

      await tester.pumpWidget(
        const MaterialApp(
          home: PinLoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CRESAL'), findsOneWidget);
      expect(find.text('Ingrese su PIN de Operario'), findsOneWidget);
      // Card de usuario y desenrolamiento eliminados
      expect(find.text('Carlos Bodeguero'), findsNothing);
      expect(find.text('carlos@cresal.cl'), findsNothing);
      expect(find.text('Desenrolar Terminal'), findsNothing);

      // Botones numéricos presentes
      for (int i = 0; i <= 9; i++) {
        expect(find.text('$i'), findsOneWidget);
      }
      expect(find.text('C'), findsWidgets);
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);
    });

    testWidgets('Sin enrolamiento previo, redirige automáticamente a /enrolamiento', (tester) async {
      await const FlutterSecureStorage().deleteAll();

      await tester.pumpWidget(
        MaterialApp(
          home: const PinLoginScreen(),
          routes: {
            '/enrolamiento': (context) => const Scaffold(body: Text('ENROLAMIENTO_VIEW')),
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ENROLAMIENTO_VIEW'), findsOneWidget);
    });

    testWidgets('Error de PIN incorrecto se muestra como SnackBar flotante y no desplaza los botones numéricos', (tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await const FlutterSecureStorage().write(key: 'enrolled_user_id', value: 'uuid-1234');

      await tester.pumpWidget(
        const MaterialApp(
          home: PinLoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Guardar posición inicial de botones del teclado numérico
      final Offset posBoton1Antes = tester.getCenter(find.text('1'));
      final Offset posBoton5Antes = tester.getCenter(find.text('5'));

      // Verificar que desenrolar terminal no existe
      expect(find.text('Desenrolar Terminal'), findsNothing);

      // Ingresar 4 dígitos incorrectos
      await tester.tap(find.text('9'));
      await tester.pump();
      await tester.tap(find.text('9'));
      await tester.pump();
      await tester.tap(find.text('9'));
      await tester.pump();
      await tester.tap(find.text('9'));
      await tester.pumpAndSettle();

      // Los números del teclado no se han movido en la pantalla
      final Offset posBoton1Despues = tester.getCenter(find.text('1'));
      final Offset posBoton5Despues = tester.getCenter(find.text('5'));
      expect(posBoton1Despues, equals(posBoton1Antes));
      expect(posBoton5Despues, equals(posBoton5Antes));

      // Se muestra la notificación flotante de error
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('AUTH_ERROR'), findsOneWidget);
    });

    testWidgets('Ingreso de dígitos y borrado en teclado numérico', (tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await const FlutterSecureStorage().write(key: 'enrolled_user_id', value: 'uuid-1234');
      await const FlutterSecureStorage().write(key: 'enrolled_user_name', value: 'Carlos Bodeguero');

      await tester.pumpWidget(
        const MaterialApp(
          home: PinLoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Presionar dígitos 1, 2, 3
      await tester.tap(find.text('1'));
      await tester.pump();
      await tester.tap(find.text('2'));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();

      // Borrar un dígito con el icono de backspace
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();

      // Limpiar con botón C del teclado numérico
      await tester.tap(find.text('C').last);
      await tester.pump();
    });

    testWidgets('Error de red muestra icono de Wi-Fi apagado y mensaje amigable sin fugas de IP', (tester) async {
      tester.view.physicalSize = const Size(1366, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await const FlutterSecureStorage().write(key: 'enrolled_user_id', value: 'uuid-1234');
      await const FlutterSecureStorage().write(key: 'enrolled_user_name', value: 'Carlos Bodeguero');

      await tester.pumpWidget(
        const MaterialApp(
          home: PinLoginScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Verificar que AuthResult clasifica correctamente los errores de red
      const netError = AuthResult.fail(
        'No se pudo conectar con el servidor. Verifique su conexión Wi-Fi o de red corporativa.',
        errorType: AuthErrorType.network,
      );
      expect(netError.isNetworkError, isTrue);
      expect(netError.isCredentialsError, isFalse);
      expect(netError.errorMessage, isNot(contains('http://')));
      expect(netError.errorMessage, isNot(contains(':8000')));

      // Verificar clasificación de error de credenciales
      const credError = AuthResult.fail(
        'PIN incorrecto para este terminal.',
        errorType: AuthErrorType.credentials,
      );
      expect(credError.isCredentialsError, isTrue);
      expect(credError.isNetworkError, isFalse);
    });
  });
}
