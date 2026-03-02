import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_colors.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});

  final Widget child;

  int _selectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/analytics')) return 2;
    if (location.startsWith('/record'))    return 1;
    return 0; // /home
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.2),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/home');
            case 1:
              context.go('/record');
            case 2:
              context.go('/analytics');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined, color: AppColors.onSurface),
            selectedIcon: Icon(Icons.home, color: AppColors.primary),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.mic_outlined, color: AppColors.onSurface),
            selectedIcon: Icon(Icons.mic, color: AppColors.primary),
            label: 'Record',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined, color: AppColors.onSurface),
            selectedIcon: Icon(Icons.bar_chart, color: AppColors.primary),
            label: 'Analytics',
          ),
        ],
      ),
    );
  }
}
