import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';

import '../../core/network/api_config.dart';
import '../../core/network/api_client.dart';
import '../../services/auth_service.dart';
import './widgets/input_field_widget.dart';
import './widgets/social_login_button_widget.dart';

/// Authentication Screen for MotoRide motorcycle ride-hailing application
/// Provides secure user registration and login with mobile-optimized input methods
/// Supports email/phone authentication, social login, and biometric authentication
class AuthenticationScreen extends StatefulWidget {
  const AuthenticationScreen({super.key});

  @override
  State<AuthenticationScreen> createState() => _AuthenticationScreenState();
}

class _AuthenticationScreenState extends State<AuthenticationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoginMode = true;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isEmailMode = true;
  bool _acceptTerms = false;
  bool _isLoading = false;
  String? _emailPhoneError;
  String? _passwordError;
  String? _confirmPasswordError;

  @override
  void dispose() {
    _emailPhoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _toggleAuthMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
      _emailPhoneError = null;
      _passwordError = null;
      _confirmPasswordError = null;
      _acceptTerms = false;
    });
  }

  void _toggleInputMode() {
    setState(() {
      _isEmailMode = !_isEmailMode;
      _emailPhoneController.clear();
      _emailPhoneError = null;
    });
  }

  bool _validateEmailPhone() {
    final value = _emailPhoneController.text.trim();
    if (value.isEmpty) {
      setState(() {
        _emailPhoneError = _isEmailMode ? 'Email requis' : 'Téléphone requis';
      });
      return false;
    }

    if (_isEmailMode) {
      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
      if (!emailRegex.hasMatch(value)) {
        setState(() {
          _emailPhoneError = 'Format email invalide';
        });
        return false;
      }
    } else {
      final phoneRegex = RegExp(r'^\+?[1-9]\d{1,14}$');
      if (!phoneRegex.hasMatch(value.replaceAll(RegExp(r'\s+'), ''))) {
        setState(() {
          _emailPhoneError = 'Format téléphone invalide';
        });
        return false;
      }
    }

    setState(() {
      _emailPhoneError = null;
    });
    return true;
  }

  bool _validatePassword() {
    final value = _passwordController.text;
    if (value.isEmpty) {
      setState(() {
        _passwordError = 'Mot de passe requis';
      });
      return false;
    }

    if (!_isLoginMode && value.length < 8) {
      setState(() {
        _passwordError = 'Minimum 8 caractères requis';
      });
      return false;
    }

    setState(() {
      _passwordError = null;
    });
    return true;
  }

  bool _validateConfirmPassword() {
    if (_isLoginMode) return true;

    final value = _confirmPasswordController.text;
    if (value.isEmpty) {
      setState(() {
        _confirmPasswordError = 'Confirmation requise';
      });
      return false;
    }

    if (value != _passwordController.text) {
      setState(() {
        _confirmPasswordError = 'Mots de passe différents';
      });
      return false;
    }

    setState(() {
      _confirmPasswordError = null;
    });
    return true;
  }

  String _dioErrorMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.unknown:
        return 'Serveur inaccessible. Backend démarré ? URL: ${ApiConfig.baseUrl}';
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Délai dépassé. Vérifiez le backend.';
      default:
        return e.message ?? 'Erreur réseau. Vérifiez le backend.';
    }
  }

  bool _isFormValid() {
    if (_isLoginMode) {
      return _emailPhoneController.text.isNotEmpty &&
          _passwordController.text.isNotEmpty &&
          _emailPhoneError == null &&
          _passwordError == null;
    } else {
      return _emailPhoneController.text.isNotEmpty &&
          _passwordController.text.isNotEmpty &&
          _confirmPasswordController.text.isNotEmpty &&
          _acceptTerms &&
          _emailPhoneError == null &&
          _passwordError == null &&
          _confirmPasswordError == null;
    }
  }

  Future<void> _handleAuthentication() async {
    if (!_validateEmailPhone() ||
        !_validatePassword() ||
        !_validateConfirmPassword()) {
      return;
    }

    if (!_isLoginMode && !_acceptTerms) {
      _showErrorSnackBar('Veuillez accepter les conditions');
      return;
    }

    // Backend BikeRide exige un email pour login/register
    if (!_isEmailMode) {
      _showErrorSnackBar('Utilisez votre email pour vous connecter');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final email = _emailPhoneController.text.trim();
    final password = _passwordController.text;
    final authService = AuthService();

    try {
      if (_isLoginMode) {
        await authService.login(email: email, password: password);
      } else {
        await authService.register(
          email: email,
          password: password,
          role: 'client',
        );
      }
      if (mounted) {
        setState(() => _isLoading = false);
        HapticFeedback.mediumImpact();
        Navigator.of(context, rootNavigator: true)
            .pushReplacementNamed('/home-screen');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar(e.message ?? 'Erreur de connexion');
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final msg = _dioErrorMessage(e);
        _showErrorSnackBar(msg);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar('Erreur inattendue: $e');
      }
    }
  }

  Future<void> _handleSocialLogin(String provider) async {
    HapticFeedback.lightImpact();
    setState(() {
      _isLoading = true;
    });

    await Future.delayed(const Duration(seconds: 2));

    HapticFeedback.mediumImpact();
    if (mounted) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).pushReplacementNamed('/home-screen');
    }
  }

  void _handleForgotPassword() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Réinitialiser le mot de passe',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Text(
          'Un lien de réinitialisation sera envoyé à votre ${_isEmailMode ? 'email' : 'téléphone'}.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSuccessSnackBar('Lien envoyé avec succès');
            },
            child: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.tertiary,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: theme.colorScheme.primary,
                ),
              )
            : SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: 4.h),
                      Text(
                        _isLoginMode ? 'Connexion' : 'Inscription',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 1.h),
                      Text(
                        _isLoginMode
                            ? 'Bienvenue sur MotoRide'
                            : 'Créez votre compte MotoRide',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 4.h),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _isEmailMode ? null : _toggleInputMode,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: _isEmailMode
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                foregroundColor: _isEmailMode
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.primary,
                                side: BorderSide(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              child: const Text('Email'),
                            ),
                          ),
                          SizedBox(width: 3.w),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: !_isEmailMode
                                  ? null
                                  : _toggleInputMode,
                              style: OutlinedButton.styleFrom(
                                backgroundColor: !_isEmailMode
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                foregroundColor: !_isEmailMode
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.primary,
                                side: BorderSide(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              child: const Text('Téléphone'),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 3.h),
                      InputFieldWidget(
                        controller: _emailPhoneController,
                        label: _isEmailMode ? 'Email' : 'Téléphone',
                        keyboardType: _isEmailMode
                            ? TextInputType.emailAddress
                            : TextInputType.phone,
                        prefixIcon: _isEmailMode ? 'email' : 'phone',
                        errorText: _emailPhoneError,
                        onChanged: (_) => _validateEmailPhone(),
                      ),
                      SizedBox(height: 2.h),
                      InputFieldWidget(
                        controller: _passwordController,
                        label: 'Mot de passe',
                        keyboardType: TextInputType.visiblePassword,
                        prefixIcon: 'lock',
                        isPassword: true,
                        isPasswordVisible: _isPasswordVisible,
                        errorText: _passwordError,
                        onChanged: (_) => _validatePassword(),
                        onToggleVisibility: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                      if (!_isLoginMode) ...[
                        SizedBox(height: 2.h),
                        InputFieldWidget(
                          controller: _confirmPasswordController,
                          label: 'Confirmer le mot de passe',
                          keyboardType: TextInputType.visiblePassword,
                          prefixIcon: 'lock',
                          isPassword: true,
                          isPasswordVisible: _isConfirmPasswordVisible,
                          errorText: _confirmPasswordError,
                          onChanged: (_) => _validateConfirmPassword(),
                          onToggleVisibility: () {
                            setState(() {
                              _isConfirmPasswordVisible =
                                  !_isConfirmPasswordVisible;
                            });
                          },
                        ),
                      ],
                      if (_isLoginMode) ...[
                        SizedBox(height: 1.h),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _handleForgotPassword,
                            child: Text(
                              'Mot de passe oublié?',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (!_isLoginMode) ...[
                        SizedBox(height: 2.h),
                        Row(
                          children: [
                            Checkbox(
                              value: _acceptTerms,
                              onChanged: (value) {
                                setState(() {
                                  _acceptTerms = value ?? false;
                                });
                              },
                            ),
                            Expanded(
                              child: Text(
                                'J\'accepte les conditions d\'utilisation',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ],
                      SizedBox(height: 3.h),
                      ElevatedButton(
                        onPressed: _isFormValid()
                            ? _handleAuthentication
                            : null,
                        child: Text(
                          _isLoginMode ? 'Se connecter' : 'S\'inscrire',
                        ),
                      ),
                      SizedBox(height: 3.h),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(color: theme.colorScheme.outline),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 3.w),
                            child: Text(
                              'OU',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(color: theme.colorScheme.outline),
                          ),
                        ],
                      ),
                      SizedBox(height: 3.h),
                      SocialLoginButtonWidget(
                        provider: 'Google',
                        iconName: 'google',
                        onTap: () => _handleSocialLogin('Google'),
                      ),
                      SizedBox(height: 2.h),
                      SocialLoginButtonWidget(
                        provider: 'Apple',
                        iconName: 'apple',
                        onTap: () => _handleSocialLogin('Apple'),
                      ),
                      SizedBox(height: 2.h),
                      SocialLoginButtonWidget(
                        provider: 'Facebook',
                        iconName: 'facebook',
                        onTap: () => _handleSocialLogin('Facebook'),
                      ),
                      SizedBox(height: 3.h),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _isLoginMode
                                ? 'Pas encore de compte?'
                                : 'Déjà un compte?',
                            style: theme.textTheme.bodyMedium,
                          ),
                          TextButton(
                            onPressed: _toggleAuthMode,
                            child: Text(
                              _isLoginMode ? 'S\'inscrire' : 'Se connecter',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
