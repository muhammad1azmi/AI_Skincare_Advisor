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

  runApp(const ProviderScope(child: SkincareAdvisorApp()));
}

class SkincareAdvisorApp extends ConsumerWidget {
  const SkincareAdvisorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return MaterialApp(
      title: 'AI Skincare Advisor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
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
