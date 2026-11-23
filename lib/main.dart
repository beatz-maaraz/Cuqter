import 'package:cuqter/widgets/session_validator_wrapper.dart';
import 'dart:ui';
import 'package:cuqter/Account/login.dart';
import 'package:cuqter/Screen/home/navigation_screen.dart';
import 'package:cuqter/Screen/home/desktop_navigation_screen.dart';
import 'package:cuqter/responsive/responsive_layout.dart';
import 'package:cuqter/providers/chat_provider.dart';
import 'package:cuqter/providers/theme_provider.dart';
import 'package:cuqter/utils/colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cuqter/services/notification_service.dart';
import 'package:cuqter/services/deep_link_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cuqter/services/biometric_service.dart';
import 'package:cuqter/Screen/settings/app_lock_screen.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  final data = message.data;
  final type = data['type'];

  // 1. If it's a call invite or call cancellation, handle Full-Screen Intent / CallKit:
  if (type == 'call_invite' || type == 'video_call' || type == 'voice_call') {
    final roomId = data['roomId'] ?? message.notification?.body ?? '';
    final callerName =
        data['callerName'] ??
        message.notification?.title ??
        data['title'] ??
        'Incoming Call';
    final callerId = data['callerId'] ?? data['senderId'] ?? '';
    final isVideoCall = data['isVideoCall'] == 'true' || type == 'video_call';
    final callerPic = data['callerPic'] ?? data['senderProfilePic'];

    if (roomId.isNotEmpty) {
      await NotificationService.showIncomingCallNotification(
        callerName: callerName,
        roomId: roomId,
        callerId: callerId,
        isVideoCall: isVideoCall,
        callerPic: callerPic,
      );
    }
    return;
  }

  if (type == 'call_cancel') {
    final roomId = data['roomId'];
    if (roomId != null && roomId.isNotEmpty) {
      await NotificationService.cancelCallNotification(roomId);
    }
    return;
  }

  // 2. Eliminate duplicate alerts:
  // When the message payload contains a notification block, the OS (Android / iOS)
  // automatically posts and displays the banner in the system tray.
  // We MUST NOT show another local notification here, or the user receives duplicate alerts!
  if (message.notification != null) {
    return;
  }

  // 3. Fallback for data-only messages:
  await showMessageNotification(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Optimize RAM usage and image decoding
  if (kIsWeb) {
    BrowserContextMenu.disableContextMenu();
    PaintingBinding.instance.imageCache.maximumSize = 150;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 64 * 1024 * 1024;
  } else {
    PaintingBinding.instance.imageCache.maximumSize = 100;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024;
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await BiometricService.isAppLockEnabled();
    // Start listening for cuqter.com deep links
    DeepLinkService().init(navigatorKey);
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: const MainApp(),
    ),
  );
}

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return const ClampingScrollPhysics(
        parent: RangeMaintainingScrollPhysics(),
      );
    }
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      try {
        precacheImage(const AssetImage('assets/icon/icon.png'), context);
        precacheImage(const AssetImage('assets/icon/google_icon.png'), context);
        precacheImage(const AssetImage('assets/Wallpaper/dark.png'), context);
        precacheImage(const AssetImage('assets/Wallpaper/light.png'), context);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Cuqter',
      scrollBehavior: const AppScrollBehavior(),
      themeMode: themeProvider.themeMode,
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: themeProvider.primaryColor,
              brightness: Brightness.light,
            ).copyWith(
              primary: themeProvider.primaryColor,
              secondary: themeProvider.primaryColor.withValues(alpha: 0.2),
              surface: Colors.white,
              onSurface: const Color(0xFF191C1B),
              primaryContainer: themeProvider.primaryColor.withValues(
                alpha: 0.15,
              ),
              onPrimaryContainer: const Color(0xFF002114),
              surfaceContainerHighest: const Color(0xFFE8ECE9),
              surfaceContainerHigh: const Color(0xFFEEF2EF),
              onSurfaceVariant: const Color(0xFF3F4945),
              secondaryContainer: AppColors.accent,
              onSecondaryContainer: Colors.white,
              outlineVariant: const Color(0xFFC2C8C4),
            ),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF10B981),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: themeProvider.primaryColor,
          brightness: Brightness.dark,
        ).copyWith(primary: themeProvider.primaryColor, surface: Colors.black),
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF10B981),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: AppLockWrapper(
        child: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          initialData: FirebaseAuth.instance.currentUser,
          builder: (context, snapshot) {
            if (snapshot.hasData || FirebaseAuth.instance.currentUser != null) {
              return const SessionValidatorWrapper(
                child: ResponsiveLayout(
                  mobileLayout: NavigationScreen(),
                  desktopLayout: DesktopNavigationScreen(),
                ),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox.shrink();
            }
            return const Loginpage();
          },
        ),
      ),
    );
  }
}

class AppLockWrapper extends StatefulWidget {
  final Widget child;
  const AppLockWrapper({super.key, required this.child});

  @override
  State<AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends State<AppLockWrapper>
    with WidgetsBindingObserver {
  late bool _isLocked;
  bool _isPaused = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isLocked =
        BiometricService.appLockEnabled &&
        FirebaseAuth.instance.currentUser != null;
    _checkAppLock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _isPaused = true;
      _pausedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_isPaused && !_isLocked) {
        _isPaused = false;
        _checkAppLockOnResume();
      }
    }
  }

  Future<void> _checkAppLock() async {
    if (BiometricService.isAuthenticating) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final isLockEnabled = await BiometricService.isAppLockEnabled();
    if (mounted) {
      setState(() {
        _isLocked = isLockEnabled;
      });
    }
  }

  Future<void> _checkAppLockOnResume() async {
    if (BiometricService.isAuthenticating) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final isLockEnabled = await BiometricService.isAppLockEnabled();
    if (!isLockEnabled) return;

    final timeoutSeconds = await BiometricService.getAppLockTimeoutSeconds();
    if (timeoutSeconds > 0 && _pausedAt != null) {
      final elapsed = DateTime.now().difference(_pausedAt!).inSeconds;
      if (elapsed < timeoutSeconds) {
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isLocked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
      return AppLockScreen(
        onUnlocked: () {
          if (mounted) {
            setState(() {
              _isLocked = false;
              _isPaused = false;
            });
          }
        },
      );
    }
    return widget.child;
  }
}
