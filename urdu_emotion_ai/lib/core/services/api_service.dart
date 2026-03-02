import 'package:http/http.dart' as http;
import 'dart:convert';

/// Service for communicating with the FastAPI emotion-recognition backend.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  /// Cloud deployment (Hugging Face Spaces / Render / Railway):
  ///   Set _backendHost to your Space URL, e.g.
  ///   'your-username-urdu-emotion-api.hf.space'
  ///   and set _useHttps = true.
  ///
  /// Local development (laptop on same Wi-Fi):
  ///   Set _backendHost to your PC's LAN IP (run `ipconfig`), e.g. '192.168.1.24'
  ///   and set _useHttps = false.
  static const String _backendHost = 'woodiee-urdu-emotion-api.hf.space';
  static const bool _useHttps = true;

  String get baseUrl =>
      '${_useHttps ? 'https' : 'http'}://$_backendHost${_useHttps ? '' : ':8000'}';

  /// Send an audio file to the backend and return the prediction.
  ///
  /// Returns `{"emotion": String, "confidence": double}`.
  /// Throws [Exception] on network or server error.
  Future<Map<String, dynamic>> predictEmotion(String filePath) async {
    final uri = Uri.parse('$baseUrl/predict');

    final request = http.MultipartRequest('POST', uri)
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await request.send().timeout(
          const Duration(seconds: 60), // 60s for cloud cold-start
        );
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      final body = json.decode(response.body);
      throw Exception(body['detail'] ?? 'Prediction failed (${response.statusCode})');
    }
  }
}
