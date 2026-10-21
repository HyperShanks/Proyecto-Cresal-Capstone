import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/widgets/cresal_logo.dart';
import '../../../../core/widgets/custom_error_snackbar.dart';
import '../../services/auth_service.dart';
import '../../controllers/login_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PANTALLA DE LOGIN POR PIN INDUSTRIAL
// Diseñada para operarios con guantes en patio de desarme y terminales de caja.
// Cumple regla W3C: touch targets mínimos de 44px y soporte de teclado físico/numpad.
// Errores flotantes (SnackBar) para mantener fija la posición de los números.
// ─────────────────────────────────────────────────────────────────────────────
class PinLoginScreen extends StatefulWidget {
  const PinLoginScreen({super.key});

  @override
  State<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends State<PinLoginScreen>
    with SingleTickerProviderStateMixin {
  static const int _pinLength = 4;

  String _pin = '';
  bool _isLoading = false;
  String? _errorMessage;
  AuthErrorType? _lastErrorType;
  int _failedAttempts = 0;
  final FocusNode _keyboardFocusNode = FocusNode();

  String? _enrolledUserId;

  // Animación de sacudida para feedback de error
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    _cargarDatosEnrolamiento();
  }

  Future<void> _cargarDatosEnrolamiento() async {
    final userId = await AuthService.getEnrolledUserId();

    if (!mounted) return;

    if (userId == null || userId.isEmpty) {
      Navigator.of(context).pushReplacementNamed('/enrolamiento');
      return;
    }

    setState(() {
      _enrolledUserId = userId;
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  // ── Lógica de ingreso de dígitos ──────────────────────────────────────────

  void _onDigitPressed(String digit) {
    if (_isLoading || _pin.length >= _pinLength) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _pin += digit;
      _errorMessage = null;
      _lastErrorType = null;
    });
    if (_pin.length == _pinLength) {
      _submitPin();
    }
  }

  void _onBackspace() {
    if (_isLoading || _pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _onClear() {
    if (_isLoading) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _pin = '';
      _errorMessage = null;
      _lastErrorType = null;
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      _onDigitPressed('0');
    } else if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      _onDigitPressed('1');
    } else if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      _onDigitPressed('2');
    } else if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      _onDigitPressed('3');
    } else if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      _onDigitPressed('4');
    } else if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
      _onDigitPressed('5');
    } else if (key == LogicalKeyboardKey.digit6 || key == LogicalKeyboardKey.numpad6) {
      _onDigitPressed('6');
    } else if (key == LogicalKeyboardKey.digit7 || key == LogicalKeyboardKey.numpad7) {
      _onDigitPressed('7');
    } else if (key == LogicalKeyboardKey.digit8 || key == LogicalKeyboardKey.numpad8) {
      _onDigitPressed('8');
    } else if (key == LogicalKeyboardKey.digit9 || key == LogicalKeyboardKey.numpad9) {
      _onDigitPressed('9');
    } else if (key == LogicalKeyboardKey.backspace) {
      _onBackspace();
    } else if (key == LogicalKeyboardKey.escape) {
      _onClear();
    }
  }

  Future<void> _submitPin() async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _lastErrorType = null;
    });

    final result = await AuthService.loginConPin(_pin, _enrolledUserId);

    if (!mounted) return;

    if (result.success) {
      _failedAttempts = 0;
      _lastErrorType = null;
      await LoginController.handlePostLoginNavigation(
        context,
        idRol: result.user?.idRol,
        rol: result.user?.nombreRol,
      );
    } else {
      if (result.isNetworkError) {
        // Falla de conexión / Wi-Fi: NO se incrementa el contador de intentos ni se sacude
        setState(() {
          _isLoading = false;
          _pin = '';
          _lastErrorType = AuthErrorType.network;
          _errorMessage = result.errorMessage ??
              'No se pudo conectar con el servidor. Verifique su conexión Wi-Fi o de red corporativa.';
        });
        CustomErrorSnackbar.mostrar(
          context,
          mensaje: _errorMessage!,
          codigoError: 'NETWORK_ERROR',
        );
      } else if (result.isCredentialsError) {
        // PIN incorrecto: SÍ incrementa intentos fallidos y sacude
        _failedAttempts++;
        _shakeController.forward(from: 0);

        if (_failedAttempts >= 10) {
          await AuthService.clearToken();
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _pin = '';
            _lastErrorType = AuthErrorType.credentials;
            _errorMessage = 'Acceso bloqueado por seguridad tras 10 intentos fallidos.';
          });
          _showFatalErrorDialog();
        } else {
          setState(() {
            _isLoading = false;
            _pin = '';
            _lastErrorType = AuthErrorType.credentials;
            _errorMessage = '${result.errorMessage} (Intento $_failedAttempts de 10)';
          });
          CustomErrorSnackbar.mostrar(
            context,
            mensaje: _errorMessage!,
            codigoError: 'AUTH_PIN_INVALID',
          );
        }
      } else {
        // Error de servidor u otro
        setState(() {
          _isLoading = false;
          _pin = '';
          _lastErrorType = result.errorType;
          _errorMessage = result.errorMessage ?? 'Ocurrió un error inesperado al validar el PIN.';
        });
        CustomErrorSnackbar.mostrar(
          context,
          mensaje: _errorMessage!,
          codigoError: 'AUTH_ERROR',
        );
      }
    }
  }

  void _showFatalErrorDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppPalette.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            'Acceso Bloqueado',
            style: AppTypography.title.copyWith(color: AppPalette.error),
          ),
          content: const Text(
            'Se ha superado el número máximo de intentos de PIN permitidos (10 intentos). '
            'Por motivos de seguridad, el acceso ha sido bloqueado.',
            style: AppTypography.small,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              },
              child: Text(
                'REINICIAR',
                style: AppTypography.button.copyWith(color: AppPalette.primary),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Construcción de la UI ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: AppPalette.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 36),
                  _buildPinIndicators(),
                  const SizedBox(height: 36),
                  _buildNumericKeypad(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Encabezado con logo y título ──────────────────────────────────────────

  Widget _buildHeader() {
    return Column(
      children: [
        // Emblema de la empresa
        const CresalLogo(size: 84),
        const SizedBox(height: 20),
        Text(
          'CRESAL',
          style: AppTypography.headline.copyWith(fontSize: 28, letterSpacing: 6),
        ),
        const SizedBox(height: 8),
        const Text(
          'Sistema Industrial de Operaciones',
          style: AppTypography.small,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        const Text(
          'Ingrese su PIN de Operario',
          style: AppTypography.title,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ── Indicadores de dígitos (4 círculos) ──────────────────────────────────

  Widget _buildPinIndicators() {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        // Efecto de sacudida horizontal en caso de error
        final offset = _shakeController.isAnimating
            ? 12 * (0.5 - _shakeAnimation.value).abs() * 2
            : 0.0;
        return Transform.translate(
          offset: Offset(offset * (_shakeAnimation.value < 0.5 ? 1 : -1), 0),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_pinLength, (index) {
          final isFilled = index < _pin.length;
          final hasError = _errorMessage != null && _lastErrorType == AuthErrorType.credentials;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: hasError
                  ? AppPalette.error
                  : isFilled
                  ? AppPalette.primary
                  : AppPalette.surface,
              border: Border.all(
                color: hasError
                    ? AppPalette.error
                    : isFilled
                    ? AppPalette.primary
                    : AppPalette.neutral,
                width: 2,
              ),
              boxShadow: isFilled
                  ? [
                      BoxShadow(
                        color: (hasError ? AppPalette.error : AppPalette.primary)
                            .withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          );
        }),
      ),
    );
  }

  // ── Teclado numérico industrial 3×4 ──────────────────────────────────────

  Widget _buildNumericKeypad() {
    const double keypadSpacing = 14;
    final List<String?> keys = [
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      'C',
      '0',
      '⌫',
    ];

    if (_isLoading) {
      return SizedBox(
        height: 260,
        child: Center(
          child: CircularProgressIndicator(
            color: AppPalette.primary,
            strokeWidth: 3,
          ),
        ),
      );
    }

    return Column(
      children: [
        for (int row = 0; row < 4; row++) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int col = 0; col < 3; col++) ...[
                _buildKeyButton(keys[row * 3 + col]),
                if (col < 2) const SizedBox(width: keypadSpacing),
              ],
            ],
          ),
          if (row < 3) const SizedBox(height: keypadSpacing),
        ],
      ],
    );
  }

  Widget _buildKeyButton(String? label) {
    const double buttonSize = 72; // Amplio para guantes industriales (>44px)

    final bool isDelete = label == '⌫';
    final bool isClear = label == 'C';
    final bool isSpecial = isDelete || isClear;

    Color bgColor = AppPalette.surface;
    Color fgColor = AppPalette.textPrimary;
    if (isDelete) {
      bgColor = AppPalette.neutral.withValues(alpha: 0.3);
      fgColor = AppPalette.textSecondary;
    } else if (isClear) {
      bgColor = AppPalette.error.withValues(alpha: 0.15);
      fgColor = AppPalette.error;
    }

    return GestureDetector(
      onTap: () {
        if (label == null) return;
        if (isDelete) {
          _onBackspace();
        } else if (isClear) {
          _onClear();
        } else {
          _onDigitPressed(label);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: buttonSize,
        height: buttonSize,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: isDelete
              ? Icon(Icons.backspace_outlined, color: fgColor, size: 22)
              : Text(
                  label ?? '',
                  style: AppTypography.title.copyWith(
                    fontSize: isSpecial ? 16 : 24,
                    color: fgColor,
                  ),
                ),
        ),
      ),
    );
  }
}
