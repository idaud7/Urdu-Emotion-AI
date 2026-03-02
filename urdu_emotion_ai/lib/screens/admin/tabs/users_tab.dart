import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/theme/app_colors.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();

  List<AdminUserView> _users = [];
  String _query = '';
  bool _loading = true;
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  StreamSubscription<List<UserProfile>>? _userProfilesSub;
  StreamSubscription<List<SessionRecord>>? _sessionsSub;
  List<UserProfile> _rawUsers = [];
  List<SessionRecord> _rawSessions = [];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
    _listenToData();
  }

  void _listenToData() {
    _userProfilesSub = FirestoreService.instance.watchAllUsers().listen(
      (users) {
        _rawUsers = users;
        _rebuildUserViews();
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );

    _sessionsSub = FirestoreService.instance.watchAllSessionsAdmin().listen(
      (sessions) {
        _rawSessions = sessions;
        _rebuildUserViews();
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  void _rebuildUserViews() {
    if (_rawUsers.isEmpty) return;

    final Map<String, List<SessionRecord>> byUser = {};
    for (final s in _rawSessions) {
      byUser.putIfAbsent(s.uid, () => []).add(s);
    }

    final List<AdminUserView> result = [];
    for (final user in _rawUsers) {
      if (user.role == 'admin') continue;

      final userSessions = byUser[user.uid] ?? const <SessionRecord>[];
      final totalSessions = userSessions.length;

      final Map<String, int> emotionCounts = {};
      for (final s in userSessions) {
        emotionCounts[s.emotion] = (emotionCounts[s.emotion] ?? 0) + 1;
      }
      String topEmotion = 'Neutral';
      if (emotionCounts.isNotEmpty) {
        topEmotion = (emotionCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
      }

      DateTime? lastActive;
      for (final s in userSessions) {
        final dt = s.timestamp?.toDate();
        if (dt != null && (lastActive == null || dt.isAfter(lastActive))) {
          lastActive = dt;
        }
      }

      final now = DateTime.now();
      final recentlyActive =
          lastActive != null && now.difference(lastActive).inHours < 24;

      final displayLabel = user.displayName.isNotEmpty
          ? user.displayName
          : user.email.isNotEmpty
              ? user.email
              : 'User ${user.uid.substring(0, 6)}';

      result.add(AdminUserView(
        uid: user.uid,
        name: displayLabel,
        email: user.email.isNotEmpty ? user.email : user.uid,
        sessions: totalSessions,
        topEmotion: topEmotion,
        lastActive: lastActive,
        isActive: recentlyActive,
        isBlocked: user.isBlocked,
      ));
    }

    if (!mounted) return;
    setState(() {
      _users = result;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _userProfilesSub?.cancel();
    _sessionsSub?.cancel();
    _searchController.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  List<AdminUserView> get _filtered => _query.isEmpty
      ? _users
      : _users
          .where((u) =>
              u.name.toLowerCase().contains(_query.toLowerCase()) ||
              u.email.toLowerCase().contains(_query.toLowerCase()))
          .toList();

  int get _activeCount => _users.where((u) => u.isActive).length;

  String _formatLastActive(DateTime? dt) {
    if (dt == null) return 'Never';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _editUser(AdminUserView user) {
    final profile = _rawUsers.firstWhere(
      (p) => p.uid == user.uid,
      orElse: () => UserProfile(
        uid: user.uid,
        email: user.email,
        displayName: user.name,
        role: 'user',
        createdAt: null,
        isBlocked: user.isBlocked,
      ),
    );
    final nameCtrl = TextEditingController(text: profile.displayName.isNotEmpty ? profile.displayName : user.name);
    final ageCtrl = TextEditingController(text: profile.age != null ? '${profile.age}' : '');
    String? selectedGender = profile.gender;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit User',
                  style: Theme.of(ctx)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: const TextStyle(fontSize: 12, color: AppColors.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  'Email and password cannot be changed.',
                  style: TextStyle(fontSize: 11, color: AppColors.onSurface.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ageCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Age',
                    prefixIcon: Icon(Icons.cake_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                _buildGenderSelector(ctx, selectedGender, (g) {
                  setModalState(() => selectedGender = g);
                }),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final newName = nameCtrl.text.trim();
                      if (newName.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Display name is required')),
                        );
                        return;
                      }
                      int? newAge;
                      final ageText = ageCtrl.text.trim();
                      if (ageText.isNotEmpty) {
                        newAge = int.tryParse(ageText);
                        if (newAge != null && (newAge < 1 || newAge > 120)) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('Please enter a valid age (1-120)')),
                          );
                          return;
                        }
                      }
                      Navigator.pop(ctx);
                      try {
                        await FirestoreService.instance.updateUserProfile(
                          uid: user.uid,
                          displayName: newName,
                          age: newAge,
                          gender: selectedGender,
                        );
                        _showSnack('User updated successfully');
                      } catch (e) {
                        _showSnack('Failed: $e', isError: true);
                      }
                    },
                    child: const Text('Save changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGenderSelector(BuildContext ctx, String? selected, ValueChanged<String?> onChanged) {
    const options = ['Male', 'Female', 'Prefer not to say'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: AppColors.onSurface),
        ),
        const SizedBox(height: 8),
        Row(
          children: options.map((opt) {
            final isSelected = selected == opt;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: opt == options.last ? 0 : 8),
                child: GestureDetector(
                  onTap: () => onChanged(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.divider,
                      ),
                    ),
                    child: Text(
                      opt,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : AppColors.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.angry : null,
      ),
    );
  }

  Future<void> _toggleBlock(AdminUserView user) async {
    final willBlock = !user.isBlocked;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(willBlock ? 'Block User?' : 'Unblock User?'),
        content: Text(
          willBlock
              ? 'Block "${user.name}"? They will no longer be able to use the app.'
              : 'Unblock "${user.name}"? They will regain full access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor:
                  willBlock ? AppColors.angry : AppColors.primary,
            ),
            child: Text(willBlock ? 'Block' : 'Unblock'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await FirestoreService.instance
            .setUserBlocked(user.uid, blocked: willBlock);
        _showSnack(
            willBlock ? '${user.name} has been blocked.' : '${user.name} has been unblocked.');
      } catch (e) {
        _showSnack('Failed: $e', isError: true);
      }
    }
  }

  Future<void> _deleteUser(AdminUserView user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User?'),
        content: Text(
          'Permanently delete "${user.name}" and all their session data? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: AppColors.angry),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await FirestoreService.instance.deleteUserAccount(user.uid);
        _showSnack('${user.name} has been deleted.');
      } catch (e) {
        _showSnack('Failed: $e', isError: true);
      }
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filtered;
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Column(
          children: [
            // ── Search bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search by name or email…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                ),
              ),
            ),

            // ── Stats row ───────────────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} users',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.onSurface),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: AppColors.primary, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$_activeCount active',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            // ── User list ───────────────────────────────────────────────────
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text('No users found.',
                          style:
                              TextStyle(color: AppColors.onSurface)))
                  : ListView.separated(
                      padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final user = filtered[i];
                        return _UserCard(
                          user: user,
                          lastActiveStr:
                              _formatLastActive(user.lastActive),
                          onEdit: () => _editUser(user),
                          onToggleBlock: () => _toggleBlock(user),
                          onDelete: () => _deleteUser(user),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── User card ────────────────────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.lastActiveStr,
    required this.onEdit,
    required this.onToggleBlock,
    required this.onDelete,
  });

  final AdminUserView user;
  final String lastActiveStr;
  final VoidCallback onEdit;
  final VoidCallback onToggleBlock;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final emotionColor = AppColors.forEmotion(user.topEmotion);
    final activeColor = user.isActive ? AppColors.primary : AppColors.neutral;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: user.isBlocked
              ? AppColors.angry.withValues(alpha: 0.35)
              : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          CircleAvatar(
            radius: 22,
            backgroundColor:
                (user.isBlocked ? AppColors.angry : AppColors.primary)
                    .withValues(alpha: 0.15),
            child: Text(
              user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: user.isBlocked ? AppColors.angry : AppColors.primary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + status badge
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.onBackground,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (user.isBlocked)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.angry.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Blocked',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.angry,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: activeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          user.isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: activeColor,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  user.email,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),

                // Sessions · top emotion · last active
                Row(
                  children: [
                    const Icon(Icons.mic_outlined,
                        size: 12, color: AppColors.onSurface),
                    const SizedBox(width: 3),
                    Text('${user.sessions} sessions',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.onSurface)),
                    const SizedBox(width: 10),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: emotionColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      user.topEmotion,
                      style: TextStyle(
                          fontSize: 11,
                          color: emotionColor,
                          fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    const Icon(Icons.access_time_outlined,
                        size: 11, color: AppColors.onSurface),
                    const SizedBox(width: 3),
                    Text(lastActiveStr,
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.onSurface)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Action buttons: edit · block/unblock · delete
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionBtn(
                icon: Icons.edit_outlined,
                color: AppColors.primary,
                onTap: onEdit,
              ),
              const SizedBox(height: 6),
              _ActionBtn(
                icon: user.isBlocked
                    ? Icons.check_circle_outline
                    : Icons.block_outlined,
                color: user.isBlocked ? AppColors.primary : AppColors.angry,
                onTap: onToggleBlock,
              ),
              const SizedBox(height: 6),
              _ActionBtn(
                icon: Icons.delete_outline,
                color: AppColors.angry,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Small icon action button ─────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      );
}
