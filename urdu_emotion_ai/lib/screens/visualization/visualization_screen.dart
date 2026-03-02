import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/audio_storage_service.dart';

// ─── Data model ───────────────────────────────────────────────────────────────
enum AudioInputMethod { live, upload }

class VisualizationData {
  final String emotion;
  final double confidence;
  final Map<String, double> allScores;
  final String? recordingPath;
  final AudioInputMethod inputMethod;

  const VisualizationData({
    required this.emotion,
    required this.confidence,
    required this.allScores,
    this.recordingPath,
    this.inputMethod = AudioInputMethod.live,
  });

  static const List<String> knownEmotions = ['Happy', 'Sad', 'Angry', 'Neutral'];

  bool get canSaveRecording =>
      inputMethod == AudioInputMethod.live &&
      recordingPath != null &&
      recordingPath!.isNotEmpty;

  /// Ensures all 4 known emotion classes appear in [scores].
  /// Missing classes are inserted with 0 %.
  static Map<String, double> fillMissingEmotions(Map<String, double> scores) {
    final result = Map<String, double>.from(scores);
    for (final e in knownEmotions) {
      if (!result.keys.any((k) => k.toLowerCase() == e.toLowerCase())) {
        result[e] = 0.0;
      }
    }
    return result;
  }

  /// Caps the dominant emotion to ≤ 93 %, redistributes the remainder
  /// across the other classes randomly or proportionally, and ensures
  /// all 4 known classes are always present in the returned map.
  static Map<String, double> applyConfidenceCap(
    String? dominant,
    Map<String, double> scores,
  ) {
    final filled = fillMissingEmotions(scores);
    if (filled.isEmpty || dominant == null) return filled;

    final lowerDominant = dominant.toLowerCase();
    String? dominantKey;
    for (final key in filled.keys) {
      if (key.toLowerCase() == lowerDominant) {
        dominantKey = key;
        break;
      }
    }
    if (dominantKey == null) return filled;

    final dominantOriginal = filled[dominantKey] ?? 0.0;
    if (dominantOriginal <= 93.0) {
      return filled.map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(2))));
    }

    final rand = math.Random();
    final target = 85.0 + rand.nextDouble() * 7.0; // 85–92 %
    final otherKeys =
        filled.keys.where((k) => k != dominantKey).toList(growable: false);
    final result = <String, double>{};
    result[dominantKey] = double.parse(target.toStringAsFixed(2));

    if (otherKeys.isEmpty) return result;

    final remaining = 100.0 - target;
    final othersTotal =
        otherKeys.fold(0.0, (sum, k) => sum + (filled[k] ?? 0.0));

    double assigned = 0.0;
    if (othersTotal <= 0) {
      // All other classes are 0 %: distribute the remainder randomly.
      final weights = List<double>.generate(
        otherKeys.length,
        (_) => rand.nextDouble() + 0.1,
      );
      final weightSum = weights.fold<double>(0.0, (a, b) => a + b);
      for (int i = 0; i < otherKeys.length; i++) {
        final isLast = i == otherKeys.length - 1;
        double value;
        if (isLast) {
          value = remaining - assigned;
        } else {
          value = remaining * (weights[i] / weightSum);
          value = double.parse(value.toStringAsFixed(2));
          assigned += value;
        }
        result[otherKeys[i]] = double.parse(value.toStringAsFixed(2));
      }
    } else {
      // Distribute proportionally to existing scores.
      for (int i = 0; i < otherKeys.length; i++) {
        final key = otherKeys[i];
        final isLast = i == otherKeys.length - 1;
        double value;
        if (isLast) {
          value = remaining - assigned;
        } else {
          final weight = (filled[key] ?? 0.0) / othersTotal;
          value = remaining * weight;
          value = double.parse(value.toStringAsFixed(2));
          assigned += value;
        }
        result[key] = double.parse(value.toStringAsFixed(2));
      }
    }
    return result;
  }
}

// ─── Screen ───────────────────────────────────────────────────────────────────
class VisualizationScreen extends StatefulWidget {
  final VisualizationData? data;
  const VisualizationScreen({super.key, this.data});

  @override
  State<VisualizationScreen> createState() => _VisualizationScreenState();
}

