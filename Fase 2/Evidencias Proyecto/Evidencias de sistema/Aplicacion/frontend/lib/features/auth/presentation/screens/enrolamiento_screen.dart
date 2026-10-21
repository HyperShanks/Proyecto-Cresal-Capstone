import 'package:flutter/material.dart';
import '../../../../core/theme/tokens/app_palette.dart';
import '../../../../core/theme/tokens/app_typography.dart';
import '../../../../core/widgets/cresal_logo.dart';
import '../../services/auth_service.dart';
import '../../controllers/login_controller.dart';

/// Pantalla de Enrolamiento Inicial de Terminal.
/// Permite vincular el dispositivo a un usuario corporativo mediante correo y contraseña.
class EnrolamientoScreen extends StatefulWidget {
  const EnrolamientoScreen({super.key});

  @override
  State<EnrolamientoScreen> createState() => _EnrolamientoScreenState();
}

class _EnrolamientoScreenState extends State<EnrolamientoScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  AuthErrorType? _lastErrorType;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitEnrolamiento() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _lastErrorType = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final result = await AuthService.enrolarTerminal(email, password);

    if (!mounted) return;

    if (result.success) {
      await LoginController.handlePostLoginNavigation(
        context,
        idRol: result.user?.idRol,
        rol: result.user?.nombreRol,
      );
    } else {
      setState(() {
        _isLoading = false;
        _lastErrorType = result.errorType;
        _errorMessage = result.errorMessage ?? 'Error al enrolar terminal.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
                    if (_errorMessage != null) ...[
                      _buildErrorBanner(),
                      const SizedBox(height: 20),
                    ],
                    _buildEmailField(),
                    const SizedBox(height: 16),
                    _buildPasswordField(),
                    const SizedBox(height: 32),
                    _buildSubmitButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const CresalLogo(size: 84),
        const SizedBox(height: 20),
        Text(
          'CRESAL',
          style: AppTypography.headline.copyWith(fontSize: 28, letterSpacing: 6),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enrolamiento de Terminal Industrial',
          style: AppTypography.title,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Ingrese sus credenciales corporativas para vincular este dispositivo a su usuario.',
          style: AppTypography.small.copyWith(color: AppPalette.textSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildErrorBanner() {
    final isNetwork = _lastErrorType == AuthErrorType.network;
    final isCreds = _lastErrorType == AuthErrorType.credentials;
    final bannerColor = isNetwork ? AppPalette.secondary : AppPalette.error;
    final bannerIcon = isNetwork
        ? Icons.wifi_off_rounded
        : (isCreds ? Icons.lock_outline_rounded : Icons.error_outline);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: bannerColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(bannerIcon, color: bannerColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: AppTypography.small.copyWith(
                color: bannerColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      focusNode: _emailFocusNode,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      style: const TextStyle(color: AppPalette.textPrimary),
      decoration: InputDecoration(
        labelText: 'Correo Electrónico',
        labelStyle: const TextStyle(color: AppPalette.textSecondary),
        prefixIcon: const Icon(Icons.email_outlined, color: AppPalette.primary),
        filled: true,
        fillColor: AppPalette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppPalette.primary, width: 2),
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Ingrese su correo electrónico';
        }
        if (!value.contains('@') || !value.contains('.')) {
          return 'Ingrese un formato de correo válido';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      focusNode: _passwordFocusNode,
      obscureText: _obscurePassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) => _submitEnrolamiento(),
      style: const TextStyle(color: AppPalette.textPrimary),
      decoration: InputDecoration(
        labelText: 'Contraseña Corporativa',
        labelStyle: const TextStyle(color: AppPalette.textSecondary),
        prefixIcon: const Icon(Icons.lock_outline, color: AppPalette.primary),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: AppPalette.textSecondary,
          ),
          onPressed: () {
            setState(() {
              _obscurePassword = !_obscurePassword;
            });
          },
        ),
        filled: true,
        fillColor: AppPalette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppPalette.primary, width: 2),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Ingrese su contraseña';
        }
        return null;
      },
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      height: 52, // touch target >= 48px
      child: ElevatedButton(
        onPressed: _isLoading ? null : _submitEnrolamiento,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                'ENROLAR TERMINAL',
                style: AppTypography.button.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
      ),
    );
  }
}
