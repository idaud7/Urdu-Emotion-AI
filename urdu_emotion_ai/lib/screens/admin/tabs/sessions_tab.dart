import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/theme/app_colors.dart';

class SessionsTab extends StatefulWidget {
  const SessionsTab({super.key});

  @override
  State<SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends State<SessionsTab>
    with SingleTickerProviderStateMixin {
  String? _filterEmotion; // null = show all
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  bool _loading = true;
  List<SessionRecord> _allSessions = [];
  // uid → user display name cache
  Map<String, String> _userNames = {};

  StreamSubscription<List<SessionRecord>>? _sessionsSub;
  StreamSubscription<List<UserProfile>>? _usersSub;

  List<SessionRecord> get _filtered => _filterEmotion == null
      ? _allSessions
      : _allSessions
          .where((s) => s.emotion == _filterEmotion)
          .toList();

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
    _sessionsSub = FirestoreService.instance.watchAllSessionsAdmin().listen(
      (sessions) {
        if (!mounted) return;
        // Sort by timestamp descending (most recent first)
        sessions.sort((a, b) {
          final ta = a.timestamp;
          final tb = b.timestamp;
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
        setState(() {
          _allSessions = sessions;
          _loading = false;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );

    _usersSub = FirestoreService.instance.watchAllUsers().listen(
      (users) {
        if (!mounted) return;
        final Map<String, String> nameMap = {};
        for (final u in users) {
          // Pick the best available display string: name → email → short UID
          String label = u.displayName.isNotEmpty
              ? u.displayName
              : u.email.isNotEmpty
                  ? u.email
                  : 'User ${u.uid.substring(0, 6)}';
          nameMap[u.uid] = label;
        }
        setState(() {
          _userNames = nameMap;
        });
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _sessionsSub?.cancel();
    _usersSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString();
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

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
        // ── Filter chips ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _EmotionChip(
                  label: 'All',
                  color: AppColors.primary,
                  active: _filterEmotion == null,
                  onTap: () => setState(() => _filterEmotion = null),
                ),
                const SizedBox(width: 8),
                ...['Happy', 'Sad', 'Angry', 'Neutral'].map((e) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _EmotionChip(
                        label: e,
                        color: AppColors.forEmotion(e),
                        active: _filterEmotion == e,
                        onTap: () => setState(() => _filterEmotion = e),
                      ),
                    )),
              ],
            ),
          ),
        ),

        // ── Count ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${filtered.length} session${filtered.length == 1 ? '' : 's'}',
              style:
                  const TextStyle(fontSize: 12, color: AppColors.onSurface),
            ),
          ),
        ),

        // ── Session list ──────────────────────────────────────────────────
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('No sessions found.',
                      style: TextStyle(color: AppColors.onSurface)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = filtered[i];
                    final name = _userNames[s.uid];
                    final display = (name != null && name.isNotEmpty)
                        ? name
                        : 'User ${s.uid.length > 6 ? s.uid.substring(0, 6) : s.uid}';
                    return _SessionCard(
                      session: s,
                      userName: display,
                      formatDuration: _formatDuration,
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

// ─── Emotion filter chip ──────────────────────────────────────────────────────
class _EmotionChip extends StatelessWidget {
  const _EmotionChip({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.15) : AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: active ? color : AppColors.divider),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  active ? FontWeight.w600 : FontWeight.normal,
              color: active ? color : AppColors.onSurface,
            ),
          ),
        ),
      );
}

// ─── Session card ─────────────────────────────────────────────────────────────
class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.userName,
    required this.formatDuration,
  });
  final SessionRecord session;
  final String userName;
  final String Function(int) formatDuration;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forEmotion(session.emotion);
    final confidencePct = session.confidence.round();

    // Format date / time from timestamp
    String dateStr = '';
    String timeStr = '';
    if (session.timestamp != null) {
      final dt = session.timestamp!.toDate();
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      dateStr = '${months[dt.month - 1]} ${dt.day}';
      timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // Emotion accent bar
          Container(
            width: 4,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ID + date/time
                Row(
                  children: [
                    Text(
                      session.id.length > 6
                          ? session.id.substring(0, 6)
                          : session.id,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$dateStr  $timeStr',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.onSurface),
                    ),
                  ],
                ),
                const SizedBox(height: 3),

                // User name
                Text(
                  userName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.onBackground,
                  ),
                ),
                const SizedBox(height: 5),

                // Emotion badge · duration · confidence
                Row(
                  children: [
                    // Emotion badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        session.emotion,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Duration
                    const Icon(Icons.timer_outlined,
                        size: 12, color: AppColors.onSurface),
                    const SizedBox(width: 3),
                    Text(
                      formatDuration(session.durationSeconds),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.onSurface),
                    ),
                    const SizedBox(width: 10),

                    // Confidence
                    const Icon(Icons.bar_chart_rounded,
                        size: 12, color: AppColors.onSurface),
                    const SizedBox(width: 3),
                    Text(
                      '$confidencePct% conf.',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.onSurface),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
