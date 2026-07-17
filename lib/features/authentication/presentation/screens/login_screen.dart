import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:tracking_system_app/core/config/supabase_config.dart';

// ═════════════════════════════════════════════════════════════
// DESIGN SYSTEM
// ═════════════════════════════════════════════════════════════

/// Colores de login alineados con Routio web.
abstract final class AppColors {
  static const primary = Color(0xFF206B5C);
  static const primaryDark = Color(0xFF174F44);

  static const background = Color(0xFFF4F6F5);
  static const surface = Color(0xFFFFFFFF);
  static const inputFill = Color(0xFFF8FAFC);

  static const textPrimary = Color(0xFF172521);
  static const textSecondary = Color(0xFF6E7B77);
  static const textMuted = Color(0xFF96A09D);
  static const border = Color(0xFFE2E8E5);

  static const error = Color(0xFFC74C4C);
  static const success = Color(0xFF16A34A);
}

abstract final class AppDimensions {
  static const radiusSm = 10.0;
  static const radiusMd = 14.0;
  static const radiusLg = 20.0;
  static const radiusXl = 24.0;

  static const fieldHeight = 56.0;
  static const buttonHeight = 56.0;

  static const pageHorizontal = 22.0;
  static const cardPadding = 24.0;
}

abstract final class AppTextStyles {
  static const brand = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    letterSpacing: 2.4,
    color: AppColors.primary,
  );

  static const title = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    height: 1.15,
    letterSpacing: -0.8,
    color: AppColors.textPrimary,
  );

  static const subtitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textSecondary,
  );

  static const fieldLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const link = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: AppColors.primary,
  );

  static const button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.1,
    color: Colors.white,
  );

  static const caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
  );
}

// ═════════════════════════════════════════════════════════════
// TEXT FORM FIELD
// ═════════════════════════════════════════════════════════════

