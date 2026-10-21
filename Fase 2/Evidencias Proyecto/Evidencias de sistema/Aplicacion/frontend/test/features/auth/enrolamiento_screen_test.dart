import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:frontend/features/auth/presentation/screens/enrolamiento_screen.dart';
import 'package:frontend/features/auth/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final Map<String, String> mockStorage = {};

  setUp(() {
    mockStorage.clear();
    FlutterSecureStorage.setMockInitialValues(mockStorage);
  });

  group('EnrolamientoScreen UI & Validation Tests', () {
    testWidgets('Renderiza correctamente títulos, campos de email, contraseña y botón', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EnrolamientoScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CRESAL'), findsOneWidget);
      expect(find.text('Enrolamiento de Terminal Industrial'), findsOneWidget);
      expect(find.text('Correo Electrónico'), findsOneWidget);
      expect(find.text('Contraseña Corporativa'), findsOneWidget);
      expect(find.text('ENROLAR TERMINAL'), findsOneWidget);
    });

    testWidgets('Muestra mensajes de error de validación cuando los campos están vacíos', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EnrolamientoScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap en Enrolar con campos vacíos
      await tester.tap(find.text('ENROLAR TERMINAL'));
      await tester.pumpAndSettle();

      expect(find.text('Ingrese su correo electrónico'), findsOneWidget);
      expect(find.text('Ingrese su contraseña'), findsOneWidget);
    });

    testWidgets('Muestra error de formato si el correo no es válido', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EnrolamientoScreen(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'correo-invalido');
      await tester.enterText(find.byType(TextFormField).last, 'clave1234');
      await tester.tap(find.text('ENROLAR TERMINAL'));
      await tester.pumpAndSettle();

      expect(find.text('Ingrese un formato de correo válido'), findsOneWidget);
    });

    testWidgets('Alterna la visibilidad de la contraseña al presionar el icono de ojo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EnrolamientoScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Estado inicial: obscureText == true, icono visibility_off
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      expect(find.byIcon(Icons.visibility), findsNothing);

      // Tap en icono para mostrar
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.visibility), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off), findsNothing);
    });
  });

  group('AuthService Enrolamiento & Storage Tests', () {
    test('enrolarTerminal guarda las claves de sesión y enrolamiento', () async {
      // Mock storage direct test
      await const FlutterSecureStorage().write(key: 'enrolled_user_id', value: 'user-uuid-abc');
      await const FlutterSecureStorage().write(key: 'enrolled_user_email', value: 'admin@cresal.cl');
      await const FlutterSecureStorage().write(key: 'enrolled_user_name', value: 'Admin Principal');

      expect(await AuthService.getEnrolledUserId(), 'user-uuid-abc');
      expect(await AuthService.getEnrolledUserEmail(), 'admin@cresal.cl');
      expect(await AuthService.getEnrolledUserName(), 'Admin Principal');
      expect(await AuthService.isTerminalEnrolled(), isTrue);

      // Des-enrolar purga todo
      await AuthService.desenrolarTerminal();
      expect(await AuthService.getEnrolledUserId(), isNull);
      expect(await AuthService.getEnrolledUserEmail(), isNull);
      expect(await AuthService.isTerminalEnrolled(), isFalse);
    });

    test('AuthResult clasifica correctamente errores de credenciales y de red para enrolamiento', () {
      const credFail = AuthResult.fail(
        'Credenciales inválidas, verifica tu correo o contraseña.',
        errorType: AuthErrorType.credentials,
      );
      expect(credFail.isCredentialsError, isTrue);
      expect(credFail.isNetworkError, isFalse);
      expect(credFail.errorMessage, 'Credenciales inválidas, verifica tu correo o contraseña.');

      const netFail = AuthResult.fail(
        'No se pudo conectar con el servidor. Verifique su conexión Wi-Fi o de red corporativa.',
        errorType: AuthErrorType.network,
      );
      expect(netFail.isNetworkError, isTrue);
      expect(netFail.isCredentialsError, isFalse);
      expect(netFail.errorMessage, isNot(contains('/api')));
      expect(netFail.errorMessage, isNot(contains('10.81')));
    });
  });
}
