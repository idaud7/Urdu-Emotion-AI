import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

/// Data class passed via GoRouter extra.
class ResultData {
  final String emotion;
  final double confidence;

  const ResultData({required this.emotion, required this.confidence});
}

class ResultScreen extends StatefulWidget {
  final ResultData data;
  const ResultScreen({super.key, required this.data});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;
  late Animation<double> _progressAnim;
  late String _resultMessage;

  @override
  void initState() {
    super.initState();
    _resultMessage = _messageFor(widget.data.emotion);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.7, curve: Curves.easeIn),
      ),
    );
    _progressAnim = Tween<double>(begin: 0.0, end: widget.data.confidence / 100)
        .animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
    ));
    _controller.forward();
  }

  String _messageFor(String emotion) {
    final messages = _messages(emotion);
    return messages[Random().nextInt(messages.length)];
  }

  List<String> _messages(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return [
          'You are radiating positive energy! Your emotional well being is in a wonderful place right now.',
          'What a joyful result! Keep embracing life with this open and happy heart of yours.',
          'Happiness detected loud and clear! Your voice carries the warmth of someone who is truly thriving.',
          'This is a beautiful result. Let this joy fuel your relationships, your goals, and your daily moments.',
          'Your positivity is shining through. Celebrate this win and share your good energy with the people around you.',
          'A happy voice is a healthy voice. You are doing something right and it is really starting to show.',
          'This result is a reminder of how great life can feel. Hold onto this feeling and keep building on it.',
          'Your emotional state is glowing with brightness today. Keep doing what makes your heart feel this alive.',
          'Happiness is your current superpower. Use it to inspire, create, and connect with the world around you.',
          'The data confirms what your heart already knows. You are in a truly great emotional place today.',
        ];
      case 'sad':
        return [
          'It is completely okay to feel this way. Every emotion has its purpose and sadness reminds us of what truly matters.',
          'Your feelings are valid and you are not alone. Reach out to someone who cares and let yourself be supported today.',
          'Even on the hardest days, you showed up. That takes real courage and it is something to be genuinely proud of.',
          'Sadness is not a weakness. It is a sign that you care deeply and that is one of the most human things there is.',
          'This feeling will pass and when it does, you will feel the sunshine even more deeply. Be kind to yourself today.',
          'You are going through something tough but you are tougher than you know. Rest, breathe, and take it one step at a time.',
          'It takes strength to acknowledge how you feel. You are already doing something brave just by checking in with yourself.',
          'Give yourself permission to feel this fully. Processing your emotions is the first step toward healing and finding peace.',
          'Even the sky cries sometimes and then it clears. Your brightness is still there beneath these clouds, waiting to return.',
          'You are seen, you are valued, and you are going to be okay. Better days are already on their way to you.',
        ];
      case 'angry':
        return [
          'Anger is a powerful emotion and it is okay to feel it. Remember that you have the strength to channel this energy well.',
          'Your frustration is valid. Give yourself a moment to cool down and you will find the clarity to handle things with confidence.',
          'Even this feeling has a message. Once the heat fades, listen to what your anger is telling you and use that energy wisely.',
          'You are stronger than this moment of frustration. A few deep breaths can transform this energy into something constructive.',
          'It is okay to feel fired up. Channel that intensity into something positive like a workout, a journal entry, or a bold new idea.',
          'Anger often comes from caring about something deeply. Recognize what matters to you here and use that passion for good.',
          'Take this moment to pause and reset. The storm always passes and your calm, wise self is just a few breaths away.',
          'You handled this moment by checking in and that is already real progress. Being aware in tough moments is a sign of strength.',
          'Your feelings are powerful and real. Treat yourself with the same patience you would offer a good friend right now.',
          'This too shall pass and you will come out of it wiser and more grounded. You have navigated hard moments before.',
        ];
      case 'neutral':
        return [
          'Steady and composed. Your emotional balance is a genuine strength that serves you well in every area of life.',
          'A calm emotional state is the foundation of clear thinking and wise decisions. You are in a truly great place right now.',
          'Balanced is beautiful. This steadiness gives you the clarity to navigate life with patience, purpose, and quiet confidence.',
          'Your emotional groundedness is something to appreciate. A composed mind is well equipped to handle whatever comes next.',
          'Neutral is powerful. You are centered, clear headed, and ready to take on whatever the day decides to bring your way.',
          'Equilibrium detected. You have a strong emotional foundation that supports healthy growth and thoughtful action.',
          'There is a quiet confidence in this result. Your balanced state is a platform for making meaningful moves in your life.',
          'A steady emotional state means a steady life. You are building resilience simply by maintaining this sense of calm.',
          'Being centered is an underrated superpower. Your composure lets you respond to life thoughtfully rather than react impulsively.',
          'This result shows a mind at peace. Use this balanced moment to reflect, plan, and step toward something that inspires you.',
        ];
      default:
        return [
          'Every recording is a step toward deeper understanding of your emotional world. Keep checking in with yourself.',
          'Your voice holds more insight than you may realize. Regular sessions will reveal powerful patterns over time.',
          'Showing up for yourself like this takes intention. Each session brings you closer to true emotional clarity.',
          'Emotional awareness starts with moments exactly like this one. You are building something meaningful session by session.',
          'The journey toward understanding your emotions is one of the most worthwhile things you can invest in.',
          'You are learning to listen to yourself in a deeper way. That is a truly powerful and life changing habit to build.',
          'Each check in is data that helps paint a fuller picture of your emotional patterns and overall well being.',
          'Progress is built one session at a time. Keep going and the insights will continue to grow more meaningful.',
          'You took the time to check in with yourself today and that matters more than you might think right now.',
          'Consistency is where the real insights live. Keep recording and watch as the picture of your emotions becomes clearer.',
        ];
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _emojiFor(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return '😊';
      case 'sad':
        return '😢';
      case 'angry':
        return '😡';
      case 'neutral':
        return '😐';
      default:
        return '🎭';
    }
  }

  @override
  Widget build(BuildContext context) {
    final emotion = widget.data.emotion;
    final confidence = widget.data.confidence;
    final color = AppColors.forEmotion(emotion);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/record'),
        ),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // ── Emoji ──
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Text(
                      _emojiFor(emotion),
                      style: const TextStyle(fontSize: 80),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Emotion label ──
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: Text(
                      emotion.toUpperCase(),
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: 4,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ── Confidence ring ──
                  SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Background ring
                        SizedBox(
                          width: 160,
                          height: 160,
                          child: CircularProgressIndicator(
                            value: 1.0,
                            strokeWidth: 10,
                            color: color.withValues(alpha: 0.15),
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                        // Animated progress ring
                        SizedBox(
                          width: 160,
                          height: 160,
                          child: CircularProgressIndicator(
                            value: _progressAnim.value,
                            strokeWidth: 10,
                            color: color,
                            strokeCap: StrokeCap.round,
                          ),
                        ),
                        // Percentage text
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${(_progressAnim.value * 100).toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Confidence',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // ── Glassmorphic detail card ──
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: color.withValues(alpha: 0.3),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.08),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _DetailRow(
                            icon: Icons.psychology_outlined,
                            label: 'Detected Emotion',
                            value: emotion,
                            color: color,
                          ),
                          const SizedBox(height: 12),
                          Divider(color: AppColors.divider.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          _DetailRow(
                            icon: Icons.speed_outlined,
                            label: 'Confidence Score',
                            value: '${confidence.toStringAsFixed(2)}%',
                            color: color,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── Contextual message ──
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: Text(
                      _resultMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.onSurface.withValues(alpha: 0.85),
                        height: 1.55,
                      ),
                    ),
                  ),

                  const Spacer(flex: 2),

                  // ── Record again button ──
                  FadeTransition(
                    opacity: _fadeAnim,
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => context.go('/record'),
                        icon: const Icon(Icons.mic_rounded),
                        label: const Text('Record Again'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.onSurface.withValues(alpha: 0.7),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
