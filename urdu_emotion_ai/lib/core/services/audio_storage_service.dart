import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class AudioStorageService {
  AudioStorageService._();
  static final AudioStorageService instance = AudioStorageService._();

  static const MethodChannel _channel =
      MethodChannel('com.example.urdu_emotion_ai/audio_picker');

  Future<bool> saveToDownloads({
    required String sourcePath,
    required String mimeType,
  }) async {
    try {
      final fileName = sourcePath.split('/').last;

      if (Platform.isAndroid) {
        final result = await _channel.invokeMethod<bool>(
          'saveToDownloads',
          {'path': sourcePath, 'fileName': fileName, 'mimeType': mimeType},
        );
        return result == true;
      }

      Directory? dir = await getDownloadsDirectory();
      dir ??= await getExternalStorageDirectory();
      if (dir == null) return false;
      final destPath = '${dir.path}/$fileName';
      await File(sourcePath).copy(destPath);
      return true;
    } catch (_) {
      return false;
    }
  }
}

