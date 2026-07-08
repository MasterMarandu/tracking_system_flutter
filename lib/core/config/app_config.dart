import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';

class AppConfig {
  static late final ProviderContainer providerContainer;
  
  static Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Initialize Supabase
    await SupabaseConfig.initialize();
    
    // Initialize provider container
    providerContainer = ProviderContainer();
  }
}
