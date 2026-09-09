import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/screens/home_screen.dart';
import 'package:crm_mobile/blocs/login_bloc.dart';
import 'package:crm_mobile/blocs/login_event.dart';
import 'package:crm_mobile/blocs/login_state.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/screens/auth/forgot_password_screen.dart';
import 'package:crm_mobile/core/services/call_recording_service.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<LoginBloc>(),
      child: const LoginScreenView(),
    );
  }
}

class LoginScreenView extends StatefulWidget {
  const LoginScreenView({super.key});

  @override
  State<LoginScreenView> createState() => _LoginScreenViewState();
}

class _LoginScreenViewState extends State<LoginScreenView> {
  bool _obscurePassword = true;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
              await CallRecordingService().requestPermissionsSequentially();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const HomeScreen()),
                );
              }
            } else if (state is LoginFailure) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.message),
                  backgroundColor: AppColors.primary,
                ),
              );
            }
          },
          builder: (context, state) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Logo and Name ("Tickora CRM")
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Image.asset(
                          'assets/images/logo.png',
                          width: 44,
                          height: 44,
                          errorBuilder: (context, error, stackTrace) {
                            return Image.asset(
                              'assets/images/logo.webp',
                              width: 44,
                              height: 44,
                            );
                          },
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Tickora CRM',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 56),

                    // Email Address Label
                    const Text(
                      'Email Address',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Email Field
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      selectionControls: MaterialTextSelectionControls(),
                      onTap: () {
                        if (_emailController.selection.isValid && !_emailController.selection.isCollapsed) {
                          _emailController.selection = TextSelection.collapsed(offset: _emailController.selection.extentOffset);
                        }
                      },
                      style: const TextStyle(fontSize: 15, color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Enter your email',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                        prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF94A3B8), size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Password Label
                    const Text(
                      'Password',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Password Field
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      selectionControls: MaterialTextSelectionControls(),
                      onTap: () {
                        if (_passwordController.selection.isValid && !_passwordController.selection.isCollapsed) {
                          _passwordController.selection = TextSelection.collapsed(offset: _passwordController.selection.extentOffset);
                        }
                      },
                      style: const TextStyle(fontSize: 15, color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Password',
                        hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                        prefixIcon: const Icon(Icons.lock_outlined, color: Color(0xFF94A3B8), size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: const Color(0xFF94A3B8),
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Forgot Password?
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const ForgotPasswordScreen(),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Red Login Button
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: state is LoginLoading 
                          ? null 
                          : () {
                            context.read<LoginBloc>().add(
                              LoginButtonPressed(
                                email: _emailController.text,
                                password: _passwordController.text,
                              ),
                            );
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
                        child: state is LoginLoading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text(
                                'Login',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 36),

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
