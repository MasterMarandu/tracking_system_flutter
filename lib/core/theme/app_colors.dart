import 'package:flutter/material.dart';

abstract class AppColors {
  // Primary
  static const Color primary = Color(0xFF1565C0);
  static const Color primaryLight = Color(0xFF5E92F3);
  static const Color primaryDark = Color(0xFF003C8F);
  
  // Secondary
  static const Color secondary = Color(0xFF00897B);
  static const Color secondaryLight = Color(0xFF4EBAAA);
  static const Color secondaryDark = Color(0xFF005B4F);
  
  // Accent
  static const Color accent = Color(0xFFFF6F00);
  
  // Background
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF2C2C2C);
  
  // Text
  static const Color textPrimaryLight = Color(0xFF212121);
  static const Color textSecondaryLight = Color(0xFF757575);
  static const Color textPrimaryDark = Color(0xFFE0E0E0);
  static const Color textSecondaryDark = Color(0xFF9E9E9E);
  
  // Status
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color error = Color(0xFFF44336);
  static const Color info = Color(0xFF2196F3);
  
  // Shipping Status
  static const Color statusCreated = Color(0xFF9E9E9E);
  static const Color statusPreparing = Color(0xFF2196F3);
  static const Color statusDispatched = Color(0xFF03A9F4);
  static const Color statusInRoute = Color(0xFFFF9800);
  static const Color statusInCenter = Color(0xFFFFC107);
  static const Color statusInDelivery = Color(0xFFFF5722);
  static const Color statusDelivered = Color(0xFF4CAF50);
  static const Color statusReturned = Color(0xFFF44336);
  static const Color statusCancelled = Color(0xFF795548);
  
  // Priority
  static const Color priorityLow = Color(0xFF4CAF50);
  static const Color priorityNormal = Color(0xFF2196F3);
  static const Color priorityHigh = Color(0xFFFF9800);
  static const Color priorityUrgent = Color(0xFFF44336);
  
  // GPS Signal
  static const Color gpsStrong = Color(0xFF4CAF50);
  static const Color gpsMedium = Color(0xFFFFC107);
  static const Color gpsWeak = Color(0xFFF44336);
  static const Color gpsNone = Color(0xFF9E9E9E);
  
  // Gradient
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [secondary, secondaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
