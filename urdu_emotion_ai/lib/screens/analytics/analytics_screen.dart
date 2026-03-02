import 'dart:io';
import 'package:csv/csv.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/firestore_service.dart';
import '../../core/theme/app_colors.dart';

// ─── Screen ───────────────────────────────────────────────────────────────────
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  String _period = '7D';
  bool _loading = true;

  // Computed data from Firestore
  List<SessionRecord> _sessions = [];
  int _totalSessions = 0;
  int _daysTracked = 0;
  double _avgMoodScore = 0;
  String _mostCommonEmotion = '--';
  Map<String, double> _emotionCounts = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = AuthService.instance.firebaseUser;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final sessions =
          await FirestoreService.instance.getAllSessions(user.uid);

      final totalSessions = sessions.length;

      // Distinct days tracked
      final daySet = <String>{};
      for (final s in sessions) {
        if (s.timestamp != null) {
          final dt = s.timestamp!.toDate();
          daySet.add('${dt.year}-${dt.month}-${dt.day}');
        }
      }
      final daysTracked = daySet.length;

      // Avg confidence as mood score (0-100)
      double avgMoodScore = 0;
      if (sessions.isNotEmpty) {
        final totalConf =
            sessions.fold<double>(0, (sum, s) => sum + s.confidence);
        avgMoodScore = totalConf / sessions.length;
      }

      // Emotion frequency
      final Map<String, double> emotionCounts = {};
      for (final s in sessions) {
        emotionCounts[s.emotion] = (emotionCounts[s.emotion] ?? 0) + 1;
      }

      // Most common emotion
      String mostCommon = '--';
      if (emotionCounts.isNotEmpty) {
        mostCommon = (emotionCounts.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
      }

      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _totalSessions = totalSessions;
        _daysTracked = daysTracked;
        _avgMoodScore = avgMoodScore;
        _mostCommonEmotion = mostCommon;
        _emotionCounts = emotionCounts;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _shortDayName(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(weekday - 1) % 7];
  }

  /// Returns (scores, labels) for the confidence trend chart based on _period.
  (List<double>, List<String>) _getMoodTrendData() {
    final days = _period == '30D' ? 30 : 7;
    final now = DateTime.now();
    final labels = <String>[];
    final scores = <double>[];
    for (int i = days - 1; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final dayKey = '${day.year}-${day.month}-${day.day}';
      labels.add(_period == '30D'
          ? '${day.month}/${day.day}'
          : _shortDayName(day.weekday));

      final daySessions = _sessions.where((s) {
        if (s.timestamp == null) return false;
        final dt = s.timestamp!.toDate();
        return '${dt.year}-${dt.month}-${dt.day}' == dayKey;
      }).toList();

      if (daySessions.isEmpty) {
        scores.add(0);
      } else {
        final avg = daySessions.fold<double>(
                0, (sum, s) => sum + s.confidence) /
            daySessions.length;
        scores.add(avg);
      }
    }
    return (scores, labels);
  }

  Color _moodColor(double score) {
    if (score >= 70) return AppColors.happy;
    if (score >= 50) return AppColors.neutral;
    if (score >= 30) return AppColors.sad;
    return AppColors.angry;
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

  // ── CSV Export ─────────────────────────────────────────────────────────────
  static const _channel = MethodChannel('com.example.urdu_emotion_ai/audio_picker');

  Future<void> _exportCsv() async {
    if (_sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data to export.')),
      );
      return;
    }

    final rows = <List<String>>[
      ['Session ID', 'Emotion', 'Confidence (%)', 'Duration (s)', 'Date'],
    ];
    for (final s in _sessions) {
      final date = s.timestamp != null
          ? s.timestamp!.toDate().toIso8601String()
          : 'N/A';
      rows.add([
        s.id,
        s.emotion,
        s.confidence.toStringAsFixed(1),
        s.durationSeconds.toString(),
        date,
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'emotion_analytics_$timestamp.csv';

    try {
      // Write CSV to a temp file first
      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File('${tmpDir.path}/$fileName');
      await tmpFile.writeAsString(csv);

      bool saved = false;
      if (Platform.isAndroid) {
        // Use MediaStore via platform channel so the file appears
        // in the public Downloads folder (same as audio recordings).
        final result = await _channel.invokeMethod<bool>(
          'saveToDownloads',
          {'path': tmpFile.path, 'fileName': fileName, 'mimeType': 'text/csv'},
        );
        saved = result == true;
      } else {
        // iOS / desktop fallback
        Directory? dir = await getDownloadsDirectory();
        dir ??= await getExternalStorageDirectory();
        dir ??= await getApplicationDocumentsDirectory();
        await tmpFile.copy('${dir.path}/$fileName');
        saved = true;
      }

      // Clean up temp file
      if (await tmpFile.exists()) await tmpFile.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              saved
                  ? 'CSV exported to Downloads folder.'
                  : 'Could not export CSV.',
            ),
            backgroundColor: saved ? null : AppColors.angry,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.angry,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export CSV',
            onPressed: _exportCsv,
          ),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No sessions recorded yet.\nRecord your first session to see analytics!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.onSurface),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    // ── Summary cards ────────────────────────────────────────
                    Row(
                      children: [
                        _SummaryCard(
                          label: 'Total Sessions',
                          value: '$_totalSessions',
                          icon: Icons.mic_outlined,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        _SummaryCard(
                          label: 'Days Tracked',
                          value: '$_daysTracked',
                          icon: Icons.calendar_today_outlined,
                          color: AppColors.happy,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _SummaryCard(
                          label: 'Avg Confidence',
                          value: '${_avgMoodScore.toInt()}%',
                          icon: Icons.sentiment_satisfied_alt_outlined,
                          color: _moodColor(_avgMoodScore),
                        ),
                        const SizedBox(width: 12),
                        _SummaryCard(
                          label: 'Most Common',
                          value:
                              '$_mostCommonEmotion ${_emojiFor(_mostCommonEmotion)}',
                          icon: Icons.emoji_emotions_outlined,
                          color: AppColors.forEmotion(_mostCommonEmotion),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Mood trend line chart ────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const _SecTitle('Confidence Trend'),
                        Row(
                          children: ['7D', '30D']
                              .map(
                                (p) => _PeriodChip(
                                  label: p,
                                  active: _period == p,
                                  onTap: () =>
                                      setState(() => _period = p),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ChartCard(
                      child: Builder(
                        builder: (context) {
                          final (scores, labels) = _getMoodTrendData();
                          return SizedBox(
                            height: 175,
                            child: scores.every((v) => v == 0)
                                ? const Center(
                                    child: Text('No data for this period',
                                        style: TextStyle(
                                            color: AppColors.onSurface,
                                            fontSize: 12)),
                                  )
                                : LineChart(_buildMoodChart(scores, labels)),
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Emotion frequency bar chart ──────────────────────────
                    const _SecTitle('Emotion Frequency'),
                    const SizedBox(height: 10),
                    _ChartCard(
                      child: SizedBox(
                        height: 175,
                        child: _emotionCounts.isEmpty
                            ? const Center(
                                child: Text('No data',
                                    style: TextStyle(
                                        color: AppColors.onSurface,
                                        fontSize: 12)),
                              )
                            : BarChart(_buildFrequencyChart()),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Most common emotions ────────────────────────────────
                    const _SecTitle('Most Common Emotions'),
                    const SizedBox(height: 10),
                    _ChartCard(
                      child: Column(
                        children: () {
                          final entries =
                              _emotionCounts.entries.toList()
                                ..sort(
                                    (a, b) => b.value.compareTo(a.value));
                          final total =
                              entries.fold(0.0, (s, e) => s + e.value);
                          if (total == 0) {
                            return <Widget>[
                              const Text('No data',
                                  style: TextStyle(
                                      color: AppColors.onSurface))
                            ];
                          }
                          return entries.asMap().entries.map((entry) {
                            final i = entry.key;
                            final e = entry.value;
                            final color = AppColors.forEmotion(e.key);
                            final pct = (e.value / total * 100)
                                .toStringAsFixed(0);
                            return Padding(
                              padding: EdgeInsets.only(
                                  bottom:
                                      i < entries.length - 1 ? 14 : 0),
                              child: Row(
                                children: [
                                  Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color:
                                          color.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${i + 1}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(_emojiFor(e.key),
                                      style:
                                          const TextStyle(fontSize: 18)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment
                                                  .spaceBetween,
                                          children: [
                                            Text(
                                              e.key,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight:
                                                    FontWeight.w600,
                                                color: AppColors
                                                    .onBackground,
                                              ),
                                            ),
                                            Text(
                                              '${e.value.toInt()} · $pct%',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color:
                                                    AppColors.onSurface,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          child:
                                              LinearProgressIndicator(
                                            value: e.value / total,
                                            minHeight: 7,
                                            backgroundColor: color
                                                .withValues(alpha: 0.12),
                                            valueColor:
                                                AlwaysStoppedAnimation<
                                                    Color>(color),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList();
                        }(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Recent sessions ──────────────────────────────────────
                    const _SecTitle('Recent Sessions'),
                    const SizedBox(height: 10),
                    ..._sessions.take(10).map((s) => _SessionTile(
                          session: s,
                          emojiFor: _emojiFor,
                        )),
                  ],
                ),
    );
  }

  // ── Mood line chart ───────────────────────────────────────────────────────
  LineChartData _buildMoodChart(List<double> scores, List<String> labels) {

    return LineChartData(
      lineBarsData: [
        LineChartBarData(
          spots: List.generate(
              scores.length, (i) => FlSpot(i.toDouble(), scores[i])),
          isCurved: true,
          color: AppColors.primary,
          barWidth: 3,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, _, _, _) => FlDotCirclePainter(
              radius: 4,
              color: _moodColor(spot.y),
              strokeWidth: 2,
              strokeColor: AppColors.background,
            ),
          ),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                AppColors.primary.withValues(alpha: 0.22),
                AppColors.primary.withValues(alpha: 0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: labels.length > 10 ? 5.0 : 1.0,
            getTitlesWidget: (v, m) {
              final idx = v.toInt();
              if (idx < 0 || idx >= labels.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(labels[idx],
                    style: const TextStyle(
                        fontSize: 9, color: AppColors.onSurface)),
              );
            },
            reservedSize: 22,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 25,
            getTitlesWidget: (v, m) => Text(
              v.toInt().toString(),
              style: const TextStyle(
                  fontSize: 9, color: AppColors.onSurface),
            ),
            reservedSize: 26,
          ),
        ),
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 25,
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.divider, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: (scores.length - 1).toDouble(),
      minY: 0,
      maxY: 100,
    );
  }

  // ── Emotion frequency bar chart ───────────────────────────────────────────
  BarChartData _buildFrequencyChart() {
    final entries = _emotionCounts.entries.toList();
    final maxVal =
        entries.fold<double>(0, (m, e) => e.value > m ? e.value : m);

    return BarChartData(
      maxY: (maxVal * 1.2).ceilToDouble(),
      barGroups: List.generate(entries.length, (i) {
        final color = AppColors.forEmotion(entries[i].key);
        return BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: entries[i].value,
              color: color,
              width: 34,
              borderRadius: BorderRadius.circular(6),
            ),
          ],
        );
      }),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, m) {
              final idx = v.toInt();
              if (idx < 0 || idx >= entries.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(entries[idx].key,
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.onSurface)),
              );
            },
            reservedSize: 26,
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: (maxVal / 4).ceilToDouble().clamp(1, 100),
            getTitlesWidget: (v, m) => Text(
              v.toInt().toString(),
              style: const TextStyle(
                  fontSize: 9, color: AppColors.onSurface),
            ),
            reservedSize: 22,
          ),
        ),
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: (maxVal / 4).ceilToDouble().clamp(1, 100),
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.divider, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _SecTitle extends StatelessWidget {
  const _SecTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      );
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: child,
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      label,
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(left: 6),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active ? AppColors.primary : AppColors.divider),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.onSurface,
            ),
          ),
        ),
      );
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.emojiFor,
  });

  final SessionRecord session;
  final String Function(String) emojiFor;

  String _formatDate(SessionRecord s) {
    if (s.timestamp == null) return 'N/A';
    final dt = s.timestamp!.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionDay = DateTime(dt.year, dt.month, dt.day);

    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');

    if (sessionDay == today) return 'Today, $hour:$min';
    if (sessionDay == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, $hour:$min';
    }
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forEmotion(session.emotion);
    final confidence = session.confidence.round();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(emojiFor(session.emotion),
              style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.emotion,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(session),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.onSurface),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$confidence%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