class AppTextFormField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String semanticLabel;
  final String hintText;
  final IconData prefixIconData;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final List<String> autofillHints;
  final ValueChanged<String>? onFieldSubmitted;
  final String? Function(String?)? validator;
  final VoidCallback? onToggleObscure;

  const AppTextFormField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.semanticLabel,
    required this.hintText,
    required this.prefixIconData,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.autofillHints = const [],
    this.onFieldSubmitted,
    this.validator,
    this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) {
        final hasFocus = focusNode.hasFocus;

        final iconColor = hasFocus
            ? AppColors.primary
            : AppColors.textSecondary.withValues(alpha: 0.65);

        return Semantics(
          label: semanticLabel,
          textField: true,
          child: TextFormField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscureText,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            autofillHints: autofillHints.isEmpty ? null : autofillHints,
            autocorrect: false,
            enableSuggestions: !obscureText,
            textCapitalization: TextCapitalization.none,
            textAlignVertical: TextAlignVertical.center,
            cursorColor: AppColors.primary,
            onFieldSubmitted: onFieldSubmitted,
            onTapOutside: (_) {
              FocusManager.instance.primaryFocus?.unfocus();
            },
            validator: validator,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              constraints: const BoxConstraints(
                minHeight: AppDimensions.fieldHeight,
              ),
              hintText: hintText,
              hintStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: AppColors.textMuted,
              ),
              filled: true,
              fillColor: hasFocus ? AppColors.surface : AppColors.inputFill,

              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 16, right: 10),
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(begin: iconColor, end: iconColor),
                  duration: const Duration(milliseconds: 180),
                  builder: (_, color, __) {
                    return Icon(prefixIconData, size: 20, color: color);
                  },
                ),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 52,
                minHeight: AppDimensions.fieldHeight,
              ),

              suffixIcon: onToggleObscure == null
                  ? null
                  : IconButton(
                      onPressed: onToggleObscure,
                      tooltip: obscureText
                          ? 'Mostrar contraseña'
                          : 'Ocultar contraseña',
                      icon: Icon(
                        obscureText
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                        color: AppColors.textSecondary.withValues(alpha: 0.65),
                      ),
                    ),

              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),

              border: _border(AppColors.border),
              enabledBorder: _border(AppColors.border),
              focusedBorder: _border(AppColors.primary, width: 1.8),
              errorBorder: _border(AppColors.error),
              focusedErrorBorder: _border(AppColors.error, width: 1.8),

              errorStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: AppColors.error,
              ),
              errorMaxLines: 2,
            ),
          ),
        );
      },
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1.1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// LOGIN SCREEN
// ═════════════════════════════════════════════════════════════

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  final int _currentYear = DateTime.now().year;

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _headerAnimation;
  late final Animation<Offset> _cardAnimation;
  late final Animation<Offset> _actionsAnimation;

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0, 0.55, curve: Curves.easeOut),
    );

    _headerAnimation = _slide(
      const Interval(0, 0.6, curve: Curves.easeOutCubic),
    );

    _cardAnimation = _slide(
      const Interval(0.18, 0.78, curve: Curves.easeOutCubic),
    );

    _actionsAnimation = _slide(
      const Interval(0.36, 1, curve: Curves.easeOutCubic),
    );

    _animationController.forward();
  }

  Animation<Offset> _slide(Interval interval) {
    return Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: interval));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: AppColors.background,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: PopScope(
        canPop: !_isLoading,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _isLoading) {
            HapticFeedback.lightImpact();
          }
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final keyboardIsOpen = mediaQuery.viewInsets.bottom > 0;

                final isCompact = keyboardIsOpen || constraints.maxHeight < 700;

                final verticalPadding = isCompact ? 16.0 : 28.0;

                final minHeight = math.max(
                  0.0,
                  constraints.maxHeight - verticalPadding * 2,
                );

                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      AppDimensions.pageHorizontal,
                      verticalPadding,
                      AppDimensions.pageHorizontal,
                      24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: minHeight),
                      child: Align(
                        alignment: isCompact
                            ? Alignment.topCenter
                            : Alignment.center,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: AutofillGroup(
                            child: Form(
                              key: _formKey,
                              autovalidateMode: _autovalidateMode,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 280),
                                    curve: Curves.easeOutCubic,
                                    child: SlideTransition(
                                      position: _headerAnimation,
                                      child: _buildHeader(isCompact),
                                    ),
                                  ),

                                  SizedBox(height: isCompact ? 20 : 34),

                                  SlideTransition(
                                    position: _cardAnimation,
                                    child: _buildFormCard(isCompact),
                                  ),

                                  SizedBox(height: isCompact ? 18 : 24),

                                  SlideTransition(
                                    position: _actionsAnimation,
                                    child: _buildActionsSection(),
                                  ),

                                  SizedBox(height: isCompact ? 24 : 30),

                                  _buildFooter(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool compact) {
    final logoSize = compact ? 68.0 : 80.0;

    return Column(
      children: [
        Semantics(
          image: true,
          label: 'Logo de Routio',
          child: Container(
            width: logoSize,
            height: logoSize,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF206B5C), Color(0xFF2D8A78)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                  spreadRadius: -5,
                ),
              ],
            ),
            child: Icon(
              Icons.navigation_rounded,
              size: compact ? 32 : 38,
              color: Colors.white,
            ),
          ),
        ),

        SizedBox(height: compact ? 18 : 24),

        const Text('ROUTIO', style: AppTextStyles.brand),

        const SizedBox(height: 12),

        Text(
          'Bienvenido de nuevo',
          textAlign: TextAlign.center,
          style: AppTextStyles.title.copyWith(fontSize: compact ? 25 : 28),
        ),

        const SizedBox(height: 8),

        const SizedBox(
          width: 310,
          child: Text(
            'Ingresa tus credenciales para acceder a la app del conductor',
            textAlign: TextAlign.center,
            style: AppTextStyles.subtitle,
          ),
        ),
      ],
    );
  }

  Widget _buildFormCard(bool compact) {
    return Container(
      padding: EdgeInsets.all(compact ? 20 : AppDimensions.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withValues(alpha: 0.055),
            blurRadius: 28,
            offset: const Offset(0, 12),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Correo electrónico', style: AppTextStyles.fieldLabel),
          const SizedBox(height: 8),

          AppTextFormField(
            controller: _emailController,
            focusNode: _emailFocus,
            semanticLabel: 'Correo electrónico',
            hintText: 'tu@empresa.com',
            prefixIconData: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            onFieldSubmitted: (_) {
              _passwordFocus.requestFocus();
            },
            validator: _validateEmail,
          ),

          const SizedBox(height: 20),

          const Text('Contraseña', style: AppTextStyles.fieldLabel),
          const SizedBox(height: 8),

          AppTextFormField(
            controller: _passwordController,
            focusNode: _passwordFocus,
            semanticLabel: 'Contraseña',
            hintText: '••••••••',
            prefixIconData: Icons.lock_outline_rounded,
            obscureText: _obscurePassword,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) {
              _handleLogin();
            },
            onToggleObscure: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
            validator: _validatePassword,
          ),

          const SizedBox(height: 14),

          _buildRememberAndForgot(),
        ],
      ),
    );
  }

  Widget _buildRememberAndForgot() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: CheckboxListTile(
            value: _rememberMe,
            onChanged: _isLoading
                ? null
                : (value) {
                    if (value == null) return;

                    HapticFeedback.selectionClick();

                    setState(() {
                      _rememberMe = value;
                    });
                  },
            title: const Text('Recordarme', style: AppTextStyles.body),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            visualDensity: const VisualDensity(horizontal: -4, vertical: -3),
            activeColor: AppColors.primary,
            checkColor: Colors.white,
          ),
        ),

        const SizedBox(width: 4),

        Flexible(
          child: TextButton(
            onPressed: _isLoading
                ? null
                : () {
                    context.push('/forgot-password');
                  },
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 48),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              tapTargetSize: MaterialTapTargetSize.padded,
            ),
            child: const Text(
              '¿Olvidaste tu contraseña?',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PrimaryButton(
          isLoading: _isLoading,
          onPressed: _isLoading ? null : _handleLogin,
        ),

        const SizedBox(height: 24),

        Row(
          children: [
            const Expanded(child: Divider(height: 1, color: AppColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'o continúa con',
                style: AppTextStyles.body.copyWith(
                  fontSize: 13,
                  color: AppColors.textSecondary.withValues(alpha: 0.75),
                ),
              ),
            ),
            const Expanded(child: Divider(height: 1, color: AppColors.border)),
          ],
        ),

        const SizedBox(height: 18),

        Row(
          children: [
            Expanded(
              child: _SocialButton(
                label: 'Google',
                icon: const Text(
                  'G',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF4285F4),
                  ),
                ),
                onPressed: _isLoading
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        // Implementar Google Sign In.
                      },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _SocialButton(
                label: 'Biometría',
                icon: const Icon(
                  Icons.fingerprint_rounded,
                  size: 22,
                  color: AppColors.textSecondary,
                ),
                onPressed: _isLoading
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        // Implementar local_auth.
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('¿No tienes cuenta?', style: AppTextStyles.body),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      context.push('/register');
                    },
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 5),
              ),
              child: const Text('Regístrate', style: AppTextStyles.link),
            ),
          ],
        ),

        const SizedBox(height: 14),

        Text(
          '© $_currentYear Routio · App del conductor',
          textAlign: TextAlign.center,
          style: AppTextStyles.caption,
        ),
      ],
    );
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;

    if (_autovalidateMode == AutovalidateMode.disabled) {
      setState(() {
        _autovalidateMode = AutovalidateMode.onUserInteraction;
      });
    }

    final form = _formKey.currentState;

    if (form == null || !form.validate()) {
      HapticFeedback.lightImpact();
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.mediumImpact();

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      debugPrint('═══════════════════════════════════════');
      debugPrint('🔐 LOGIN ATTEMPT');
      debugPrint('   Email: $email');
      debugPrint('═══════════════════════════════════════');

      // Autenticación real con Supabase
      final response = await SupabaseConfig.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) {
        throw Exception('No se pudo obtener el usuario después del login');
      }

      debugPrint('✅ LOGIN EXITOSO');
      debugPrint('   auth_user_id: ${user.id}');
      debugPrint('   email: ${user.email}');

      // Verificar que el usuario existe en core_usuarios
      final coreUser = await SupabaseConfig.client
          .from('core_usuarios')
          .select('id, auth_user_id, email, nombre, apellido, activo, empresa_id')
          .eq('auth_user_id', user.id)
          .filter('deleted_at', 'is', null)
          .maybeSingle();

      if (coreUser == null) {
        debugPrint('⚠️ Usuario no encontrado en core_usuarios');
        throw Exception('Tu cuenta no está registrada en el sistema. Contacta al administrador.');
      }

      debugPrint('   core_usuarios_id: ${coreUser['id']}');
      debugPrint('   nombre: ${coreUser['nombre']} ${coreUser['apellido']}');
      debugPrint('   activo: ${coreUser['activo']}');
      debugPrint('   empresa_id: ${coreUser['empresa_id']}');

      if (coreUser['activo'] != true) {
        throw Exception('Tu cuenta está inactiva. Contacta al administrador.');
      }

      if (!mounted) return;

      TextInput.finishAutofillContext(shouldSave: _rememberMe);

      HapticFeedback.heavyImpact();
      context.go('/dashboard');
    } on AuthException catch (e) {
      debugPrint('❌ AuthException: ${e.message}');
      debugPrint('   statusCode: ${e.statusCode}');

      if (!mounted) return;

      String msg = 'No pudimos iniciar sesión. Verifica tus credenciales e inténtalo nuevamente.';
      if (e.message.toLowerCase().contains('invalid login credentials')) {
        msg = 'Email o contraseña incorrectos.';
      } else if (e.message.toLowerCase().contains('email not confirmed')) {
        msg = 'Debes confirmar tu email antes de iniciar sesión.';
      }
      _showErrorMessage(msg);
    } catch (error, stackTrace) {
      debugPrint('❌ Login error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _showErrorMessage(
        error.toString().contains('Exception:')
            ? error.toString().replaceAll('Exception: ', '')
            : 'No pudimos iniciar sesión. Verifica tus credenciales e inténtalo nuevamente.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          ),
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Cerrar',
            textColor: Colors.white,
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
        ),
      );
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'El correo es obligatorio';
    }

    final isValid = RegExp(
      r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+'
      r'@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*'
      r'\.[a-zA-Z]{2,}$',
    ).hasMatch(email);

    if (!isValid) {
      return 'Ingresa un correo electrónico válido';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'La contraseña es obligatoria';
    }

    if (value.length < 6) {
      return 'Mínimo 6 caracteres requeridos';
    }

    return null;
  }
}

