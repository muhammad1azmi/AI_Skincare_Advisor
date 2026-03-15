import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/consultation_screen.dart';
import 'screens/consultation_lobby_screen.dart';
import 'screens/login_screen.dart';

/// App-level route names.
class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String home = '/';
  static const String chat = '/chat';
  static const String consultationLobby = '/consultation-lobby';
  static const String consultation = '/consultation';
}

/// Simple router using named routes.
class AppRouter {
  AppRouter._();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.login:
        return _fade(const LoginScreen(), settings);
      case AppRoutes.home:
        return _fade(const HomeScreen(), settings);
      case AppRoutes.chat:
        return _slide(const ChatScreen(), settings);
      case AppRoutes.consultationLobby:
        return _slide(const ConsultationLobbyScreen(), settings);
      case AppRoutes.consultation:
        return _slide(const ConsultationScreen(), settings);
      default:
        return _fade(const HomeScreen(), settings);
    }
  }

  /// Fade transition for root-level routes.
  static PageRoute _fade(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  /// Slide transition for detail routes.
  static PageRoute _slide(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 350),
    );
  }
}