class _VisualizationScreenState extends State<VisualizationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<double> _scaleAnim;
  late Animation<double> _slideAnim;

  // Confidence scores with the >93% cap applied (computed once in initState)
  late Map<String, double> _adjustedScores;
  bool _showAllScores = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _slideAnim = Tween<double>(
      begin: 40,
      end: 0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _adjustedScores = _applyConfidenceCap(
      widget.data?.emotion,
      widget.data?.allScores ?? {},
    );
    _controller.forward();
  }

  Map<String, double> _applyConfidenceCap(
    String? dominant,
    Map<String, double> scores,
  ) =>
      VisualizationData.applyConfidenceCap(dominant, scores);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _emojiFor(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return '😊';
      case 'sad':
        return '😢';
      case 'angry':
        return '😡';
      default:
        return '😐'; // neutral
    }
  }

  String _summaryFor(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return 'Your voice carries a positive and joyful energy. '
            'The model detected warmth and enthusiasm in your speech patterns, '
            'indicating an uplifted emotional state.';
      case 'sad':
        return 'Your speech patterns reflect a subdued emotional state. '
            'Slower tempo and lower energy levels in your voice suggest '
            'feelings of sadness or low mood.';
      case 'angry':
        return 'The analysis detected elevated intensity in your voice. '
            'Sharp tonal variations and increased speech energy indicate '
            'an agitated or angry emotional state.';
      default: // neutral
        return 'Your voice maintains a calm and composed tone. '
            'No dominant emotional markers were detected, your speech '
            'reflects a balanced, neutral state of mind.';
    }
  }

  Map<String, double> _fillMissingEmotions(Map<String, double> scores) =>
      VisualizationData.fillMissingEmotions(scores);

  // Dominant emotion first, rest sorted descending by score.
  List<MapEntry<String, double>> _orderedScores(
    String dominant,
    Map<String, double> scores,
  ) {
    // Always show all 4 emotions, even if backend didn't return them.
    final filled = _fillMissingEmotions(
      scores.isEmpty
          ? {dominant: widget.data?.confidence ?? 0}
          : scores,
    );
    final entries = filled.entries.toList()
      ..sort((a, b) {
        if (a.key.toLowerCase() == dominant.toLowerCase()) return -1;
        if (b.key.toLowerCase() == dominant.toLowerCase()) return 1;
        return b.value.compareTo(a.value);
      });
    return entries;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final emotion = data?.emotion ?? 'Neutral';
    final color = AppColors.forEmotion(emotion);
    final scores = _orderedScores(emotion, _adjustedScores);
    final dominantConfidence =
        scores.isNotEmpty ? scores.first.value : (data?.confidence ?? 0);
    final summary = _summaryFor(emotion);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis Result'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.go('/record'),
        ),
        actions: [
          if (data?.canSaveRecording == true)
            IconButton(
              tooltip: 'Save recording',
              icon: const Icon(Icons.save_outlined),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Save Recording?'),
                    content: const Text(
                      'Save this audio file to your phone\'s Downloads folder?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                if (confirm != true || !context.mounted) return;
                final path = data!.recordingPath!;
                final ok = await AudioStorageService.instance.saveToDownloads(
                  sourcePath: path,
                  mimeType: 'audio/wav',
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? 'Audio saved to Downloads.' : 'Could not save recording.',
                    ),
                    backgroundColor: ok ? AppColors.primary : AppColors.angry,
                  ),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Dominant emotion circle ──────────────────────────────
                    Transform.translate(
                      offset: Offset(0, _slideAnim.value),
                      child: ScaleTransition(
                        scale: _scaleAnim,
                        child: Center(
                          child: Column(
                            children: [
                              Container(
                                width: 150,
                                height: 150,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: color, width: 2.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.35),
                                      blurRadius: 32,
                                      spreadRadius: 6,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    _emojiFor(emotion),
                                    style: const TextStyle(fontSize: 64),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                emotion.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                  letterSpacing: 4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Dominant Emotion Detected',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: AppColors.onSurface),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Bar chart ────────────────────────────────────────────
                    const _SectionTitle(title: 'Confidence Distribution'),
                    const SizedBox(height: 6),
                    if (data != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Detected "$emotion" with ${dominantConfidence.toStringAsFixed(1)}% confidence',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.onSurface,
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    _Card(
                      child: SizedBox(
                        height: 210,
                        child: _ConfidenceBarChart(
                          scores: scores,
                          dominant: emotion,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Confidence scores ────────────────────────────────────
                    const _SectionTitle(title: 'Confidence Scores'),
                    const SizedBox(height: 12),
                    _Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InkWell(
                            onTap: () => setState(
                              () => _showAllScores = !_showAllScores,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _showAllScores
                                      ? 'All emotions'
                                      : 'Predicted emotion only',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _showAllScores
                                        ? AppColors.forEmotion(emotion)
                                        : AppColors.onSurface,
                                  ),
                                ),
                                Icon(
                                  _showAllScores
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: _showAllScores
                                      ? AppColors.forEmotion(emotion)
                                      : AppColors.onSurface,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...(() {
                            if (scores.isEmpty) return <Widget>[];
                            final visibleScores =
                                _showAllScores ? scores : [scores.first];
                            return visibleScores.asMap().entries.map((entry) {
                              final i = entry.key;
                              final e = entry.value;
                            final barColor = AppColors.forEmotion(e.key);
                            final pct = e.value.clamp(0.0, 100.0);
                              final isLast = i == visibleScores.length - 1;
                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: isLast ? 0 : 14,
                                ),
                                child: _AnimatedEmotionBar(
                                  label: e.key,
                                  percent: pct,
                                  color: barColor,
                                  isDominant: e.key.toLowerCase() ==
                                      emotion.toLowerCase(),
                                  delay:
                                      Duration(milliseconds: 200 + i * 90),
                                ),
                              );
                            }).toList();
                          })(),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── AI Summary ───────────────────────────────────────────
                    const _SectionTitle(title: 'AI Summary'),
                    const SizedBox(height: 12),
                    _Card(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.psychology_outlined,
                              color: color,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'What we interpreted',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: color,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  summary,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.onSurface,
                                    height: 1.55,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Record again ─────────────────────────────────────────
                    ElevatedButton.icon(
                      onPressed: () => context.go('/record'),
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text('Record Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Vertical bar chart for all emotion confidence scores ────────────────────
class _ConfidenceBarChart extends StatefulWidget {
  const _ConfidenceBarChart({required this.scores, required this.dominant});

  final List<MapEntry<String, double>> scores;
  final String dominant;

  @override
  State<_ConfidenceBarChart> createState() => _ConfidenceBarChartState();
}

class _ConfidenceBarChartState extends State<_ConfidenceBarChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    // Delay slightly so it starts after the page entrance animation
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.scores;

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        return BarChart(
          BarChartData(
            maxY: 100,
            barGroups: List.generate(entries.length, (i) {
              final e = entries[i];
              final color = AppColors.forEmotion(e.key);
              final isDominant =
                  e.key.toLowerCase() == widget.dominant.toLowerCase();
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: e.value * _anim.value,
                    color: isDominant ? color : color.withValues(alpha: 0.55),
                    width: 36,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                  ),
                ],
              );
            }),
            titlesData: FlTitlesData(
              topTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (value, _) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= entries.length) {
                      return const SizedBox.shrink();
                    }
                    final percent = entries[idx].value.clamp(0.0, 100.0);
                    return Text(
                      '${percent.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onSurface,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, _) {
                    final idx = value.toInt();
                    if (idx < 0 || idx >= entries.length) {
                      return const SizedBox.shrink();
                    }
                    final isDominant =
                        entries[idx].key.toLowerCase() ==
                        widget.dominant.toLowerCase();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        entries[idx].key,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isDominant
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: isDominant
                              ? AppColors.forEmotion(entries[idx].key)
                              : AppColors.onSurface,
                        ),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 25,
                  reservedSize: 34,
                  getTitlesWidget: (value, _) => Text(
                    '${value.toInt()}%',
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 25,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AppColors.divider, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, _, rod, _) {
                  final e = entries[group.x];
                  return BarTooltipItem(
                    '${e.key}\n${e.value.toStringAsFixed(1)}%',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Animated emotion bar ─────────────────────────────────────────────────────
class _AnimatedEmotionBar extends StatefulWidget {
  const _AnimatedEmotionBar({
    required this.label,
    required this.percent,
    required this.color,
    required this.isDominant,
    required this.delay,
  });

  final String label;
  final double percent;
  final Color color;
  final bool isDominant;
  final Duration delay;

  @override
  State<_AnimatedEmotionBar> createState() => _AnimatedEmotionBarState();
}

class _AnimatedEmotionBarState extends State<_AnimatedEmotionBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _widthAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _widthAnim = Tween<double>(
      begin: 0,
      end: widget.percent / 100,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Row(
            children: [
              if (widget.isDominant)
                Icon(Icons.arrow_right, size: 14, color: widget.color),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: widget.isDominant
                        ? FontWeight.w700
                        : FontWeight.normal,
                    color: widget.isDominant
                        ? widget.color
                        : AppColors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: AnimatedBuilder(
            animation: _widthAnim,
            builder: (context, _) => ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _widthAnim.value,
                minHeight: widget.isDominant ? 14 : 10,
                backgroundColor: widget.color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(widget.color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 46,
          child: Text(
            '${widget.percent.toStringAsFixed(1)}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: widget.isDominant ? 13 : 12,
              fontWeight: widget.isDominant
                  ? FontWeight.w700
                  : FontWeight.normal,
              color: widget.isDominant ? widget.color : AppColors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Section title ────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
  );
}

// ─── Card wrapper ─────────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.divider),
    ),
    child: child,
  );
}
