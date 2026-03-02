import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/services/firestore_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/app_colors.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab>
    with SingleTickerProviderStateMixin {
  final _titleController   = TextEditingController();
  final _messageController = TextEditingController();
  String _notifTarget = 'All Users';
  bool _sending = false;
  bool _exporting = false;
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

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
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  // Platform channel — must match the channel registered in MainActivity.kt
  static const _downloadsChannel =
      MethodChannel('com.example.urdu_emotion_ai/audio_picker');

  void _showSnack(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  /// Write bytes to a temp file and then copy to public Downloads via
  /// the native platform channel (MediaStore on Android 10+).
  Future<bool> _saveToDownloads(
    List<int> bytes,
    String fileName,
    String mimeType,
  ) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final tmpPath = '${dir.path}/$fileName';
      await File(tmpPath).writeAsBytes(bytes);

      final ok = await _downloadsChannel.invokeMethod<bool>(
        'saveToDownloads',
        {
          'path': tmpPath,
          'fileName': fileName,
          'mimeType': mimeType,
        },
      );

      // Clean up temp file
      try {
        await File(tmpPath).delete();
      } catch (_) {}

      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  String _userLabel(UserProfile u) {
    if (u.displayName.isNotEmpty) return u.displayName;
    if (u.email.isNotEmpty) return u.email;
    return 'User ${u.uid.substring(0, u.uid.length.clamp(0, 6))}';
  }

  // ── Export handlers ─────────────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      final sessions =
          await FirestoreService.instance.getAllSessionsAdmin();
      final users = await FirestoreService.instance.getAllUsers();
      final realUsers = users.where((u) => u.role != 'admin').toList();

      final Map<String, String> nameMap = {};
      for (final u in users) {
        nameMap[u.uid] = _userLabel(u);
      }

      // ── Compute stats ──────────────────────────────────────────────────
      final totalSessions = sessions.length;
      final totalUsers = realUsers.length;
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final activeToday = sessions
          .where((s) =>
              s.timestamp != null &&
              s.timestamp!.toDate().isAfter(todayStart))
          .length;

      // Emotion distribution
      final Map<String, int> emotionCounts = {};
      for (final s in sessions) {
        emotionCounts[s.emotion] = (emotionCounts[s.emotion] ?? 0) + 1;
      }
      final total = totalSessions.toDouble().clamp(1, double.infinity);

      // Group sessions by user
      final Map<String, List<SessionRecord>> byUser = {};
      for (final s in sessions) {
        byUser.putIfAbsent(s.uid, () => []).add(s);
      }

      // ── Build PDF ──────────────────────────────────────────────────────
      final pdf = pw.Document();

      // Page 1: Overview
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Urdu Emotion AI — Admin Report',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Generated: ${now.day}/${now.month}/${now.year}  ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
              ),
              pw.Divider(),
              pw.SizedBox(height: 12),

              // KPI row
              pw.Text('Overview', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _pdfKpi('Total Users', '$totalUsers'),
                  _pdfKpi('Total Sessions', '$totalSessions'),
                  _pdfKpi('Recordings', '$totalSessions'),
                  _pdfKpi('Active Today', '$activeToday'),
                ],
              ),
              pw.SizedBox(height: 20),

              // Emotion distribution
              pw.Text('Emotion Distribution', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              if (emotionCounts.isEmpty)
                pw.Text('No session data yet.')
              else
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                  cellStyle: const pw.TextStyle(fontSize: 10),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  headers: ['Emotion', 'Count', 'Percentage'],
                  data: emotionCounts.entries.map((e) => [
                    e.key,
                    '${e.value}',
                    '${(e.value / total * 100).toStringAsFixed(1)}%',
                  ]).toList(),
                ),
              pw.SizedBox(height: 20),

              // User summary table
              pw.Text('User Summary', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              if (realUsers.isEmpty)
                pw.Text('No users found.')
              else
                pw.TableHelper.fromTextArray(
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  headers: ['Name', 'Email', 'Sessions', 'Top Emotion'],
                  data: realUsers.map((u) {
                    final uSessions = byUser[u.uid] ?? [];
                    final Map<String, int> eCounts = {};
                    for (final s in uSessions) {
                      eCounts[s.emotion] = (eCounts[s.emotion] ?? 0) + 1;
                    }
                    String topEmo = 'N/A';
                    if (eCounts.isNotEmpty) {
                      topEmo = (eCounts.entries.toList()
                            ..sort((a, b) => b.value.compareTo(a.value)))
                          .first
                          .key;
                    }
                    return [
                      _userLabel(u),
                      u.email.isNotEmpty ? u.email : 'N/A',
                      '${uSessions.length}',
                      topEmo,
                    ];
                  }).toList(),
                ),
            ],
          ),
        ),
      );

      // Page 2: Session details (paginated table)
      if (sessions.isNotEmpty) {
        // Sort sessions by timestamp descending
        final sorted = List<SessionRecord>.from(sessions)
          ..sort((a, b) {
            final ta = a.timestamp;
            final tb = b.timestamp;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });

        final sessionRows = sorted.map((s) {
          final date = s.timestamp != null
              ? '${s.timestamp!.toDate().day}/${s.timestamp!.toDate().month}/${s.timestamp!.toDate().year}'
              : 'N/A';
          return [
            nameMap[s.uid] ?? 'User ${s.uid.substring(0, s.uid.length.clamp(0, 6))}',
            s.emotion,
            '${s.confidence.toStringAsFixed(1)}%',
            '${s.durationSeconds}s',
            date,
          ];
        }).toList();

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            header: (ctx) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                'Session Details (${sessions.length} sessions)',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
              ),
            ),
            build: (ctx) => [
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
                headers: ['User', 'Emotion', 'Confidence', 'Duration', 'Date'],
                data: sessionRows,
              ),
            ],
          ),
        );
      }

      // Save PDF
      final pdfBytes = await pdf.save();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'emotion_report_$ts.pdf';

      final ok = await _saveToDownloads(pdfBytes, fileName, 'application/pdf');
      _showSnack(
        ok ? 'PDF saved to Downloads.' : 'Could not save PDF to Downloads.',
        ok ? AppColors.primary : AppColors.angry,
      );
    } catch (e) {
      _showSnack('Export failed: $e', AppColors.angry);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Small KPI widget for the PDF overview section.
  static pw.Widget _pdfKpi(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        children: [
          pw.Text(value, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  Future<void> _exportSessionsCsv() async {
    setState(() => _exporting = true);
    try {
      final sessions =
          await FirestoreService.instance.getAllSessionsAdmin();
      final users = await FirestoreService.instance.getAllUsers();

      final Map<String, String> nameMap = {};
      for (final u in users) {
        nameMap[u.uid] = _userLabel(u);
      }

      final rows = <List<String>>[
        [
          'Session ID',
          'User',
          'Emotion',
          'Confidence (%)',
          'Duration (s)',
          'Date',
        ],
      ];
      for (final s in sessions) {
        final date = s.timestamp != null
            ? s.timestamp!.toDate().toIso8601String()
            : 'N/A';
        rows.add([
          s.id,
          nameMap[s.uid] ?? 'User ${s.uid.substring(0, s.uid.length.clamp(0, 6))}',
          s.emotion,
          s.confidence.toStringAsFixed(1),
          s.durationSeconds.toString(),
          date,
        ]);
      }

      final csv = const ListToCsvConverter().convert(rows);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'sessions_report_$ts.csv';

      final ok = await _saveToDownloads(utf8.encode(csv), fileName, 'text/csv');
      _showSnack(
        ok ? 'CSV saved to Downloads.' : 'Could not save CSV to Downloads.',
        ok ? AppColors.primary : AppColors.angry,
      );
    } catch (e) {
      _showSnack('Export failed: $e', AppColors.angry);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportUsersCsv() async {
    setState(() => _exporting = true);
    try {
      final users = await FirestoreService.instance.getAllUsers();
      final sessions = await FirestoreService.instance.getAllSessionsAdmin();

      // Group sessions by user for aggregate metrics
      final Map<String, List<SessionRecord>> byUser = {};
      for (final s in sessions) {
        byUser.putIfAbsent(s.uid, () => []).add(s);
      }

      final rows = <List<String>>[
        [
          'UID',
          'Name',
          'Email',
          'Sessions',
          'Top Emotion',
          'Last Active',
        ],
      ];
      for (final u in users) {
        if (u.role == 'admin') continue; // Skip admin accounts

        final userSessions = byUser[u.uid] ?? [];
        final totalSessions = userSessions.length;

        // Top emotion
        final Map<String, int> emotionCounts = {};
        for (final s in userSessions) {
          emotionCounts[s.emotion] = (emotionCounts[s.emotion] ?? 0) + 1;
        }
        String topEmotion = 'N/A';
        if (emotionCounts.isNotEmpty) {
          topEmotion = (emotionCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
        }

        // Last active
        DateTime? lastActive;
        for (final s in userSessions) {
          final dt = s.timestamp?.toDate();
          if (dt != null && (lastActive == null || dt.isAfter(lastActive))) {
            lastActive = dt;
          }
        }

        rows.add([
          u.uid,
          _userLabel(u),
          u.email.isNotEmpty ? u.email : 'N/A',
          totalSessions.toString(),
          topEmotion,
          lastActive?.toIso8601String() ?? 'N/A',
        ]);
      }

      final csv = const ListToCsvConverter().convert(rows);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'users_report_$ts.csv';

      final ok = await _saveToDownloads(utf8.encode(csv), fileName, 'text/csv');
      _showSnack(
        ok ? 'CSV saved to Downloads.' : 'Could not save CSV to Downloads.',
        ok ? AppColors.primary : AppColors.angry,
      );
    } catch (e) {
      _showSnack('Export failed: $e', AppColors.angry);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _sendNotification() async {
    final title = _titleController.text.trim();
    final body  = _messageController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _showSnack('Please fill in both title and message.', AppColors.angry);
      return;
    }
    setState(() => _sending = true);
    try {
      await NotificationService.instance.sendAdminNotification(
        title: title,
        body: body,
        target: _notifTarget,
      );
      if (!mounted) return;
      _titleController.clear();
      _messageController.clear();
      _showSnack('Notification sent successfully.', AppColors.primary);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to send: $e', AppColors.angry);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
        // ── Export section ─────────────────────────────────────────────────
        const _SecTitle('Export Reports'),
        const SizedBox(height: 4),
        const Text(
          'Download app analytics to your device in CSV format.',
          style: TextStyle(fontSize: 12, color: AppColors.onSurface),
        ),
        const SizedBox(height: 16),

        if (_exporting)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          _ExportCard(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Export as PDF',
            subtitle: 'Overview stats, charts & emotion analytics',
            color: AppColors.angry,
            onTap: _exportPdf,
          ),
          const SizedBox(height: 10),
          _ExportCard(
            icon: Icons.table_chart_outlined,
            title: 'Export Sessions as CSV',
            subtitle: 'All session data for spreadsheet analysis',
            color: AppColors.happy,
            onTap: _exportSessionsCsv,
          ),
          const SizedBox(height: 10),
          _ExportCard(
            icon: Icons.people_outline,
            title: 'Export User Report as CSV',
            subtitle: 'Full user activity data in CSV format',
            color: AppColors.sad,
            onTap: _exportUsersCsv,
          ),
        ],

        const SizedBox(height: 28),
        const Divider(color: AppColors.divider),
        const SizedBox(height: 20),

        // ── Notifications section ──────────────────────────────────────────
        const _SecTitle('Push Notifications'),
        const SizedBox(height: 4),
        const Text(
          'Compose and send push notifications to users. Requires Firebase Cloud Messaging.',
          style: TextStyle(fontSize: 12, color: AppColors.onSurface),
        ),
        const SizedBox(height: 16),

        // Target selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.group_outlined,
                  size: 18, color: AppColors.onSurface),
              const SizedBox(width: 10),
              const Text('Send to:',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.onSurface)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _notifTarget,
                dropdownColor: AppColors.surface,
                underline: const SizedBox.shrink(),
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.onBackground,
                    fontWeight: FontWeight.w600),
                items: ['All Users', 'Active Users']
                    .map((v) => DropdownMenuItem(
                          value: v,
                          child: Text(v),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _notifTarget = v!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Title field
        TextField(
          controller: _titleController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Notification Title',
            prefixIcon: Icon(Icons.title_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 12),

        // Message field
        TextField(
          controller: _messageController,
          maxLines: 4,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Message',
            alignLabelWithHint: true,
            prefixIcon: Padding(
              padding: EdgeInsets.only(bottom: 54),
              child: Icon(Icons.message_outlined, size: 20),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Send button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _sending ? null : _sendNotification,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(_sending ? 'Sending…' : 'Send Notification'),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Notifications are sent to all non-blocked users who have enabled push notifications.',
          style: TextStyle(fontSize: 11, color: AppColors.onSurface),
          textAlign: TextAlign.center,
        ),
          ],
        ),
      ),
    );
  }
}

// ─── Section title ────────────────────────────────────────────────────────────
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

// ─── Export card ──────────────────────────────────────────────────────────────
class _ExportCard extends StatelessWidget {
  const _ExportCard({
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
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
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
                        fontSize: 14,
                        color: AppColors.onBackground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.onSurface),
                    ),
                  ],
                ),
              ),
              Icon(Icons.download_outlined,
                  size: 18, color: color.withValues(alpha: 0.7)),
            ],
          ),
        ),
      );
}
