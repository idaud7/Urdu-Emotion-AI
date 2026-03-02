import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/services/firestore_service.dart';
import '../../../core/theme/app_colors.dart';

class OverviewTab extends StatefulWidget {
  const OverviewTab({super.key});

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab>
    with SingleTickerProviderStateMixin {
  String _period = '7D';
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  bool _loading = true;
  bool _sessionsLoaded = false;
  AdminStats? _stats;
  Map<String, double> _emotionDist = {};
  List<double> _weeklySessionCounts = List.filled(7, 0);
  // Emotion trends 7D (daily) and 30D (weekly)
  List<double> _happyTrend7D = [];
  List<double> _sadTrend7D = [];
  List<double> _angryTrend7D = [];
  List<double> _neutralTrend7D = [];
  List<double> _happyTrend30D = [];
  List<double> _sadTrend30D = [];
  List<double> _angryTrend30D = [];
  List<double> _neutralTrend30D = [];
  List<double> _peakHours = List.filled(24, 0);

  StreamSubscription<List<SessionRecord>>? _sessionsSub;
  StreamSubscription<List<UserProfile>>? _usersSub;
  int _realUserCount = 0;
  List<SessionRecord> _cachedSessions = [];

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
    _listenToSessions();
    _listenToUsers();
  }

