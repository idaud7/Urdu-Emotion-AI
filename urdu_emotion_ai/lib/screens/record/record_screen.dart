import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/api_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/firestore_service.dart';
import '../../core/services/audio_storage_service.dart';
import '../visualization/visualization_screen.dart';

// ─── State enum ───────────────────────────────────────────────────────────────
enum RecordState { idle, readyToRecord, recording, stopped, analysing }

// ─── Screen ───────────────────────────────────────────────────────────────────
class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with SingleTickerProviderStateMixin {
  // Recording
  final AudioRecorder _recorder = AudioRecorder();
  RecordState _state = RecordState.idle;
  String? _recordingPath;
  bool _isStarting = false; // guard against double-tap
  AudioInputMethod _inputMethod = AudioInputMethod.live;

  // Playback
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _playPosition = Duration.zero;
  Duration _playDuration = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  // Timer
  Duration _duration = Duration.zero;
  Timer? _timer;

  // Static waveform — decoded from file after recording stops
  List<double> _waveformBars = [];

  // Stop button pulse animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // User's detection sensitivity threshold (0.0–1.0, default 0.5)
  double _sensitivityThreshold = 0.5;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _loadSensitivity();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.14).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _positionSub = _player.positionStream.listen((pos) {
      if (mounted) setState(() => _playPosition = pos);
    });
    _playerStateSub = _player.playerStateStream.listen((ps) {
      if (mounted) {
        setState(() {
          _isPlaying = ps.playing;
          if (ps.processingState == ProcessingState.completed) {
            _isPlaying = false;
            _player.seek(Duration.zero);
            _player.pause();
          }
        });
      }
    });
  }

  Future<void> _loadSensitivity() async {
    final uid = AuthService.instance.firebaseUser?.uid;
    if (uid == null) return;
    try {
      final profile = await FirestoreService.instance.getUserProfile(uid);
      if (mounted && profile?.sensitivityThreshold != null) {
        setState(() => _sensitivityThreshold = profile!.sensitivityThreshold!.clamp(0.0, 1.0));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _pulseController.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────
  void _goToReadyToRecord() =>
      setState(() => _state = RecordState.readyToRecord);

  void _goBackToIdle() {
    if (_state == RecordState.readyToRecord) {
      setState(() => _state = RecordState.idle);
    } else if (_state == RecordState.stopped) {
      _discardRecording();
    }
  }

  // ── Recording ──────────────────────────────────────────────────────────────
  Future<void> _beginRecording() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);

    try {
      await _player.stop();

      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (mounted) {
          _showSnack(
            'Microphone permission is required to record.',
            AppColors.angry,
          );
        }
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/recordings');
      if (!folder.existsSync()) folder.createSync();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${folder.path}/recording_$timestamp.wav';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );

      if (!mounted) return;
      setState(() {
        _state = RecordState.recording;
        _isStarting = false;
        _duration = Duration.zero;
        _recordingPath = path;
        _inputMethod = AudioInputMethod.live;
      });

      _pulseController.repeat(reverse: true);

      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _state != RecordState.recording) return;
        setState(() => _duration += const Duration(seconds: 1));
        if (_duration.inSeconds >= _maxDurationSeconds) {
          _stopRecording();
          _showSnack(
            'Maximum recording length (59s) reached.',
            AppColors.primary,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isStarting = false);
        _showSnack('Could not start recording: $e', AppColors.angry);
      }
    }
  }

  // ── Waveform extraction ────────────────────────────────────────────────────
  // Parses a 16-bit PCM WAV file and returns normalised RMS amplitude per bar.
  Future<List<double>> _computeWaveform(
    String filePath, {
    int numBars = 60,
  }) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      if (bytes.length < 44) return List.filled(numBars, 0.05);

      // Locate the 'data' chunk (robustly, in case there are extra chunks)
      int dataOffset = 44;
      for (int i = 12; i < bytes.length - 8; i++) {
        if (bytes[i] == 0x64 &&
            bytes[i + 1] == 0x61 &&
            bytes[i + 2] == 0x74 &&
            bytes[i + 3] == 0x61) {
          dataOffset = i + 8; // skip 'data' tag + 4-byte size field
          break;
        }
      }
      if (dataOffset >= bytes.length) return List.filled(numBars, 0.05);

      // 16-bit little-endian mono PCM
      final numSamples = (bytes.length - dataOffset) ~/ 2;
      if (numSamples < numBars) return List.filled(numBars, 0.05);

      final samplesPerBar = numSamples ~/ numBars;
      final rms = List<double>.filled(numBars, 0);
      double maxRms = 0.001;

      for (int i = 0; i < numBars; i++) {
        double sumSq = 0;
        for (int j = 0; j < samplesPerBar; j++) {
          final idx = dataOffset + (i * samplesPerBar + j) * 2;
          if (idx + 1 >= bytes.length) break;
          int s = bytes[idx] | (bytes[idx + 1] << 8);
          if (s > 32767) s -= 65536; // convert to signed
          final norm = s / 32768.0;
          sumSq += norm * norm;
        }
        rms[i] = math.sqrt(sumSq / samplesPerBar);
        if (rms[i] > maxRms) maxRms = rms[i];
      }

      return rms.map((v) => (v / maxRms).clamp(0.04, 1.0)).toList();
    } catch (_) {
      return List.filled(numBars, 0.05);
    }
  }

  double get _playProgressValue {
    final total = _playDuration.inMilliseconds;
    if (total == 0) return 0.0;
    return (_playPosition.inMilliseconds / total).clamp(0.0, 1.0);
  }

  // ── Audio validation (duration + non-empty + non-silent) ───────────────────
  static const int _minDurationSeconds = 3;
  static const int _maxDurationSeconds = 59;
  static const int _minAudioBytes = 1024; // guard against empty/invalid files

  Future<bool> _isSilentOrNoiseWav(
    String filePath, {
    double p95Min = 0.015,
    double variationRatioMin = 1.35,
  }) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      if (bytes.length < 44) return true;

      // Find the 'data' chunk and its size.
      int dataOffset = -1;
      int dataSize = 0;
      for (int i = 12; i < bytes.length - 8; i++) {
        if (bytes[i] == 0x64 &&
            bytes[i + 1] == 0x61 &&
            bytes[i + 2] == 0x74 &&
            bytes[i + 3] == 0x61) {
          dataSize = bytes[i + 4] |
              (bytes[i + 5] << 8) |
              (bytes[i + 6] << 16) |
              (bytes[i + 7] << 24);
          dataOffset = i + 8;
          break;
        }
      }
      if (dataOffset < 0) return true;
      if (dataSize <= 0) return true;

      final available = bytes.length - dataOffset;
      final usable = math.min<int>(available, dataSize);
      final numSamples = usable ~/ 2;
      if (numSamples < 200) return true;

      // Frame-wise RMS gives a better signal for "voice present" than global RMS.
      // Voice typically has noticeable energy spikes/variation compared to constant noise.
      const frameSamples = 480; // 30ms at 16kHz
      final hopSamples = frameSamples; // non-overlapping for speed
      final frames = <double>[];
      double maxAbs = 0.0;

      // Limit frames for performance on long files.
      final maxFrames = math.min<int>(500, (numSamples / hopSamples).floor());
      for (int f = 0; f < maxFrames; f++) {
        final start = f * hopSamples;
        double sumSq = 0.0;
        int used = 0;
        for (int i = 0; i < frameSamples; i++) {
          final s = start + i;
          if (s >= numSamples) break;
          final idx = dataOffset + s * 2;
          if (idx + 1 >= bytes.length) break;
          int v = bytes[idx] | (bytes[idx + 1] << 8);
          if (v > 32767) v -= 65536;
          final norm = v / 32768.0;
          final absN = norm.abs();
          if (absN > maxAbs) maxAbs = absN;
          sumSq += norm * norm;
          used++;
        }
        if (used == 0) break;
        frames.add(math.sqrt(sumSq / used));
      }

      if (frames.isEmpty) return true;
      frames.sort();

      double percentile(List<double> sorted, double p) {
        if (sorted.isEmpty) return 0.0;
        final idx = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
        return sorted[idx];
      }

      final p50 = percentile(frames, 0.50);
      final p95 = percentile(frames, 0.95);

      // If there's basically no signal energy (or clipped-to-zero), treat as silent.
      if (p95 < p95Min || maxAbs < 0.03) return true;

      // Constant waveform / steady noise: high median but low variation.
      final ratio = p50 <= 0.0001 ? 999.0 : (p95 / p50);
      if (ratio < variationRatioMin && p95 < 0.06) return true;

      return false;
    } catch (_) {
      // If we can't parse it reliably, don't block analysis here.
      return false;
    }
  }

  Future<String?> _validateAudioForAnalysis(String filePath) async {
    if (filePath.trim().isEmpty) {
      return 'No audio found. Please record again.';
    }

    final f = File(filePath);
    final exists = await f.exists();
    if (!exists) {
      return 'Audio file was not found. Please record again.';
    }

    final length = await f.length();
    if (length < _minAudioBytes) {
      return 'Recording is empty. Please record more than 3 seconds.';
    }

    final durationSeconds = _playDuration.inSeconds;
    if (durationSeconds < _minDurationSeconds) {
      return 'Please record more than 3 seconds.';
    }
    if (durationSeconds > _maxDurationSeconds) {
      return 'Recording must be 59 seconds or less.';
    }

    final lower = filePath.toLowerCase();
    if (lower.endsWith('.wav')) {
      final silentOrNoise = await _isSilentOrNoiseWav(filePath);
      if (silentOrNoise) {
        return 'No voice detected (recording is silent or only background noise). '
            'Please record again with more than 3 seconds of audible speech.';
      }
    }

    return null;
  }

  Future<void> _stopRecording() async {
    // Cancel immediately to prevent extra timer ticks incrementing _duration.
    _timer?.cancel();
    _pulseController.stop();
    _pulseController.reset();

    // Capture duration BEFORE any await so the timer can't race.
    final recordedDuration = _duration;

    await _recorder.stop();

    if (_recordingPath != null) {
      try {
        // Load file for playback only; ignore returned duration — WAV headers
        // are sometimes not yet finalised and just_audio can return a stale
        // or wrong value. The timer-tracked duration is always accurate.
        await _player.setFilePath(_recordingPath!);
        if (mounted) setState(() => _playDuration = recordedDuration);
      } catch (e) {
        debugPrint('Error loading audio for playback: $e');
      }

      // Decode WAV → static waveform bars
      final bars = await _computeWaveform(_recordingPath!);
      if (mounted) setState(() => _waveformBars = bars);
    }

    if (mounted) {
      setState(() {
        _state = RecordState.stopped;
        _playPosition = Duration.zero;
      });
    }
  }

  // ── Playback ───────────────────────────────────────────────────────────────
  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  void _discardRecording() {
    _player.stop();
    if (_recordingPath != null) {
      final file = File(_recordingPath!);
      if (file.existsSync()) file.deleteSync();
    }
    setState(() {
      _state = RecordState.idle;
      _recordingPath = null;
      _duration = Duration.zero;
      _playPosition = Duration.zero;
      _playDuration = Duration.zero;
      _waveformBars = [];
      _inputMethod = AudioInputMethod.live;
    });
  }

  // ── Analyse ────────────────────────────────────────────────────────────────
  Future<void> _analyseEmotion(String filePath) async {
    final err = await _validateAudioForAnalysis(filePath);
    if (err != null) {
      _showSnack(err, AppColors.angry);
      return;
    }

    await _player.stop();
    setState(() => _state = RecordState.analysing);

    try {
      final result = await ApiService.instance.predictEmotion(filePath);
      if (mounted) {
        final emotion = result['emotion'] as String;
        final confidence = (result['confidence'] as num).toDouble();

        // Apply user's sensitivity threshold.
        // Higher sensitivity = accepts lower confidence (more lenient).
        // Lower sensitivity = requires higher confidence (stricter).
        // Floor is 25% because with 4 classes summing to ~100%, 25% is the
        // random-chance baseline — anything below that is meaningless.
        // Scale: 0% sensitivity → 85% min, 100% sensitivity → 25% min.
        final minConfidence = 25.0 + (1.0 - _sensitivityThreshold) * 60.0;
        if (confidence < minConfidence) {
          setState(() => _state = RecordState.stopped);
          _showSnack(
            'Confidence too low (${confidence.toStringAsFixed(0)}%). '
            'Lower your sensitivity or record again more clearly.',
            AppColors.angry,
          );
          return;
        }

        // Backend may or may not return per-class scores (for all emotions).
        final rawScores = result['all_scores'] as Map<String, dynamic>? ?? {};
        Map<String, double> allScores;

        // Helper: redistribute remaining % randomly across other emotion classes.
        Map<String, double> redistribute(String dominantEmotion, double dominantPct) {
          const emotionClasses = ['Happy', 'Sad', 'Angry', 'Neutral'];
          final dominantLower = dominantEmotion.toLowerCase();
          final otherClasses = emotionClasses
              .where((e) => e.toLowerCase() != dominantLower)
              .toList();

          final capped = dominantPct.clamp(0.0, 100.0);
          final remaining = (100.0 - capped).clamp(0.0, 100.0);
          final result = <String, double>{
            dominantEmotion: double.parse(capped.toStringAsFixed(2)),
          };

          if (otherClasses.isNotEmpty) {
            if (remaining > 0) {
              final rand = math.Random();
              final weights = List<double>.generate(
                otherClasses.length,
                (_) => rand.nextDouble(),
              );
              final weightSum = weights
                  .fold<double>(0.0, (a, b) => a + b)
                  .clamp(0.0001, 1e9);

              double assigned = 0.0;
              for (int i = 0; i < otherClasses.length; i++) {
                final isLast = i == otherClasses.length - 1;
                double value;
                if (isLast) {
                  value = remaining - assigned;
                } else {
                  value = remaining * (weights[i] / weightSum);
                  value = double.parse(value.toStringAsFixed(2));
                  assigned += value;
                }
                result[otherClasses[i]] =
                    double.parse(value.toStringAsFixed(2));
              }
            } else {
              // remaining is 0 (100 % confidence from backend): add other
              // classes with 0 so that applyConfidenceCap can redistribute
              // the surplus to them when it caps the dominant emotion.
              for (final cls in otherClasses) {
                result[cls] = 0.0;
              }
            }
          }
          return result;
        }

        // Use backend scores only when ALL other-emotion scores are meaningful
        // (≥ 1 %). When the model is very confident the softmax pushes every
        // other class close to 0 %, making the chart useless. In that case we
        // redistribute the remaining percentage so the chart stays readable.
        final hasAllClasses =
            rawScores.isNotEmpty && rawScores.length >= 4;
        final otherScoresAreMeaningful = hasAllClasses &&
            rawScores.entries
                .where((e) => e.key.toLowerCase() != emotion.toLowerCase())
                .any((e) => (e.value as num).toDouble() >= 1.0);

        if (otherScoresAreMeaningful) {
          allScores = rawScores.map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          );
        } else {
          // Either the backend didn't return all classes, or the model was so
          // confident that every other class rounded to 0 %. Redistribute the
          // remaining percentage randomly for a meaningful visualisation.
          allScores = redistribute(emotion, confidence);
        }

        // Apply confidence cap BEFORE storing or displaying so every page
        // (analytics, profile, admin, visualization) shows the same value.
        final adjustedScores =
            VisualizationData.applyConfidenceCap(emotion, allScores);
        final lowerEmotion = emotion.toLowerCase();
        final adjustedConfidence = adjustedScores.entries
            .firstWhere(
              (e) => e.key.toLowerCase() == lowerEmotion,
              orElse: () => MapEntry(emotion, confidence),
            )
            .value;

        // Save session to Firestore so analytics, profile and admin
        // views all reflect real user activity.
        final user = AuthService.instance.firebaseUser;
        if (user != null) {
          await FirestoreService.instance.saveSession(
            uid: user.uid,
            emotion: emotion,
            confidence: adjustedConfidence,
            allScores: adjustedScores,
            duration: _duration,
            source: 'live',
          );
        }

        if (mounted) {
          context.go(
            '/visualization',
            extra: VisualizationData(
              emotion: emotion,
              confidence: adjustedConfidence,
              allScores: adjustedScores,
              recordingPath: _inputMethod == AudioInputMethod.live ? filePath : null,
              inputMethod: _inputMethod,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _state = _recordingPath != null
              ? RecordState.stopped
              : RecordState.idle,
        );
        _showSnack('Analysis failed: $e', AppColors.angry);
      }
    }
  }

  // ── Upload ─────────────────────────────────────────────────────────────────
  static final _audioPicker = MethodChannel(
    'com.example.urdu_emotion_ai/audio_picker',
  );

  Future<void> _pickAndAnalyse() async {
    String? filePath;

    if (Platform.isAndroid) {
      // Use native ACTION_GET_CONTENT so the phone's Files/Music app opens
      // directly instead of the document picker starting on an empty "Recent".
      try {
        filePath = await _audioPicker.invokeMethod<String>('pickAudioFile');
      } on PlatformException catch (e) {
        _showSnack('Could not open file picker: ${e.message}', AppColors.angry);
        return;
      }
    } else {
      // iOS / desktop — restrict picker to wav/mp3 directly
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3'],
      );
      filePath = result?.files.single.path;
    }

    if (filePath == null) return;

    // Validate extension — catches any format slipping through the Android picker.
    final ext = filePath.split('.').last.toLowerCase();
    if (ext != 'wav' && ext != 'mp3') {
      _showSnack(
        'Only .wav and .mp3 files are supported.',
        AppColors.angry,
      );
      return;
    }

    // Load into player so the user can preview before analysing.
    try {
      final audioDuration = await _player.setFilePath(filePath);
      if (audioDuration != null &&
          audioDuration.inSeconds > _maxDurationSeconds) {
        if (mounted) {
          _showSnack(
            'Audio file must be 59 seconds or less.',
            AppColors.angry,
          );
        }
        return;
      }
      final bars = await _computeWaveform(filePath);
      if (mounted) {
        setState(() {
          _recordingPath = filePath;
          _playDuration = audioDuration ?? Duration.zero;
          _duration = audioDuration ?? Duration.zero;
          _playPosition = Duration.zero;
          _waveformBars = bars;
          _state = RecordState.stopped;
          _inputMethod = AudioInputMethod.upload;
        });
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Could not load audio file: $e', AppColors.angry);
      }
    }
  }

  // ── Save sheet ─────────────────────────────────────────────────────────────
  void _showSaveSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _SaveSheet(
        recordingPath: _recordingPath!,
        duration: _duration,
        onSavedToPhone: () async {
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
          if (confirm != true || !mounted) return;
          Navigator.pop(context); // close the sheet
          final ok = await AudioStorageService.instance.saveToDownloads(
            sourcePath: _recordingPath!,
            mimeType: 'audio/wav',
          );
          _showSnack(
            ok ? 'Audio saved to Downloads.' : 'Could not save recording.',
            ok ? AppColors.primary : AppColors.angry,
          );
          if (ok) _discardRecording();
        },
        onDiscard: () {
          Navigator.pop(context);
          _discardRecording();
        },
      ),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final showBack =
        _state == RecordState.readyToRecord || _state == RecordState.stopped;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record'),
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: _goBackToIdle,
              )
            : null,
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
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(_state),
        child: switch (_state) {
          RecordState.idle => _buildIdleView(context),
          RecordState.readyToRecord => _buildReadyView(context),
          RecordState.recording => _buildRecordingView(context),
          RecordState.stopped => _buildStoppedView(context),
          RecordState.analysing => _buildAnalysingView(),
        },
      ),
    );
  }

  // ── Idle view ──────────────────────────────────────────────────────────────
  Widget _buildIdleView(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        children: [
          const Spacer(),

          // ── Decorative icon ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.graphic_eq_rounded,
              size: 60,
              color: AppColors.primary,
            ),
          ),

          // Icon → heading
          // Waveform → helper text
          const SizedBox(height: 28),

          // ── Heading + subtitle ───────────────────────────────────────────
          Text(
            'How are you feeling today?',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          // Heading → subtitle
          const SizedBox(height: 20),
          Text(
            'Speak naturally - our AI analyses your voice\nto detect emotion in real time.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),

          // Subtitle → emotion chips
          const SizedBox(height: 28),

          // ── Emotion capability chips ──────────────────────────────────────
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: const [
              _EmotionTag(emoji: '', label: 'Happy', color: AppColors.happy),
              _EmotionTag(emoji: '', label: 'Sad', color: AppColors.sad),
              _EmotionTag(emoji: '', label: 'Angry', color: AppColors.angry),
              _EmotionTag(
                emoji: '',
                label: 'Neutral',
                color: AppColors.neutral,
              ),
            ],
          ),

          // Chips → mode cards
          const SizedBox(height: 44),

          // ── Mode selection cards ──────────────────────────────────────────
          // Mode cards row (positioned slightly lower)
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      icon: Icons.mic_rounded,
                      label: 'Record Live',
                      color: AppColors.primary,
                      onTap: _goToReadyToRecord,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _ModeCard(
                      icon: Icons.upload_file_rounded,
                      label: 'Upload File',
                  color: AppColors.primary,
                      onTap: _pickAndAnalyse,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),

          const Spacer(flex: 2),
        ],
      ),
    );
  }

  // ── Ready-to-record view: mic centred with decorative rings ───────────────
  Widget _buildReadyView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Concentric rings + mic button ──────────────────────────────────
          Stack(
            alignment: Alignment.center,
            children: [
              // Outermost faint ring
              Container(
                width: 224,
                height: 224,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    width: 1.5,
                  ),
                ),
              ),
              // Middle ring
              Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.16),
                    width: 1.5,
                  ),
                ),
              ),
              // Inner filled glow ring
              Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.07),
                ),
              ),
              // Mic button
              GestureDetector(
                onTap: _isStarting ? null : _beginRecording,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: _isStarting
                        ? AppColors.primaryLight
                        : AppColors.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.45),
                        blurRadius: 40,
                        spreadRadius: 12,
                      ),
                    ],
                  ),
                  child: _isStarting
                      ? const Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : const Icon(
                          Icons.mic_rounded,
                          size: 58,
                          color: Colors.white,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            _isStarting ? 'Starting…' : 'Tap the mic to begin',
            style: const TextStyle(color: AppColors.onSurface, fontSize: 15),
          ),
        ],
      ),
    );
  }

  // ── Recording view ─────────────────────────────────────────────────────────
  Widget _buildRecordingView(BuildContext context) {
    // Stack layout: status chip pinned top-centre, stop button group centred
    // at the exact same Y position as the ready-to-record mic button.
    return Stack(
      children: [
        // Status chip pinned at the top
        Positioned(
          top: 24,
          left: 0,
          right: 0,
          child: Center(child: _StatusChip(state: _state)),
        ),
        // Timer + stop button centred on the screen
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmt(_duration),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w300,
                  letterSpacing: 8,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 36),
              // Stop button with animated pulsing rings
              AnimatedBuilder(
                animation: _pulseAnim,
                builder: (_, _) {
                  // t: 0.0 (resting) → 1.0 (fully expanded)
                  final t = (_pulseAnim.value - 1.0) / 0.14;
                  return SizedBox(
                    width: 250,
                    height: 250,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer pulsing ring — expands & fades as pulse grows
                        Container(
                          width: 130 + t * 70,
                          height: 130 + t * 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.angry.withValues(
                                alpha: 0.45 * (1 - t),
                              ),
                              width: 1.5,
                            ),
                          ),
                        ),
                        // Inner pulsing glow — softer fill
                        Container(
                          width: 130 + t * 38,
                          height: 130 + t * 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.angry.withValues(
                              alpha: 0.12 * (1 - t),
                            ),
                          ),
                        ),
                        // Stop button (scales with pulse)
                        Transform.scale(
                          scale: _pulseAnim.value,
                          child: GestureDetector(
                            onTap: _stopRecording,
                            child: Container(
                              width: 130,
                              height: 130,
                              decoration: BoxDecoration(
                                color: AppColors.angry,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.angry.withValues(
                                      alpha: 0.45,
                                    ),
                                    blurRadius: 40,
                                    spreadRadius: 12,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.stop_rounded,
                                size: 58,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),
              Text(
                'Tap to stop',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Stopped view ───────────────────────────────────────────────────────────
  Widget _buildStoppedView(BuildContext context) {
    final displayBars = _waveformBars.isNotEmpty
        ? _waveformBars
        : List.filled(60, 0.05);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _StatusChip(state: _state)),

          // Top spacer — pushes the entire player+button group to centre
          const Spacer(),

          // ── Waveform + play button (single combined widget) ──
          _WaveformPlayer(
            bars: displayBars,
            isPlaying: _isPlaying,
            playProgress: _playProgressValue,
            position: _playPosition,
            duration: _playDuration,
            onToggle: _togglePlayback,
            onSeekFraction: (p) => _player.seek(
              Duration(
                milliseconds: (p * _playDuration.inMilliseconds).toInt(),
              ),
            ),
          ),

          const SizedBox(height: 26),

          Text(
            'Listen to your recording, then analyse',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (_playDuration.inSeconds < _minDurationSeconds)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Record more than 3 seconds to analyse emotion.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.angry,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          if (_playDuration.inSeconds > _maxDurationSeconds)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Recording exceeds 59 seconds — trim it and try again.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.angry,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          // Helper text → Analyse button (lower the button)
          const SizedBox(height: 50),

          ElevatedButton.icon(
            onPressed: () => _analyseEmotion(_recordingPath!),
            icon: const Icon(Icons.psychology_rounded),
            label: const Text('Analyse Emotion'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          // Analyse button → Save/Discard row (50% more gap)
          const SizedBox(height: 26),

          if (_inputMethod == AudioInputMethod.live)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showSaveSheet,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('Save'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryLight,
                      side: const BorderSide(
                        color: AppColors.primaryLight,
                        width: 1,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _discardRecording,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Discard'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.angry,
                      side: const BorderSide(color: AppColors.angry, width: 1),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            )
          else
            OutlinedButton.icon(
              onPressed: _discardRecording,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Discard'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.angry,
                side: const BorderSide(color: AppColors.angry, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),

          // Bottom spacer — equal to top, keeping the group centred
          const Spacer(),
        ],
      ),
    );
  }

  // ── Analysing view ─────────────────────────────────────────────────────────
  Widget _buildAnalysingView() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 3,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Analysing emotion…',
            style: TextStyle(
              color: AppColors.primaryLight,
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mode selection card ───────────────────────────────────────────────────────
class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _TapScale(
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 34),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Tap-scale interaction wrapper ────────────────────────────────────────────
class _TapScale extends StatefulWidget {
  const _TapScale({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.93,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

// ─── Waveform + play button (single combined widget) ─────────────────────────
class _WaveformPlayer extends StatelessWidget {
  const _WaveformPlayer({
    required this.bars,
    required this.isPlaying,
    required this.playProgress,
    required this.position,
    required this.duration,
    required this.onToggle,
    required this.onSeekFraction,
  });

  final List<double> bars;
  final bool isPlaying;
  final double playProgress; // 0.0–1.0
  final Duration position;
  final Duration duration;
  final VoidCallback onToggle;
  final void Function(double) onSeekFraction; // 0.0–1.0

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // ── Play button + waveform side-by-side ───────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Play / Pause button on the left of the waveform
              GestureDetector(
                onTap: onToggle,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: AppColors.primary,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Waveform — tap or drag to seek
              Expanded(
                child: LayoutBuilder(
                  builder: (_, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => onSeekFraction(
                      (d.localPosition.dx / constraints.maxWidth).clamp(
                        0.0,
                        1.0,
                      ),
                    ),
                    onHorizontalDragUpdate: (d) => onSeekFraction(
                      (d.localPosition.dx / constraints.maxWidth).clamp(
                        0.0,
                        1.0,
                      ),
                    ),
                    child: _Waveform(
                      bars: bars,
                      isRecording: false,
                      playProgress: playProgress,
                      height: 80,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Timestamps aligned under the waveform ─────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 56), // skip past play button
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmt(position),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  _fmt(duration),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status chip ──────────────────────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});
  final RecordState state;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (state) {
      RecordState.idle => ('Ready', AppColors.neutral, Icons.circle_outlined),
      RecordState.readyToRecord => (
        'Ready to Record',
        AppColors.primary,
        Icons.mic_outlined,
      ),
      RecordState.recording => (
        'Recording',
        AppColors.angry,
        Icons.fiber_manual_record,
      ),
      RecordState.stopped => (
        'Stopped',
        AppColors.primary,
        Icons.check_circle_outline,
      ),
      RecordState.analysing => (
        'Analysing',
        AppColors.primaryLight,
        Icons.psychology_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Waveform ─────────────────────────────────────────────────────────────────
class _Waveform extends StatelessWidget {
  const _Waveform({
    required this.bars,
    required this.isRecording,
    this.playProgress,
    this.height = 80,
  });

  final List<double> bars;
  final bool isRecording;

  /// 0.0–1.0 playback position; bars before this index are highlighted.
  /// Null means no progress indicator (static / idle view).
  final double? playProgress;

  final double height;

  @override
  Widget build(BuildContext context) {
    final total = bars.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Distribute available width evenly across all bars so they never
        // overflow, regardless of the container width.
        final slotW = (constraints.maxWidth / total).clamp(2.5, 6.0);
        final barW = slotW * 0.62;
        final marginH = (slotW - barW) / 2;

        return SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: bars.asMap().entries.map((entry) {
              final i = entry.key;
              final bar = entry.value;
              final barH = (bar * height).clamp(5.0, height);

              Color barColor;
              if (isRecording) {
                barColor = AppColors.primary.withValues(
                  alpha: (bar * 1.2).clamp(0.4, 1.0),
                );
              } else if (playProgress != null) {
                final playedUpTo = (playProgress! * total).floor();
                barColor = i <= playedUpTo
                    ? AppColors.primary.withValues(
                        alpha: (bar * 0.7 + 0.35).clamp(0.4, 1.0),
                      )
                    : AppColors.onSurface.withValues(alpha: 0.18);
              } else {
                barColor = AppColors.onSurface.withValues(alpha: 0.25);
              }

              return AnimatedContainer(
                duration: const Duration(milliseconds: 60),
                width: barW,
                height: barH,
                margin: EdgeInsets.symmetric(horizontal: marginH),
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

// ─── Save bottom sheet ────────────────────────────────────────────────────────
class _SaveSheet extends StatelessWidget {
  const _SaveSheet({
    required this.recordingPath,
    required this.duration,
    required this.onSavedToPhone,
    required this.onDiscard,
  });

  final String recordingPath;
  final Duration duration;
  final VoidCallback onSavedToPhone;
  final VoidCallback onDiscard;

  String get _fileName => recordingPath.split('/').last;

  String _fmtDur(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'Save Recording',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),

          Row(
            children: [
              const Icon(
                Icons.audio_file_outlined,
                size: 14,
                color: AppColors.onSurface,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _fileName,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _fmtDur(duration),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          _SaveOption(
            icon: Icons.smartphone_outlined,
            color: AppColors.happy,
            title: 'Save to Phone',
            subtitle: 'Public · accessible via file manager',
            onTap: onSavedToPhone,
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: onDiscard,
              icon: const Icon(
                Icons.delete_outline,
                size: 18,
                color: AppColors.angry,
              ),
              label: const Text(
                'Discard',
                style: TextStyle(color: AppColors.angry),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveOption extends StatelessWidget {
  const _SaveOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.onBackground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: color.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Emotion capability tag ────────────────────────────────────────────────────
class _EmotionTag extends StatelessWidget {
  const _EmotionTag({
    required this.emoji,
    required this.label,
    required this.color,
  });

  final String emoji;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
