import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/firestore_service.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _emojiFor(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return '😊';
      case 'sad':
        return '😢';
      case 'angry':
        return '😡';
      default:
        return '😐';
    }
  }

  String _insightFor(String topEmotion) {
    final pool = _insights(topEmotion);
    final seed = topEmotion.hashCode ^ DateTime.now().day;
    return pool[seed.abs() % pool.length];
  }

  List<String> _insights(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return [
          'Your voice reflects a bright emotional state today. Keep nurturing those positive feelings through gratitude and connection with the people around you.',
          'Great energy detected in your recent sessions! Channel this positivity into a creative project or share your good mood with someone who needs it.',
          'You are on a wonderful emotional streak. Use this uplifted state to tackle goals that matter to you and spread kindness wherever you go today.',
          'Your emotional well being is glowing right now. A happy mind is a productive mind, so make the most of this wonderful phase in your life.',
          'Positivity is flowing through your sessions. Consider journaling today to capture what is making you feel this good and carry it forward.',
        ];
      case 'sad':
        return [
          'Your sessions show low emotional energy right now. Take a moment to breathe deeply, step outside for fresh air, and be gentle with yourself today.',
          'It is okay to feel sad sometimes. Reach out to a friend or family member, share how you feel, and remember that brighter days are always ahead.',
          'Your voice suggests you may be going through a tough time. Try listening to uplifting music, taking a short walk, or writing down your thoughts.',
          'Sadness is a natural emotion and it will pass. Try a few minutes of mindful breathing or spend time doing something small that brings you comfort.',
          'You deserve care and comfort right now. Talk to someone you trust, get some rest, and remind yourself that you are stronger than you feel today.',
        ];
      case 'angry':
        return [
          'Elevated stress is present in your recent sessions. Try stepping away from the source of tension, take five slow deep breaths, and gently reset your mind.',
          'Your voice shows signs of frustration. A short walk, some cold water, or a few minutes of stretching can help release that built up tension quickly.',
          'When anger rises, pause before reacting. Find a quiet space, breathe slowly, and give yourself permission to process the emotion before responding.',
          'Stress levels appear high in your recent recordings. A brief meditation, a call to a trusted friend, or simply resting can help restore your inner calm.',
          'You are feeling strong emotions right now and that is completely valid. Channel that energy into exercise, journaling, or a creative outlet to find relief.',
        ];
      case 'neutral':
        return [
          'Your emotional state is steady and balanced. This is a great time to set new goals, build positive habits, and invest in your personal growth.',
          'A calm and composed mind is a powerful asset. Use this stable phase to plan ahead, learn something new, or simply enjoy the peace you have found.',
          'Your balance and composure are coming through clearly. Neutral is a strong foundation for growth, so consider starting something meaningful that inspires you.',
          'Emotional steadiness is detected across your sessions. You are in a clear headed state that is perfect for making thoughtful and meaningful decisions.',
          'A steady mind leads to steady progress. Take advantage of this balanced phase to focus deeply on what truly matters most to you right now.',
        ];
      default:
        return [
          'Record your voice regularly to gain deeper insights into your emotional well being over time.',
          'Each session helps build a clearer picture of your emotional patterns and supports your overall mental well being.',
          'Consistency is key to understanding your emotions. Keep recording to unlock meaningful insights about your well being.',
          'Your journey toward emotional awareness starts with regular check ins. Keep going and the patterns will become clearer over time.',
          'Every session is a step toward better understanding of yourself. Stay consistent and you will begin to see powerful patterns emerge.',
        ];
    }
  }

  String _formatSessionLabel(SessionRecord s) {
    final ts = s.timestamp?.toDate();
    if (ts == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(ts.year, ts.month, ts.day);
    final timeStr =
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    if (day == today) {
      return 'Today, $timeStr';
    }
    if (day == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, $timeStr';
    }
    return '${ts.month}/${ts.day}  $timeStr';
  }

  String _topEmotionFromSessions(List<SessionRecord> sessions) {
    if (sessions.isEmpty) return 'Neutral';
    final Map<String, int> counts = {};
    for (final s in sessions) {
      counts[s.emotion] = (counts[s.emotion] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.first.key;
  }

  String _displayNameFrom(UserProfile? profile, dynamic firebaseUser, bool isAdmin) {
    if (isAdmin) return 'Admin';
    if (profile != null && profile.displayName.isNotEmpty) return profile.displayName;
    if (firebaseUser?.displayName?.isNotEmpty == true) return firebaseUser!.displayName!;
    if (firebaseUser?.email != null) return firebaseUser!.email ?? 'User';
    return 'User';
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final user = auth.firebaseUser;
    final uid = user?.uid;
    final isAdmin = auth.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => context.push('/profile'),
              child: const CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.primary,
                child: Icon(Icons.person, size: 19, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.primary.withValues(alpha: 0.16),
              AppColors.background,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Greeting (uses Firestore for real-time name updates) ──────
                Text(
                  _greeting(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurface),
                ),
                const SizedBox(height: 2),
                uid != null
                    ? StreamBuilder<UserProfile?>(
                        stream: FirestoreService.instance.watchUserProfile(uid),
                        builder: (context, snap) {
                          final profile = snap.data;
                          final displayName =
                              _displayNameFrom(profile, user, isAdmin);
                          return Text(
                            displayName,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.onBackground,
                                ),
                          );
                        },
                      )
                    : Text(
                        isAdmin ? 'Admin' : 'User',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.onBackground,
                            ),
                      ),

                const SizedBox(height: 20),

                // ── Hero card: today's check-in ─────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withValues(alpha: 0.8),
                        AppColors.primaryLight.withValues(alpha: 0.4),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.45),
                        blurRadius: 32,
                        spreadRadius: 4,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Today\'s check‑in',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Check your mood\nin seconds',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Tap below to analyse your current mood using your voice.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => context.go('/record'),
                          icon: const Icon(Icons.mic_rounded),
                          label: const Text('Start quick check'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // ── Quick actions grid ──────────────────────────────────────
                Text(
                  'Quick actions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.mic_rounded,
                        title: 'Record live',
                        subtitle: 'Analyse in real time',
                        color: AppColors.primary,
                        onTap: () => context.go('/record'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.upload_file_rounded,
                        title: 'Upload audio',
                        subtitle: 'Use a saved clip',
                        color: AppColors.primaryLight,
                        onTap: () => context.go('/record'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.bar_chart_rounded,
                        title: 'View analytics',
                        subtitle: 'Trends & history',
                        color: AppColors.happy,
                        onTap: () => context.go('/analytics'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.history_rounded,
                        title: 'Previous results',
                        subtitle: 'See recent moods',
                        color: AppColors.neutral,
                        onTap: () => context.go('/analytics'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 28),

                // ── Recent emotions strip ────────────────────────────────────
                Text(
                  'Recent emotions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 80,
                  child: FutureBuilder<List<SessionRecord>>(
                    future: user == null
                        ? Future.value(const <SessionRecord>[])
                        : FirestoreService.instance
                            .getRecentSessions(user.uid, limit: 10),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          ),
                        );
                      }
                      final sessions =
                          snapshot.data ?? const <SessionRecord>[];
                      if (sessions.isEmpty) {
                        return const Center(
                          child: Text(
                            'No sessions yet. Record to see your history here.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.onSurface,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: sessions.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final s = sessions[index];
                          final label = _formatSessionLabel(s);
                          return _RecentEmotionChip(
                            emoji: _emojiFor(s.emotion),
                            emotion: s.emotion,
                            label: label,
                            color: AppColors.forEmotion(s.emotion),
                          );
                        },
                      );
                    },
                  ),
                ),

                const SizedBox(height: 28),

                // ── AI suggestions ──────────────────────────────────────────
                Text(
                  'AI suggestions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.psychology_outlined,
                          color: AppColors.primaryLight,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FutureBuilder<List<SessionRecord>>(
                              future: user == null
                                  ? Future.value(
                                      const <SessionRecord>[])
                                  : FirestoreService.instance
                                      .getRecentSessions(user.uid,
                                          limit: 20),
                              builder: (context, snapshot) {
                                final sessions =
                                    snapshot.data ?? const <SessionRecord>[];
                                final topEmotion =
                                    _topEmotionFromSessions(sessions);
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Based on your recent mood',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.onBackground,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _insightFor(topEmotion),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.onSurface,
                                        height: 1.55,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Quick action card ─────────────────────────────────────────────────────────
class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.onBackground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: AppColors.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Recent emotion chip (horizontal strip) ────────────────────────────────────
class _RecentEmotionChip extends StatelessWidget {
  const _RecentEmotionChip({
    required this.emoji,
    required this.emotion,
    required this.label,
    required this.color,
  });

  final String emoji;
  final String emotion;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 6),
              Text(
                emotion,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppColors.onSurface),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
