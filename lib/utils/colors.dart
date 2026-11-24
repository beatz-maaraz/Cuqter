import 'package:flutter/material.dart';

class AppColors {
  // Cuqter Core Palette
  static const Color baseScreen = Color(0xFF001D39);
  static const Color persistentBar = Color(0xFF0A4174);
  static const Color interactiveContainer = Color(0xFF49769F);
  static const Color interactiveFocus = Color(0xFF4E8EA2);
  static const Color textSecondary = Color(0xFF6EA2B3);
  static const Color accentHighlight = Color(0xFF7BBDE8);
  static const Color textPrimary = Color(0xFFBDD8E9);

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
  static const Color accent = accentHighlight;
  static const Color onlineSuccess = Color(0xFF55B879);
  static const Color warning = Color(0xFFE3A83B);
  static const Color errorFailed = Color(0xFFD95C5C);
  static const Color infoLinks = accentHighlight;

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
