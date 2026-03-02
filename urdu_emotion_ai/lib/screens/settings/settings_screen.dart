import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/email_report_service.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _sensitivity = 0.5;
  bool _pushEnabled = true;
  bool _emailEnabled = false;
  bool _loadingPrefs = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loadingPrefs = false);
      return;
    }
    try {
      final profile = await FirestoreService.instance.getUserProfile(uid);
      if (profile != null && mounted) {
        setState(() {
          _sensitivity = (profile.sensitivityThreshold ?? 0.5).clamp(0.0, 1.0);
          _pushEnabled = profile.pushNotificationsEnabled ?? true;
          _emailEnabled = profile.weeklyEmailEnabled ?? false;
        });
      }
    } catch (_) {
      // Use defaults if Firestore is unavailable.
    }
    if (mounted) setState(() => _loadingPrefs = false);
  }

  Future<void> _savePreferences() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirestoreService.instance.updateUserPreferences(
        uid: uid,
        sensitivityThreshold: _sensitivity,
        pushNotificationsEnabled: _pushEnabled,
        weeklyEmailEnabled: _emailEnabled,
      );
    } catch (_) {
      // Best-effort save.
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _showSensitivitySheet() {
    double temp = _sensitivity;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
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
                    'Detection Sensitivity',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Higher sensitivity accepts lower confidence scores. Lower sensitivity only accepts high confidence results.',
                    style: Theme.of(
                      ctx,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Low',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        '${(temp * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                      const Text(
                        'High',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: temp,
                    min: 0.0,
                    max: 1.0,
                    divisions: 4,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setSheetState(() => temp = v),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() => _sensitivity = temp);
                        _savePreferences();
                        Navigator.pop(ctx);
                        _showSnack(
                          'Sensitivity set to ${(temp * 100).toStringAsFixed(0)}%',
                        );
                      },
                      child: const Text('Save'),
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

  void _showAbout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Urdu Emotion AI'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version 1.0.0',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Air University Final Year Project\n© 2026',
              style: TextStyle(fontSize: 12, color: AppColors.onSurface),
            ),
            SizedBox(height: 16),
            Text(
              'An AI-powered Urdu speech emotion recognition app. '
              'Record your voice and receive real-time emotion analysis '
              'across 4 emotions.',
              style: TextStyle(color: AppColors.onSurface),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AuthService.instance.isAdmin;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loadingPrefs
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // ── Detection ──────────────────────────────────────────────
                _sectionHeader('Detection'),
                _settingTile(
                  icon: Icons.tune,
                  title: 'Sensitivity',
                  subtitle:
                      'Threshold: ${(_sensitivity * 100).toStringAsFixed(0)}%',
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: isAdmin ? null : _showSensitivitySheet,
                ),

                // ── Notifications ──────────────────────────────────────────
                _sectionHeader('Notifications'),
                _settingTile(
                  icon: Icons.notifications_outlined,
                  title: 'Push Notifications',
                  subtitle: 'Emotion alerts and session reminders',
                  trailing: Switch(
                    value: _pushEnabled,
                    activeThumbColor: AppColors.primary,
                    onChanged: isAdmin
                        ? null
                        : (val) {
                            setState(() => _pushEnabled = val);
                            _savePreferences();
                            _showSnack(
                              val
                                  ? 'Push notifications enabled'
                                  : 'Push notifications disabled',
                            );
                          },
                  ),
                ),
                _settingTile(
                  icon: Icons.email_outlined,
                  title: 'Weekly Email Report',
                  subtitle: 'Receive weekly emotion summaries',
                  trailing: Switch(
                    value: _emailEnabled,
                    activeThumbColor: AppColors.primary,
                    onChanged: isAdmin
                        ? null
                        : (val) {
                            setState(() => _emailEnabled = val);
                            _savePreferences();
                            _showSnack(
                              val
                                  ? 'Weekly email reports enabled'
                                  : 'Weekly email reports disabled',
                            );
                          },
                  ),
                ),
                _settingTile(
                  icon: Icons.send_outlined,
                  title: 'Send Weekly Report',
                  subtitle: 'Receive your weekly emotion summary now',
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: isAdmin
                      ? null
                      : () async {
                          if (!_emailEnabled) {
                            _showSnack(
                                'Enable Weekly Email Report first.');
                            return;
                          }
                          final uid =
                              FirebaseAuth.instance.currentUser?.uid;
                          if (uid == null) {
                            _showSnack(
                                'You need to be logged in to send a test email.');
                            return;
                          }
                          final profile = await FirestoreService.instance
                              .getUserProfile(uid);
                          if (profile == null || profile.email.isEmpty) {
                            _showSnack('No email found for your account.');
                            return;
                          }
                          if (!context.mounted) return;
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Send Test Email?'),
                              content: Text(
                                'Do you want to receive a test email at '
                                '${profile.email}?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, true),
                                  child: const Text('Send'),
                                ),
                              ],
                            ),
                          );
                          if (confirm != true || !context.mounted) return;
                          try {
                            await EmailReportService.instance
                                .sendTestEmail(profile);
                            if (context.mounted) {
                              _showSnack('Test email sent. Check your inbox.');
                            }
                          } catch (_) {
                            if (context.mounted) {
                              _showSnack('Failed to send. Please try again.');
                            }
                          }
                        },
                ),

                // ── Storage ────────────────────────────────────────────────
                _sectionHeader('Storage'),
                _settingTile(
                  icon: Icons.delete_outline,
                  title: 'Clear All Data',
                  subtitle: 'Delete all saved session logs',
                  titleColor: AppColors.angry,
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: AppColors.angry,
                  ),
                  onTap: isAdmin
                      ? null
                      : () async {
                          final uid = FirebaseAuth.instance.currentUser?.uid;
                          if (uid == null) {
                            _showSnack(
                              'You need to be logged in to clear data.',
                            );
                            return;
                          }

                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Clear All Data?'),
                              content: const Text(
                                'Are you sure you want to clear all your saved '
                                'session data? This action cannot be undone and '
                                'your data will not be recoverable.',
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
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );

                          if (confirm != true || !context.mounted) return;
                          await FirestoreService.instance.deleteAllSessions(
                            uid,
                          );
                          if (!context.mounted) return;
                          _showSnack(
                            'All your saved session data has been cleared.',
                          );
                        },
                ),

                // ── App ────────────────────────────────────────────────────
                _sectionHeader('App'),
                _settingTile(
                  icon: Icons.info_outline,
                  title: 'About',
                  subtitle: 'Version 1.0.0 · Air University FYP',
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                  onTap: _showAbout,
                ),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppColors.onSurface),
      title: Text(
        title,
        style: TextStyle(color: titleColor ?? AppColors.onBackground),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: AppColors.onSurface, fontSize: 12),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
