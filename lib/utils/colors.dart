import 'package:flutter/material.dart';

class AppColors {
  // Cuqter Core Palette (Visual Hierarchy Breakdown)
  static const Color baseScreen = Color(0xFF1B0C1A);
  static const Color persistentBar = Color(0xFF2D222F);
  static const Color interactiveContainer = Color(0xFF4B2138);
  static const Color interactiveFocus = Color(0xFF6D3C52);
  static const Color textPrimary = Color(0xFFFADCD5);
  static const Color textSecondary = Color(0xFF765D67);

  // Backgrounds
  static const Color mainBackground = baseScreen;
  static const Color secondaryBackground = persistentBar;

  // Brand
  static const Color primaryBrand = interactiveFocus;
  static const Color primaryLight = interactiveContainer;

  // Messaging
  static const Color outgoingMessage = interactiveFocus;
  static const Color incomingMessage = persistentBar;

  // Text
  static const Color userText = textPrimary;
  static const Color secondaryText = textSecondary;

  // Accent & States
  static const Color accent = interactiveFocus;
  static const Color onlineSuccess = Color(0xFF55B879);
  static const Color warning = Color(0xFFE3A83B);
  static const Color errorFailed = Color(0xFFD95C5C);
  static const Color infoLinks = Color(0xFF5B9BD5);

  // Borders/Dividers
  static const Color divider = persistentBar;

  // Legacy mappings to prevent build errors
  static const Color primary = primaryBrand;
  static const Color secondary = primaryLight;
  static const Color background = mainBackground;
  static const Color card = secondaryBackground;
  static const Color text = userText;
  static const Color white = Colors.white;
  static const Color black = Colors.black;
  static const Color grey = secondaryText;
  static const Color blueDefault = primaryBrand;
}
