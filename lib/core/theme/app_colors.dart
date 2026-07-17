import 'package:flutter/material.dart';

/// Paleta alineada con Routio web (`globals.css`).
abstract class AppColors {
  // Brand / primary (Routio green)
  static const Color primary = Color(0xFF206B5C);
  static const Color primaryLight = Color(0xFF2D8A78);
  static const Color primaryDark = Color(0xFF174F44);
  static const Color primarySoft = Color(0xFFE8F2EF);

  // Secondary (teal complement)
  static const Color secondary = Color(0xFF2D8A78);
  static const Color secondaryLight = Color(0xFF56A08C);
  static const Color secondaryDark = Color(0xFF174F44);

  // Accent (amber, same as web live map / alerts)
  static const Color accent = Color(0xFFF59E42);
  static const Color amber = Color(0xFFD97706);
  static const Color amberLight = Color(0xFFFFF7E8);

  // Background / surfaces
  static const Color backgroundLight = Color(0xFFF4F6F5); // --canvas
  static const Color backgroundDark = Color(0xFF0D1E1A);
  static const Color surfaceLight = Color(0xFFFFFFFF); // --surface
  static const Color surfaceDark = Color(0xFF152A26); // --sidebar-ish
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF1A2F2A);

  // Sidebar (web)
  static const Color sidebar = Color(0xFF152A26);
  static const Color sidebarGradientStart = Color(0xFF142824);
  static const Color sidebarGradientEnd = Color(0xFF0D1E1A);

  // Text
  static const Color textPrimaryLight = Color(0xFF172521); // --ink
  static const Color textSecondaryLight = Color(0xFF6E7B77); // --muted
  static const Color textSubtleLight = Color(0xFF96A09D); // --subtle
  static const Color textPrimaryDark = Color(0xFFF2F7F5);
  static const Color textSecondaryDark = Color(0xFF9EB3AD);

  // Lines
  static const Color line = Color(0xFFE2E8E5);
  static const Color lineStrong = Color(0xFFD4DDDA);

  // Status
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFC74C4C); // --red
  static const Color info = Color(0xFF206B5C);

  // Shipping Status
  static const Color statusCreated = Color(0xFF96A09D);
  static const Color statusPreparing = Color(0xFF2D8A78);
  static const Color statusDispatched = Color(0xFF206B5C);
  static const Color statusInRoute = Color(0xFFF59E42);
  static const Color statusInCenter = Color(0xFFD97706);
  static const Color statusInDelivery = Color(0xFFE07A2F);
  static const Color statusDelivered = Color(0xFF16A34A);
  static const Color statusReturned = Color(0xFFC74C4C);
  static const Color statusCancelled = Color(0xFF6E7B77);

  // Priority
  static const Color priorityLow = Color(0xFF16A34A);
  static const Color priorityNormal = Color(0xFF206B5C);
  static const Color priorityHigh = Color(0xFFD97706);
  static const Color priorityUrgent = Color(0xFFC74C4C);

  // GPS Signal
  static const Color gpsStrong = Color(0xFF16A34A);
  static const Color gpsMedium = Color(0xFFD97706);
  static const Color gpsWeak = Color(0xFFC74C4C);
  static const Color gpsNone = Color(0xFF96A09D);

  // Gradients (landing brand-mark style)
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF206B5C), Color(0xFF2D8A78)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [secondary, secondaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient sidebarGradient = LinearGradient(
    colors: [sidebarGradientStart, sidebarGradientEnd],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
