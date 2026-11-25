import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:crm_mobile/injection/injection.dart' as di;
import 'package:crm_mobile/core/services/call_recording_service.dart';
import 'package:crm_mobile/core/services/fcm_service.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/core/services/secure_token_storage.dart';
import 'package:crm_mobile/core/services/oauth_service.dart';
import 'package:crm_mobile/core/services/privilege_service.dart';
import 'package:crm_mobile/injection/injection.dart';
import 'package:crm_mobile/screens/home_screen.dart';
import 'package:crm_mobile/screens/auth/login_screen.dart';
import 'package:crm_mobile/core/services/app_update_service.dart';
import 'package:crm_mobile/core/utils/navigation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../error_handling_img/force_update_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _initializeAndNavigate();
  }

  void _runStartupBackgroundTasks() async {
    try {
      await FcmService.instance.initialize();
    } catch (e) {
      debugPrint('Error initializing FCM on startup: $e');
    }
  }

  Future<void> _initializeAndNavigate() async {
    final startTime = DateTime.now();

    // 1. Initialize core services in background while splash clock animation runs
    try {
      await dotenv.load(fileName: ".env");
    } catch (e) {
      debugPrint('dotenv.load error: $e');
    }

    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      debugPrint('Firebase init error: $e');
    }

    try {
      await di.init();
      CallRecordingService.initializeOverlayListener();
    } catch (e) {
      debugPrint('di.init error: $e');
    }

    // 2. Check for mandatory app update
    try {
      if (sl.isRegistered<AppUpdateService>()) {
        final updateService = sl<AppUpdateService>();
        final updateResult = await updateService.checkAppUpdate();

        if (updateResult.isUpdateRequired) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => ForceUpdateScreen(
                currentVersion: updateResult.currentVersion,
                requiredVersion: updateResult.requiredVersion,
              ),
            ),
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('checkAppUpdate non-fatal error: $e');
    }

    // 3. Verify user session / auth token
    bool isLoggedIn = false;
    try {
      if (sl.isRegistered<SecureTokenStorage>()) {
        final tokenStorage = sl<SecureTokenStorage>();
        String? token = await tokenStorage.getAccessToken();

        // Fallback check directly from SharedPreferences if needed
        if ((token == null || token.isEmpty) && sl.isRegistered<SharedPreferences>()) {
          token = sl<SharedPreferences>().getString('token');
        }

        if (token != null && token.trim().isNotEmpty) {
          isLoggedIn = true;
          // Run background non-blocking token refresh if expired and refresh token is available
          tokenStorage.isTokenExpired().then((isExpired) async {
            if (isExpired && sl.isRegistered<OAuthService>()) {
              final rt = await tokenStorage.getRefreshToken();
              if (rt != null && rt.isNotEmpty) {
                await sl<OAuthService>().refreshToken();
              }
            }
          }).catchError((_) {});
        }
      }
    } catch (e) {
      debugPrint('SplashScreen: session verification warning: $e');
      if (sl.isRegistered<SharedPreferences>()) {
        final fallback = sl<SharedPreferences>().getString('token');
        isLoggedIn = fallback != null && fallback.trim().isNotEmpty;
      }
    }

    if (isLoggedIn) {
      _runStartupBackgroundTasks();
      try {
        if (sl.isRegistered<PrivilegeService>()) {
          sl<PrivilegeService>().fetchPrivileges().catchError((e) {
            debugPrint('SplashScreen: Background privilege fetch non-fatal: $e');
          });
        }
      } catch (_) {}
    }

    // 4. Smooth minimum animation duration so clock hands motion is enjoyed
    final elapsed = DateTime.now().difference(startTime);
    if (elapsed < const Duration(milliseconds: 1500)) {
      await Future.delayed(const Duration(milliseconds: 1500) - elapsed);
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => isLoggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NavigationService.markAppReady();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF011F77),
      body: Center(
        child: SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Base Logo (outer circle with people/nodes and navy background)
              ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Image.asset(
                  'assets/images/logo_clean.png',
                  width: 140,
                  height: 140,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Image.asset(
                      'assets/images/logo.png',
                      width: 140,
                      height: 140,
                      fit: BoxFit.contain,
                    );
                  },
                ),
              ),

              // Animated Clock Hands (the 2 sticks moving like a clock inside)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _ClockHandsPainter(
                        progress: _controller.value,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter that renders the two clock hands (cyan short stick & white long stick)
/// rotating clockwise like a clock inside the logo emblem.
class _ClockHandsPainter extends CustomPainter {
  final double progress;

  _ClockHandsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Geometric center of the inner dark circle inside the logo emblem
    final double cx = w * 0.498;
    final double cy = h * 0.485;
    final double innerRadius = w * 0.225;

    // Seamlessly cover the inner circle background so underlying baked sticks never show
    final circlePaint = Paint()
      ..color = const Color(0xFF011A67)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), innerRadius, circlePaint);

    // Exact stick dimensions matching the logo geometry
    final double strokeW = w * 0.0615;
    final double hourLen = w * 0.165;
    final double minLen = w * 0.225;

    // Initial angles starting at classic logo checkmark / 10:10 position:
    // -5pi/6 (-150 deg, ~10:00) for shorter hour hand
    // -pi/6 (-30 deg, ~2:00) for longer minute hand
    const double initHour = -math.pi / 2 - math.pi / 3;
    const double initMin = -math.pi / 2 + math.pi / 3;

    // Clock rotation:
    // Minute hand sweeps 360 degrees per animation cycle
    // Hour hand advances at 1/6th speed for visible, natural clock motion
    final double hourAngle = initHour + (progress * 2 * math.pi * (1.0 / 6.0));
    final double minAngle = initMin + (progress * 2 * math.pi * 1.0);

    final Offset center = Offset(cx, cy);
    final Offset hourEnd = Offset(
      cx + hourLen * math.cos(hourAngle),
      cy + hourLen * math.sin(hourAngle),
    );
    final Offset minEnd = Offset(
      cx + minLen * math.cos(minAngle),
      cy + minLen * math.sin(minAngle),
    );

    // Paint for short stick (Hour hand): Electric Cyan #10D6FF
    final hourPaint = Paint()
      ..color = const Color(0xFF10D6FF)
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Paint for long stick (Minute hand): Crisp White #FFFFFF
    final minPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = strokeW
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Paint for central pivot joint
    final pivotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw hour hand (cyan)
    canvas.drawLine(center, hourEnd, hourPaint);

    // Draw minute hand (white)
    canvas.drawLine(center, minEnd, minPaint);

    // Draw round central pivot dot
    canvas.drawCircle(center, strokeW / 2, pivotPaint);
  }

  @override
  bool shouldRepaint(covariant _ClockHandsPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
