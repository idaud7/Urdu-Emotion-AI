import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/firestore_service.dart';
import '../../core/theme/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _name = '';
  String _email = '';
  int? _age;
  String? _gender;
  bool _loading = true;

  // Stats
  int _totalSessions = 0;
  int _totalMinutes = 0;
  String _topEmotion = '--';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final auth = AuthService.instance;

    if (auth.isAdmin) {
      // Admin uses hardcoded credentials — no Firebase user.
      setState(() {
        _name = 'Admin';
        _email = 'admin';
        _totalSessions = 0;
        _totalMinutes = 0;
        _topEmotion = '--';
        _loading = false;
      });
      return;
    }

    final user = auth.firebaseUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    // Load display name / email from Firebase Auth first.
    String name = user.displayName ?? '';
    String email = user.email ?? '';

    // Try Firestore profile for a richer display name and age.
    try {
      final profile =
          await FirestoreService.instance.getUserProfile(user.uid);
      if (profile != null) {
        if (profile.displayName.isNotEmpty) name = profile.displayName;
        if (profile.email.isNotEmpty) email = profile.email;
        _age = profile.age;
        _gender = profile.gender;
      }
    } catch (_) {
      // Firestore may be unavailable; fall back to Auth data.
    }

    // Load session stats.
    int totalSessions = 0;
    int totalMinutes = 0;
    String topEmotion = '--';
    try {
      final sessions =
          await FirestoreService.instance.getAllSessions(user.uid);
      totalSessions = sessions.length;
      totalMinutes =
          sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds) ~/ 60;

      // Top emotion by frequency.
      final Map<String, int> counts = {};
      for (final s in sessions) {
        counts[s.emotion] = (counts[s.emotion] ?? 0) + 1;
      }
      if (counts.isNotEmpty) {
        topEmotion = (counts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
      }
    } catch (_) {
      // Firestore may be unavailable.
    }

    if (!mounted) return;
    setState(() {
      _name = name.isNotEmpty ? name : email.split('@').first;
      _email = email;
      _totalSessions = totalSessions;
      _totalMinutes = totalMinutes;
      _topEmotion = topEmotion;
      _loading = false;
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showFeedbackSheet() {
    final feedbackController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        bool submitting = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Send Feedback',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Share your thoughts, suggestions, or report an issue.',
                    style: Theme.of(ctx)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: feedbackController,
                    maxLines: 5,
                    maxLength: 500,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Write your feedback here...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: submitting
                          ? null
                          : () async {
                              final text = feedbackController.text.trim();
                              if (text.isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Please write something before submitting.')),
                                );
                                return;
                              }
                              setSheetState(() => submitting = true);
                              try {
                                final user =
                                    AuthService.instance.firebaseUser;
                                await FirestoreService.instance
                                    .submitFeedback(
                                  uid: user?.uid ?? 'anonymous',
                                  displayName: _name,
                                  email: _email,
                                  message: text,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  _showSnack(
                                      'Thank you! Your feedback has been submitted.');
                                }
                              } catch (_) {
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  _showSnack(
                                      'Failed to submit. Please try again.');
                                }
                              }
                            },
                      child: submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Submit Feedback'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _editProfile() {
    final nameController = TextEditingController(text: _name);
    final ageController =
        TextEditingController(text: _age != null ? '$_age' : '');
    String? selectedGender = _gender;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Edit Profile',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Email cannot be changed.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: AppColors.onSurface,
                        ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      prefixIcon: Icon(Icons.person_outline, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Age',
                      prefixIcon: Icon(Icons.cake_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildGenderSelector(ctx, selectedGender, (g) {
                    setSheetState(() => selectedGender = g);
                  }),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final newName = nameController.text.trim().isEmpty
                            ? _name
                            : nameController.text.trim();
                        int? newAge;
                        final ageText = ageController.text.trim();
                        if (ageText.isNotEmpty) {
                          final parsed = int.tryParse(ageText);
                          if (parsed != null &&
                              parsed >= 1 &&
                              parsed <= 120) {
                            newAge = parsed;
                          }
                        }

                        final user = AuthService.instance.firebaseUser;
                        if (user != null) {
                          try {
                            await user.updateDisplayName(newName);
                            await FirestoreService.instance.updateUserProfile(
                              uid: user.uid,
                              displayName: newName,
                              age: newAge,
                              gender: selectedGender,
                            );
                          } catch (_) {
                            // Best-effort update.
                          }
                        }

                        setState(() {
                          _name = newName;
                          _age = newAge ?? _age;
                          _gender = selectedGender;
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) _showSnack('Profile updated successfully');
                      },
                      child: const Text('Save changes'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildGenderSelector(
    BuildContext ctx,
    String? selected,
    ValueChanged<String?> onChanged,
  ) {
    const options = ['Male', 'Female', 'Prefer not to say'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                color: AppColors.onSurface,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: options.map((opt) {
            final isSelected = selected == opt;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: opt == options.last ? 0 : 8,
                ),
                child: GestureDetector(
                  onTap: () => onChanged(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.divider,
                      ),
                    ),
                    child: Text(
                      opt,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : AppColors.onSurface,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Avatar
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                    child: const Icon(
                      Icons.person,
                      size: 48,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _email,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (!AuthService.instance.isAdmin)
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _editProfile,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit Profile'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(
                            color: AppColors.primary, width: 1),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // Stats row
                Row(
                  children: [
                    _statCard(context, '$_totalSessions', 'Sessions'),
                    const SizedBox(width: 12),
                    _statCard(context, '$_totalMinutes', 'Minutes'),
                    const SizedBox(width: 12),
                    _statCard(context, _topEmotion, 'Top Emotion'),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),

                // Settings shortcut
                ListTile(
                  leading: const Icon(Icons.settings_outlined,
                      color: AppColors.onSurface),
                  title: const Text('Settings',
                      style: TextStyle(color: AppColors.onBackground)),
                  trailing: const Icon(Icons.arrow_forward_ios,
                      size: 14, color: AppColors.onSurface),
                  onTap: () => context.push('/settings'),
                ),

                // Feedback
                ListTile(
                  leading: const Icon(Icons.feedback_outlined,
                      color: AppColors.onSurface),
                  title: const Text('Send Feedback',
                      style: TextStyle(color: AppColors.onBackground)),
                  trailing: const Icon(Icons.arrow_forward_ios,
                      size: 14, color: AppColors.onSurface),
                  onTap: _showFeedbackSheet,
                ),

                const Divider(),
                const SizedBox(height: 8),

                // Logout
                ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.angry),
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: AppColors.angry),
                  ),
                  onTap: () async {
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
            ),
    );
  }

  Widget _statCard(BuildContext context, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
