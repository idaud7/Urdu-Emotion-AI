import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import 'tabs/overview_tab.dart';
import 'tabs/users_tab.dart';
import 'tabs/sessions_tab.dart';
import 'tabs/reports_tab.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout, color: AppColors.angry),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text(
                    'Are you sure you want to log out?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.angry,
                      ),
                      child: const Text('Log out'),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                AuthService.instance.logout();
                context.go('/login');
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.onSurface,
          indicatorColor: AppColors.primary,
          labelStyle:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 11),
          tabs: const [
            Tab(
                icon: Icon(Icons.dashboard_outlined, size: 20),
                text: 'Overview'),
            Tab(
                icon: Icon(Icons.people_outline, size: 20), text: 'Users'),
            Tab(
                icon: Icon(Icons.list_alt_outlined, size: 20),
                text: 'Sessions'),
            Tab(
                icon: Icon(Icons.assessment_outlined, size: 20),
                text: 'Reports'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          OverviewTab(),
          UsersTab(),
          SessionsTab(),
          ReportsTab(),
        ],
      ),
    );
  }
}
