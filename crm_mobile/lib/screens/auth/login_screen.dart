import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/screens/home_screen.dart';
import 'package:crm_mobile/blocs/login_bloc.dart';
import 'package:crm_mobile/blocs/login_event.dart';
import 'package:crm_mobile/blocs/login_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/core/utils/navigation_service.dart';
import 'package:crm_mobile/widgets/spinning_logo.dart';

class LoginScreen extends StatelessWidget {
  final bool sessionExpired;

  const LoginScreen({super.key, this.sessionExpired = false});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<LoginBloc>(),
      child: LoginScreenView(sessionExpired: sessionExpired),
    );
  }
}

class LoginScreenView extends StatefulWidget {
  final bool sessionExpired;

  const LoginScreenView({super.key, this.sessionExpired = false});

  @override
  State<LoginScreenView> createState() => _LoginScreenViewState();
}

class _LoginScreenViewState extends State<LoginScreenView> {
  @override
  void initState() {
    super.initState();
    NavigationService.isLoginScreenActive = true;
    NavigationService.isAppReady = false;

    // Automatically trigger the in-app web login right after opening from splash screen,
    // but not if redirected due to an explicit session expiration.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.sessionExpired) {
        context.read<LoginBloc>().add(const LoginOAuthInitiated());
      }
    });
  }

  @override
  void dispose() {
    NavigationService.isLoginScreenActive = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: BlocConsumer<LoginBloc, LoginState>(
          listener: (context, state) async {
            if (state is LoginSuccess) {
              NavigationService.isLoginScreenActive = false;
              try {
                if (sl.isRegistered<SharedPreferences>()) {
                  await sl<SharedPreferences>().remove('overlay_permission_prompted');
                }
              } catch (_) {}
              try {
                await CallRecordingService().requestPermissionsSequentially();
              } catch (e) {
                debugPrint('Error requesting permissions post-login: $e');
              }
              if (context.mounted) {
                // Navigate directly inside the app to HomeScreen and clear auth stack
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const HomeScreen(isFromLogin: true)),
                  (route) => false,
                );
              }
            } else if (state is LoginFailure) {
              final msg = state.message;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    msg.isNotEmpty ? msg : 'Authentication failed. Please try again.',
                  ),
                  backgroundColor: AppColors.primary,
                ),
              );
            }
          },
          builder: (context, state) {
            final isLoading = state is LoginLoading || state is LoginSuccess;
            final loadingMessage = state is LoginLoading
                ? (state.message ?? 'Opening Tickora Login...')
                : (state is LoginSuccess ? 'Welcome to Tickora!' : '');

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (isLoading) ...[
                      // Dynamic synchronized 3-ball orbit loader
                      const SpinningLogo(size: 64),
                      const SizedBox(height: 28),
                      Text(
                        loadingMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          context.read<LoginBloc>().add(LoginOAuthCancelled());
                        },
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ] else ...[
                      // Brand Logo
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 72,
                          height: 72,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Image.asset(
                              'assets/images/logo.webp',
                              width: 72,
                              height: 72,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.business_center_rounded,
                                  size: 72,
                                  color: AppColors.primary,
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),

                      // App Title
                      const Text(
                        'Tickora CRM',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),

                      const Text(
                        'Sign in securely with your Tickora account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 48),
                      if (widget.sessionExpired && state is! LoginFailure) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: Color(0xFFDC2626), size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Your session has expired. Please sign in again.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF991B1B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // If user dismissed the in-app web login, provide a single clean Sign In button
                      if (state is LoginFailure) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 24),
                          decoration: BoxDecoration(
                            color: AppColors.secondary,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderEnabled),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.primary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  state.message,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            context.read<LoginBloc>().add(const LoginOAuthInitiated());
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.login_rounded, size: 20, color: Colors.white),
                              SizedBox(width: 10),
                              Text(
                                'Sign In with Tickora',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