  void _listenToSessions() {
    _sessionsSub = FirestoreService.instance.watchAllSessionsAdmin().listen(
      _onSessionsUpdate,
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  void _listenToUsers() {
    _usersSub = FirestoreService.instance.watchAllUsers().listen(
      (users) {
        // Count only real users, not admin accounts
        final count = users.where((u) => u.role != 'admin').length;
        if (!mounted) return;
        _realUserCount = count;
        // Rebuild stats with the correct user count
        _rebuildStats();
      },
      onError: (_) {
        if (mounted) {
          _rebuildStats();
        }
      },
    );
  }

  void _onSessionsUpdate(List<SessionRecord> sessions) {
    _cachedSessions = sessions;
    _sessionsLoaded = true;
    _rebuildStats();
  }

  /// Shared rebuild called whenever sessions OR users streams emit new data.
  /// Ensures user count is always up-to-date regardless of stream order.
  void _rebuildStats() {
    if (!mounted) return;
    // Wait until at least sessions are loaded; show partial data for users
    if (!_sessionsLoaded) return;

    final sessions = _cachedSessions;

    // ── Compute AdminStats locally ────────────────────────────────────────
    final totalSessions = sessions.length;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final activeToday = sessions
        .where(
          (s) =>
              s.timestamp != null && s.timestamp!.toDate().isAfter(todayStart),
        )
        .length;
    final totalMinutes =
        sessions.fold<int>(0, (acc, s) => acc + s.durationSeconds) ~/ 60;

    final stats = AdminStats(
      totalUsers: _realUserCount,
      totalSessions: totalSessions,
      totalMinutes: totalMinutes,
      activeToday: activeToday,
    );

    // Emotion distribution
    final Map<String, int> emotionCounts = {};
    for (final s in sessions) {
      emotionCounts[s.emotion] = (emotionCounts[s.emotion] ?? 0) + 1;
    }
    final total = sessions.length.toDouble().clamp(1, double.infinity);
    final emotionDist = emotionCounts.map(
      (k, v) => MapEntry(k, double.parse((v / total * 100).toStringAsFixed(1))),
    );

    // Weekly sessions (Mon-Sun) from last 7 days
    final weekCounts = List<double>.filled(7, 0);
    for (final s in sessions) {
      if (s.timestamp == null) continue;
      final dt = s.timestamp!.toDate();
      final diff = now.difference(dt).inDays;
      if (diff < 7) {
        final dayIdx = (dt.weekday - 1) % 7; // 0=Mon, 6=Sun
        weekCounts[dayIdx]++;
      }
    }

    // Emotion trends 7D (daily: Mon-Sun of last week)
    final trend7D = _computeTrend7D(sessions, now);
    // Emotion trends 30D (weekly averages: Wk1-Wk4)
    final trend30D = _computeTrend30D(sessions, now);

    // Peak hours
    final peakHrs = List<double>.filled(24, 0);
    for (final s in sessions) {
      if (s.timestamp == null) continue;
      peakHrs[s.timestamp!.toDate().hour]++;
    }

    setState(() {
      _stats = stats;
      _emotionDist = emotionDist;
      _weeklySessionCounts = weekCounts;
      _happyTrend7D = trend7D['Happy']!;
      _sadTrend7D = trend7D['Sad']!;
      _angryTrend7D = trend7D['Angry']!;
      _neutralTrend7D = trend7D['Neutral']!;
      _happyTrend30D = trend30D['Happy']!;
      _sadTrend30D = trend30D['Sad']!;
      _angryTrend30D = trend30D['Angry']!;
      _neutralTrend30D = trend30D['Neutral']!;
      _peakHours = peakHrs;
      _loading = false;
    });
  }

  Map<String, List<double>> _computeTrend7D(
    List<SessionRecord> sessions,
    DateTime now,
  ) {
    final result = <String, List<double>>{
      'Happy': List.filled(7, 0),
      'Sad': List.filled(7, 0),
      'Angry': List.filled(7, 0),
      'Neutral': List.filled(7, 0),
    };
    for (final s in sessions) {
      if (s.timestamp == null) continue;
      final dt = s.timestamp!.toDate();
      final diff = now.difference(dt).inDays;
      if (diff < 7) {
        final dayIdx = (dt.weekday - 1) % 7;
        final emotion = s.emotion;
        if (result.containsKey(emotion)) {
          result[emotion]![dayIdx]++;
        }
      }
    }
    return result;
  }

  Map<String, List<double>> _computeTrend30D(
    List<SessionRecord> sessions,
    DateTime now,
  ) {
    final result = <String, List<double>>{
      'Happy': List.filled(4, 0),
      'Sad': List.filled(4, 0),
      'Angry': List.filled(4, 0),
      'Neutral': List.filled(4, 0),
    };
    for (final s in sessions) {
      if (s.timestamp == null) continue;
      final dt = s.timestamp!.toDate();
      final diff = now.difference(dt).inDays;
      if (diff < 28) {
        final weekIdx = (diff ~/ 7).clamp(0, 3);
        final revIdx = 3 - weekIdx; // Wk1 = oldest, Wk4 = newest
        final emotion = s.emotion;
        if (result.containsKey(emotion)) {
          result[emotion]![revIdx]++;
        }
      }
    }
    return result;
  }

  @override
  void dispose() {
    _sessionsSub?.cancel();
    _usersSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  /// Aggregate 24 hourly buckets into 8 × 3-hour slots.
  List<double> get _peak3h {
    final result = List<double>.filled(8, 0.0);
    for (int i = 0; i < 24; i++) {
      result[i ~/ 3] += _peakHours[i];
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final stats = _stats;
    if (stats == null) {
      return const Center(
        child: Text(
          'Could not load data.',
          style: TextStyle(color: AppColors.onSurface),
        ),
      );
    }

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // ── Hero summary card ─────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.8),
                    AppColors.primaryLight.withValues(alpha: 0.4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 28,
                    spreadRadius: 4,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'System overview',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Monitor users, sessions and\nemotion trends in real time.',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _HeroStat(
                        label: 'Users',
                        value: stats.totalUsers.toString(),
                      ),
                      const SizedBox(width: 18),
                      _HeroStat(
                        label: 'Sessions',
                        value: stats.totalSessions.toString(),
                      ),
                      const SizedBox(width: 18),
                      _HeroStat(
                        label: 'Minutes',
                        value: stats.totalMinutes.toString(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // ── KPI Cards ──────────────────────────────────────────────────────
            const _SecTitle('Key Metrics'),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.6,
              children: [
                _KpiCard(
                  label: 'Total Users',
                  value: '${stats.totalUsers}',
                  icon: Icons.people_outline,
                  color: AppColors.primary,
                ),
                _KpiCard(
                  label: 'Total Sessions',
                  value: '${stats.totalSessions}',
                  icon: Icons.mic_outlined,
                  color: AppColors.happy,
                ),
                _KpiCard(
                  label: 'Total Minutes',
                  value: '${stats.totalMinutes}',
                  icon: Icons.timer_outlined,
                  color: AppColors.sad,
                ),
                _KpiCard(
                  label: 'Active Today',
                  value: '${stats.activeToday}',
                  icon: Icons.today_outlined,
                  color: AppColors.neutral,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Emotion Distribution ───────────────────────────────────────────
            const _SecTitle('Emotion Distribution'),
            const SizedBox(height: 12),
            _Card(
              child: _emotionDist.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No data yet',
                          style: TextStyle(color: AppColors.onSurface),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: 230,
                          child: PieChart(
                            PieChartData(
                              sections: _emotionDist.entries.map((e) {
                                return PieChartSectionData(
                                  color: AppColors.forEmotion(e.key),
                                  value: e.value,
                                  title: '${e.value.toStringAsFixed(0)}%',
                                  radius: 68,
                                  titleStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                );
                              }).toList(),
                              centerSpaceRadius: 46,
                              sectionsSpace: 2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _emotionDist.entries
                              .map(
                                (e) => _LegendDot(
                                  label:
                                      '${e.key}  ${e.value.toStringAsFixed(0)}%',
                                  color: AppColors.forEmotion(e.key),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
            ),
            const SizedBox(height: 24),

            // ── Sessions This Week ─────────────────────────────────────────────
            const _SecTitle('Sessions This Week'),
            const SizedBox(height: 12),
            _Card(
              child: SizedBox(
                height: 165,
                child: BarChart(
                  BarChartData(
                    maxY:
                        (_weeklySessionCounts.fold<double>(
                                  0,
                                  (a, b) => a > b ? a : b,
                                ) *
                                1.2)
                            .clamp(10, 1000)
                            .ceilToDouble(),
                    barGroups: List.generate(
                      7,
                      (i) => BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: _weeklySessionCounts[i],
                            color: AppColors.primary,
                            width: 16,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, m) => Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              const [
                                'Mon',
                                'Tue',
                                'Wed',
                                'Thu',
                                'Fri',
                                'Sat',
                                'Sun',
                              ][v.toInt()],
                              style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                          reservedSize: 26,
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 25,
                      getDrawingHorizontalLine: (_) => const FlLine(
                        color: AppColors.divider,
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Emotion Trends ─────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _SecTitle('Emotion Trends'),
                Row(
                  children: ['7D', '30D']
                      .map(
                        (p) => _PeriodChip(
                          label: p,
                          active: _period == p,
                          onTap: () => setState(() => _period = p),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _Card(
              child: Column(
                children: [
                  SizedBox(
                    height: 175,
                    child: LineChart(_buildTrendData(_period)),
                  ),
                  const SizedBox(height: 10),
                  const Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      _LegendDot(label: 'Happy', color: AppColors.happy),
                      _LegendDot(label: 'Sad', color: AppColors.sad),
                      _LegendDot(label: 'Angry', color: AppColors.angry),
                      _LegendDot(label: 'Neutral', color: AppColors.neutral),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Peak Usage Hours ───────────────────────────────────────────────
            const _SecTitle('Peak Usage Hours'),
            const SizedBox(height: 12),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 150,
                    child: BarChart(() {
                      // 8 bars, each covering a 3-hour window.
                      const labels3h = [
                        '0-2',
                        '3-5',
                        '6-8',
                        '9-11',
                        '12-14',
                        '15-17',
                        '18-20',
                        '21-23',
                      ];
                      final peak = _peak3h;
                      final maxVal = peak.fold<double>(
                        0,
                        (a, b) => a > b ? a : b,
                      );
                      return BarChartData(
                        maxY: (maxVal * 1.2).clamp(5, 1000).ceilToDouble(),
                        barGroups: List.generate(
                          8,
                          (i) => BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: peak[i],
                                color: peak[i] >= maxVal * 0.6
                                    ? AppColors.primary
                                    : AppColors.primary.withValues(alpha: 0.4),
                                width: 26,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ],
                          ),
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 1,
                              getTitlesWidget: (v, m) {
                                final idx = v.toInt();
                                if (idx < 0 || idx >= labels3h.length) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    labels3h[idx],
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                );
                              },
                              reservedSize: 22,
                            ),
                          ),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                        ),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                      );
                    }()),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Trend chart data builder ───────────────────────────────────────────────
  LineChartData _buildTrendData(String period) {
    final is7d = period == '7D';
    final happy = is7d ? _happyTrend7D : _happyTrend30D;
    final sad = is7d ? _sadTrend7D : _sadTrend30D;
    final angry = is7d ? _angryTrend7D : _angryTrend30D;
    final neutral = is7d ? _neutralTrend7D : _neutralTrend30D;
    final labels = is7d
        ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        : const ['Week 1', 'Week 2', 'Week 3', 'Week 4'];

    if (happy.isEmpty) {
      return LineChartData(lineBarsData: []);
    }

    final allValues = [...happy, ...sad, ...angry, ...neutral];
    final maxY = allValues.fold<double>(0, (a, b) => a > b ? a : b);

    LineChartBarData lineBar(List<double> data, Color color) =>
        LineChartBarData(
          spots: List.generate(
            data.length,
            (i) => FlSpot(i.toDouble(), data[i]),
          ),
          color: color,
          isCurved: true,
          barWidth: 2.5,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: color.withValues(alpha: 0.07),
          ),
        );

    return LineChartData(
      lineBarsData: [
        lineBar(happy, AppColors.happy),
        lineBar(sad, AppColors.sad),
        lineBar(angry, AppColors.angry),
        lineBar(neutral, AppColors.neutral),
      ],
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            getTitlesWidget: (v, m) {
              final idx = v.toInt();
              if (idx < 0 || idx >= labels.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  labels[idx],
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.onSurface,
                  ),
                ),
              );
            },
            reservedSize: 20,
          ),
        ),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: (maxY / 4).ceilToDouble().clamp(1, 100),
        getDrawingHorizontalLine: (_) =>
            const FlLine(color: AppColors.divider, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      minX: 0,
      maxX: (happy.length - 1).toDouble(),
      minY: 0,
      maxY: (maxY * 1.2).ceilToDouble().clamp(5, 1000),
    );
  }
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

class _SecTitle extends StatelessWidget {
  const _SecTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.divider),
    ),
    child: child,
  );
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.onSurface),
      ),
    ],
  );
}

// ─── Hero stat used in overview hero card ─────────────────────────────────────
class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? AppColors.primary : AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? AppColors.primary : AppColors.divider,
        ),
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
