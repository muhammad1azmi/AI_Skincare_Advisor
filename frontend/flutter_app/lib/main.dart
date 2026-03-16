import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'theme.dart';
import 'router.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with generated options.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize push notifications (FCM).
  final notificationService = NotificationService();
  await notificationService.initialize();

  // Auto-register FCM token if user is already signed in.
  final currentUser = FirebaseAuth.instance.currentUser;
  if (currentUser != null && notificationService.token != null) {
    notificationService.registerTokenWithServer(currentUser.uid);
  }
  // Also register on future sign-ins.
  FirebaseAuth.instance.authStateChanges().listen((user) {
    if (user != null && notificationService.token != null) {
      notificationService.registerTokenWithServer(user.uid);
    }
  });

  // Set status bar style.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // Lock to portrait.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const ProviderScope(child: GlowApp()));
}

class GlowApp extends ConsumerWidget {
  const GlowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Glow',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      // Route based on auth state.
      initialRoute: authState.when(
        data: (user) => user != null ? AppRoutes.home : AppRoutes.login,
        loading: () => AppRoutes.login,
        error: (_, _) => AppRoutes.login,
      ),
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