// ═════════════════════════════════════════════════════════════
// PRIMARY BUTTON
// ═════════════════════════════════════════════════════════════

class _PrimaryButton extends StatefulWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const _PrimaryButton({required this.isLoading, required this.onPressed});

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _pressed = false;

  bool get _enabled => !widget.isLoading && widget.onPressed != null;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;

    setState(() {
      _pressed = value;
    });
  }

  @override
  void didUpdateWidget(covariant _PrimaryButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isLoading) {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: AnimatedScale(
        scale: _pressed ? 0.985 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Semantics(
          container: true,
          button: true,
          enabled: _enabled,
          label: widget.isLoading ? 'Iniciando sesión' : 'Iniciar sesión',
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: AppDimensions.buttonHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.isLoading
                    ? [
                        AppColors.primary.withValues(alpha: 0.55),
                        AppColors.primaryDark.withValues(alpha: 0.55),
                      ]
                    : const [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              boxShadow: widget.isLoading
                  ? null
                  : [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.28),
                        blurRadius: 22,
                        offset: const Offset(0, 9),
                        spreadRadius: -5,
                      ),
                    ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              child: InkWell(
                onTap: _enabled ? widget.onPressed : null,
                onHighlightChanged: _enabled ? _setPressed : null,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                splashColor: Colors.white.withValues(alpha: 0.16),
                highlightColor: Colors.white.withValues(alpha: 0.06),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: widget.isLoading
                        ? const SizedBox(
                            key: ValueKey('loading'),
                            width: 23,
                            height: 23,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : const Row(
                            key: ValueKey('idle'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Iniciar sesión',
                                style: AppTextStyles.button,
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════
// SOCIAL / ALTERNATIVE ACCESS BUTTON
// ═════════════════════════════════════════════════════════════

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback? onPressed;

  const _SocialButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border, width: 1.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
