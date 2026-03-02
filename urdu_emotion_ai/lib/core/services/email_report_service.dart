import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'firestore_service.dart';

class EmailReportService {
  EmailReportService._();
  static final EmailReportService instance = EmailReportService._();

  static const String _serviceId = 'service_97loxk4';
  static const String _templateId = 'template_wu5nzuc';
  static const String _publicKey = 'NMOV4RISa65uCQBHT';

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _formatDate(DateTime dt) =>
      '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Sends a test email using the user's real session data so the output
  /// looks exactly like a real weekly report.
  Future<void> sendTestEmail(UserProfile profile) async {
    if (profile.email.isEmpty) return;

    final now = DateTime.now();
    final weekStart = now.subtract(const Duration(days: 7));
    final sessions = await FirestoreService.instance.getAllSessions(
      profile.uid,
    );
    final recent = _sessionsInRange(sessions, weekStart, now);
    final used = recent.isNotEmpty ? recent : sessions;

    final totalSessions = used.length;
    final totalMinutes = _minutesFrom(used);
    final emotionCounts = _countEmotions(used);
    final topEmotion = _topEmotion(emotionCounts);
    final emotionBreakdown = _buildBreakdown(emotionCounts);
    final activeDays = _activeDays(used);
    final motivational = _buildMotivational(
      topEmotion: topEmotion,
      totalSessions: totalSessions,
      totalMinutes: totalMinutes,
      activeDays: activeDays,
    );

    await _sendEmail(
      toEmail: profile.email,
      userName: profile.displayName.isNotEmpty
          ? profile.displayName
          : profile.email.split('@').first,
      weekStart: _formatDate(weekStart),
      weekEnd: _formatDate(now),
      sessionsCount: totalSessions,
      minutesCount: totalMinutes,
      topEmotion: topEmotion,
      emotionBreakdown: emotionBreakdown,
      motivationalMsg: motivational,
    );
  }

