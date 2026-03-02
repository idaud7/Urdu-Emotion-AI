// Generated from your Firebase project "urdu-emotion-a492e".
// Values extracted from android/app/google-services.json.
// Run `flutterfire configure` to regenerate this file and add iOS support.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web. '
        'Run flutterfire configure to generate web options.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for iOS/macOS. '
          'Run flutterfire configure to add a GoogleService-Info.plist.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for this platform.',
        );
    }
  }

  /// Android options – sourced from android/app/google-services.json
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD21ZQUuKnXltiaOAVgnRn44IaFVX4jrOY',
    appId: '1:81637034149:android:6dc0bbaca01cb79760a54c',
    messagingSenderId: '81637034149',
    projectId: 'urdu-emotion-a492e',
    storageBucket: 'urdu-emotion-a492e.firebasestorage.app',
  );
}
