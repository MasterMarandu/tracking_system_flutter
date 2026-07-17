import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/config/app_config.dart';
import 'package:tracking_system_app/core/router/app_router.dart';
import 'package:tracking_system_app/core/theme/app_theme.dart';
import 'package:tracking_system_app/core/services/connectivity_service.dart';
import 'package:tracking_system_app/core/services/notification_service.dart';
import 'package:tracking_system_app/features/settings/domain/settings_provider.dart';

void main() async {
  await AppConfig.initialize();
  
  await ConnectivityService.instance.initialize();
  await NotificationService.instance.initialize();
  
  runApp(
    const ProviderScope(
      child: TrackingSystemApp(),
    ),
  );
}

class TrackingSystemApp extends ConsumerWidget {
  const TrackingSystemApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    
    return MaterialApp.router(
      title: 'Routio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
