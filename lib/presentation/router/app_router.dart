import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animations/animations.dart';
import '../screens/onboarding_screen.dart';
import '../screens/shell_screen.dart';
import '../screens/obd2_dashboard_screen.dart';
import '../screens/obd2_dtc_screen.dart';
import '../screens/obd2_terminal_screen.dart';
import '../screens/obd2_info_screen.dart';

class AppRoutes {
  static const onboarding = '/onboarding';
  static const home = '/home';
  static const dashboard = '/home/dashboard';
  static const dtc = '/home/dtc';
  static const terminal = '/home/terminal';
  static const info = '/home/info';

  AppRoutes._();
}

CustomTransitionPage _fadeTransitionPage({
  required Widget child,
  required LocalKey key,
}) {
  return CustomTransitionPage(
    key: key,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        ),
        child: child,
      );
    },
  );
}

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.onboarding,
    routes: [
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        pageBuilder: (context, state) => _fadeTransitionPage(
          key: state.pageKey,
          child: const OnboardingScreen(),
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return ShellScreen(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                name: 'dashboard',
                builder: (context, state) => const Obd2DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.dtc,
                name: 'dtc',
                builder: (context, state) => const Obd2DtcScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.terminal,
                name: 'terminal',
                builder: (context, state) => const Obd2TerminalScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.info,
                name: 'info',
                builder: (context, state) => const Obd2InfoScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
