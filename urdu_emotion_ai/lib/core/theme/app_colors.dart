import 'package:flutter/material.dart';

class AppColors {
  // Emotion colors
  static const Color happy   = Color(0xFFF5C518);
  static const Color sad     = Color(0xFF4A90D9);
  static const Color angry   = Color(0xFFE53935);
  static const Color neutral = Color(0xFF78909C);

  // App theme
  static const Color primary       = Color(0xFF6C3FC8); // deep purple
  static const Color primaryLight  = Color(0xFF9D6FE8);
  static const Color background    = Color(0xFF0D0D16);
  static const Color surface       = Color(0xFF1A1A2E);
  static const Color card          = Color(0xFF16213E);
  static const Color onPrimary     = Color(0xFFFFFFFF);
  static const Color onBackground  = Color(0xFFEEEEEE);
  static const Color onSurface     = Color(0xFFCCCCCC);
  static const Color divider       = Color(0xFF2A2A3E);

  // Helper: get emotion color by label
  static Color forEmotion(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':   return happy;
      case 'sad':     return sad;
      case 'angry':   return angry;
      default:        return neutral;
    }
  }
}