  /// Called on every app open. Sends the weekly report only if:
  ///   - the user has opted in
  ///   - 7 or more days have passed since the last send
  Future<void> maybeSendWeeklyEmail(UserProfile profile) async {
    if (!(profile.weeklyEmailEnabled ?? false)) return;
    if (profile.email.isEmpty) return;

    final now = DateTime.now();
    final lastSent = profile.weeklyEmailLastSent?.toDate();
    if (lastSent != null && now.difference(lastSent).inDays < 7) return;

    final weekStart = now.subtract(const Duration(days: 7));
    final sessions = await FirestoreService.instance.getAllSessions(
      profile.uid,
    );
    final recent = _sessionsInRange(sessions, weekStart, now);
    // If no sessions this week still send a gentle nudge.
    final used = recent.isNotEmpty ? recent : <SessionRecord>[];

    final totalSessions = used.length;
    final totalMinutes = _minutesFrom(used);
    final emotionCounts = _countEmotions(used);
    final topEmotion = _topEmotion(emotionCounts);
    final emotionBreakdown = used.isEmpty
        ? 'No sessions recorded this week'
        : _buildBreakdown(emotionCounts);
    final activeDays = _activeDays(used);
    final motivational = _buildMotivational(
      topEmotion: topEmotion,
      totalSessions: totalSessions,
      totalMinutes: totalMinutes,
      activeDays: activeDays,
    );

    await _sendEmail(
      toEmail: profile.email,
      userName: profile.displayName.isNotEmpty
          ? profile.displayName
          : profile.email.split('@').first,
      weekStart: _formatDate(weekStart),
      weekEnd: _formatDate(now),
      sessionsCount: totalSessions,
      minutesCount: totalMinutes,
      topEmotion: topEmotion,
      emotionBreakdown: emotionBreakdown,
      motivationalMsg: motivational,
    );

    await FirestoreService.instance.setWeeklyEmailLastSent(
      profile.uid,
      Timestamp.fromDate(now),
    );
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  List<SessionRecord> _sessionsInRange(
    List<SessionRecord> all,
    DateTime from,
    DateTime to,
  ) => all.where((s) {
    final ts = s.timestamp?.toDate();
    return ts != null && ts.isAfter(from) && ts.isBefore(to);
  }).toList();

  int _minutesFrom(List<SessionRecord> sessions) =>
      sessions.fold<int>(0, (acc, s) => acc + s.durationSeconds) ~/ 60;

  Map<String, int> _countEmotions(List<SessionRecord> sessions) {
    final Map<String, int> counts = {};
    for (final s in sessions) {
      counts[s.emotion] = (counts[s.emotion] ?? 0) + 1;
    }
    return counts;
  }

  String _topEmotion(Map<String, int> counts) {
    if (counts.isEmpty) return 'Neutral';
    return (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
  }

  int _activeDays(List<SessionRecord> sessions) => sessions
      .map((s) => s.timestamp?.toDate())
      .whereType<DateTime>()
      .map((d) => DateTime(d.year, d.month, d.day))
      .toSet()
      .length;

  /// Builds "Happy: 5 · Neutral: 3 · Sad: 2" sorted by frequency.
  String _buildBreakdown(Map<String, int> counts) {
    if (counts.isEmpty) return 'No sessions recorded this week';
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => '${e.key}: ${e.value}').join(' · ');
  }

  String _buildMotivational({
    required String topEmotion,
    required int totalSessions,
    required int totalMinutes,
    required int activeDays,
  }) {
    if (totalSessions == 0) {
      return 'No sessions were recorded this week. Try a short check-in to '
          'start tracking your emotional trends. Even one session gives you '
          'valuable insight into how you are feeling.';
    }

    final buffer = StringBuffer();
    buffer.write(
      'You recorded $totalSessions session${totalSessions == 1 ? '' : 's'} '
      'across $activeDays day${activeDays == 1 ? '' : 's'} '
      'this week, spending about $totalMinutes '
      'minute${totalMinutes == 1 ? '' : 's'} in total. ',
    );

    switch (topEmotion.toLowerCase()) {
      case 'happy':
        buffer.write(
          'Your most frequent emotion was happiness. Keep reinforcing the '
          'habits and connections that are supporting this positive state.',
        );
        break;
      case 'sad':
        buffer.write(
          'Your voice showed lower energy across several sessions. Consider '
          'small breaks, journaling, or talking with someone you trust. '
          'Brighter days are always ahead.',
        );
        break;
      case 'angry':
        buffer.write(
          'There were signs of elevated tension in your recordings. Short '
          'walks, breathing exercises, or quiet time can help reduce stress '
          'and restore your inner calm.',
        );
        break;
      default:
        buffer.write(
          'Your emotional tone stayed relatively balanced this week. '
          'Regular check-ins like these help reveal shifts in your '
          'well-being earlier over time.',
        );
    }
    return buffer.toString();
  }

  // ── EmailJS call ────────────────────────────────────────────────────────────

  Future<void> _sendEmail({
    required String toEmail,
    required String userName,
    required String weekStart,
    required String weekEnd,
    required int sessionsCount,
    required int minutesCount,
    required String topEmotion,
    required String emotionBreakdown,
    required String motivationalMsg,
  }) async {
    final uri = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

    final payload = jsonEncode({
      'service_id': _serviceId,
      'template_id': _templateId,
      'user_id': _publicKey,
      'template_params': {
        // To field in EmailJS template must be set to {{user_email}}
        'user_email': toEmail,
        'user_name': userName,
        'week_start': weekStart,
        'week_end': weekEnd,
        'sessions_count': sessionsCount,
        'minutes_count': minutesCount,
        'top_emotion': topEmotion,
        'emotion_breakdown': emotionBreakdown,
        'motivational_message': motivationalMsg,
      },
    });

    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('EmailJS error ${response.statusCode}: ${response.body}');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('EmailJS network error: $e');
      // Non-critical — never surface to the user.
    }
  }
}
