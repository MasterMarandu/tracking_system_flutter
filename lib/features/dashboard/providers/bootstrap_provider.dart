import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';
import 'package:tracking_system_app/features/sync/domain/sync_engine.dart';

enum AppAuthStatus { unknown, authenticated, unauthenticated }

class AppAuthState {
  final AppAuthStatus status;
  final Object? user;

  const AppAuthState({this.status = AppAuthStatus.unknown, this.user});
}

class BootstrapNotifier extends AsyncNotifier<DriverBootstrap?> {
  @override
  Future<DriverBootstrap?> build() async {
    final session = SupabaseConfig.client.auth.currentSession;
    if (session == null) return null;
    return _load(forceRefresh: false);
  }

  Future<DriverBootstrap?> _load({required bool forceRefresh}) async {
    debugPrint('Bootstrap: carga vía SyncEngine (cache + red)');

    try {
      final result = await ref
          .read(syncEngineProvider.notifier)
          .loadBootstrap(forceRefresh: forceRefresh)
          .timeout(const Duration(seconds: 20));

      debugPrint(
        'Bootstrap: ok trip=${result?.trip?.code} '
        'pkgs=${result?.packages.length ?? 0}',
      );
      return result;
    } catch (e) {
      debugPrint('Bootstrap ERROR: $e');
      // Último recurso: intentar cache sin forzar red (engine ya lo hace)
      try {
        final cached = await ref
            .read(syncEngineProvider.notifier)
            .loadBootstrap(forceRefresh: false)
            .timeout(const Duration(seconds: 8));
        if (cached != null) return cached;
      } catch (e2) {
        debugPrint('Bootstrap cache ERROR: $e2');
      }
      rethrow;
    }
  }

  Future<void> loadBootstrap() async {
    final session = SupabaseConfig.client.auth.currentSession;
    if (session == null) {
      state = const AsyncData(null);
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(forceRefresh: false));
  }

  Future<void> forceRefresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _load(forceRefresh: true));
  }

  void clear() {
    state = const AsyncData(null);
  }
}

final authStateProvider =
    StateNotifierProvider<AuthNotifier, AppAuthState>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<AppAuthState> {
  StreamSubscription? _subscription;

  AuthNotifier() : super(const AppAuthState()) {
    _subscription = SupabaseConfig.client.auth.onAuthStateChange.listen(
      (supabaseState) {
        final session = supabaseState.session;
        if (session != null) {
          state = AppAuthState(
              status: AppAuthStatus.authenticated, user: session.user);
        } else {
          state = const AppAuthState(status: AppAuthStatus.unauthenticated);
        }
      },
    );

    final currentSession = SupabaseConfig.client.auth.currentSession;
    if (currentSession != null) {
      state = AppAuthState(
        status: AppAuthStatus.authenticated,
        user: currentSession.user,
      );
    } else {
      state = const AppAuthState(status: AppAuthStatus.unauthenticated);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

final bootstrapProvider =
    AsyncNotifierProvider<BootstrapNotifier, DriverBootstrap?>(
  BootstrapNotifier.new,
);

final driverSessionStateProvider = Provider<DriverSessionState>((ref) {
  final bootstrap = ref.watch(bootstrapProvider).valueOrNull;
  if (bootstrap == null) return DriverSessionState.loading;
  if (!bootstrap.user.active) return DriverSessionState.profileIncomplete;
  return bootstrap.resolveState();
});
