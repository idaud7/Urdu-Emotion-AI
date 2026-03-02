import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/auth_service.dart';
import '../../screens/welcome/welcome_screen.dart';
import '../../screens/login/login_screen.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/record/record_screen.dart';
import '../../screens/result/result_screen.dart';
import '../../screens/visualization/visualization_screen.dart';
import '../../screens/analytics/analytics_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/admin/admin_screen.dart';
import '../widgets/home_shell.dart';

class AppRouter {
  // Public routes that don't require login
  static const _publicRoutes = ['/', '/login'];

  // User-only routes (not accessible to admin)
  static const _userRoutes = ['/home', '/record', '/analytics', '/profile', '/settings'];

  // Shared fade + slight slide-up transition
  static CustomTransitionPage<T> _page<T>({
    required LocalKey key,
    required Widget child,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      child: child,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (context, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static final GoRouter router = GoRouter(
    initialLocation: '/',
    // Re-run redirect whenever AuthService notifies a change (login / logout)
    refreshListenable: AuthService.instance,

    redirect: (context, state) {
      final auth = AuthService.instance;
      final path = state.matchedLocation;

      // ── Not logged in ─────────────────────────────────────────────────────
      if (!auth.isLoggedIn) {
        // Allow public routes; redirect everything else to login
        return _publicRoutes.contains(path) ? null : '/login';
      }

      // ── Logged in ─────────────────────────────────────────────────────────
      // If on a public route (welcome / login), redirect to role home
      if (_publicRoutes.contains(path)) {
        return auth.isAdmin ? '/admin' : '/home';
      }

      // Admin trying to access user-only routes → send to admin panel
      if (auth.isAdmin && _userRoutes.any((r) => path.startsWith(r))) {
        return '/admin';
      }

      // User trying to access admin route → send to home
      if (!auth.isAdmin && path.startsWith('/admin')) {
        return '/home';
      }

      return null; // allow
    },

    routes: [
      // ── Public ────────────────────────────────────────────────────────────
      GoRoute(
        path: '/',
        name: 'welcome',
        pageBuilder: (context, state) =>
            _page(key: state.pageKey, child: const WelcomeScreen()),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) =>
            _page(key: state.pageKey, child: const LoginScreen()),
      ),

      // ── User app — bottom nav shell ───────────────────────────────────────
      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            pageBuilder: (context, state) =>
                _page(key: state.pageKey, child: const HomeScreen()),
          ),
          GoRoute(
            path: '/record',
            name: 'record',
            pageBuilder: (context, state) =>
                _page(key: state.pageKey, child: const RecordScreen()),
          ),
          GoRoute(
            path: '/analytics',
            name: 'analytics',
            pageBuilder: (context, state) =>
                _page(key: state.pageKey, child: const AnalyticsScreen()),
          ),
        ],
      ),

      // ── Full-screen routes (no bottom nav) ────────────────────────────────
      GoRoute(
        path: '/profile',
        name: 'profile',
        pageBuilder: (context, state) =>
            _page(key: state.pageKey, child: const ProfileScreen()),
      ),
      GoRoute(
        path: '/settings',
        name: 'settings',
        pageBuilder: (context, state) =>
            _page(key: state.pageKey, child: const SettingsScreen()),
      ),
      GoRoute(
        path: '/visualization',
        name: 'visualization',
        pageBuilder: (context, state) {
          final data = state.extra as VisualizationData?;
          return _page(
            key: state.pageKey,
            child: VisualizationScreen(data: data),
          );
        },
      ),
      GoRoute(
        path: '/result',
        name: 'result',
        pageBuilder: (context, state) {
          final data = state.extra as ResultData;
          return _page(
            key: state.pageKey,
            child: ResultScreen(data: data),
          );
        },
      ),
      GoRoute(
        path: '/admin',
        name: 'admin',
        pageBuilder: (context, state) =>
            _page(key: state.pageKey, child: const AdminScreen()),
      ),
    ],
  );
}
