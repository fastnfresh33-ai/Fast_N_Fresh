import 'package:flutter/material.dart';

/// Single source of truth for the app's brand color and palette.
/// Change [primary] here to re-theme the entire app.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF0E7C5A); // cafe green
  static const Color primaryDark = Color(0xFF0A5F44);
  static const Color primaryLight = Color(0xFFE6F4EF);

  static const Color accent = Color(0xFFE8A33D); // warm amber accent

  static const Color background = Color(0xFFFAFAF8);
  static const Color surface = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF1B1B1B);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color textMuted = Color(0xFF9B9B9B);

  static const Color border = Color(0xFFE7E5E0);
  static const Color divider = Color(0xFFEFEDE8);

  static const Color success = Color(0xFF2E9E5B);
  static const Color danger = Color(0xFFD64545);
  static const Color warning = Color(0xFFE8A33D);
  static const Color info = Color(0xFF3D7FE8);

  // Payment method colors
  static const Color cash = Color(0xFF2E9E5B);
  static const Color upi = Color(0xFF3D7FE8);
  static const Color credit = Color(0xFFD64545);

  static const Color cardShadow = Color(0x14000000);
}
