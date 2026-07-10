import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap.dart';
import 'package:tracking_system_app/features/dashboard/domain/driver_bootstrap_service.dart';
import 'package:tracking_system_app/features/sync/data/sync_repository.dart';
import 'package:tracking_system_app/features/sync/domain/sync_engine.dart';

enum AppAuthStatus { unknown, authenticated, unauthenticated }

class AppAuthState {
  final AppAuthStatus status;
  final Object? user;

  const AppAuthState({this.status = AppAuthStatus.unknown, this.user});
}

class BootstrapNotifier extends StateNotifier<DriverBootstrap?> {
  final SyncRepository _syncRepository;

  BootstrapNotifier(this._syncRepository) : super(null);

  Future<void> loadBootstrap({bool forceRefresh = false}) async {
    try {
      final bootstrap = await _syncRepository.loadBootstrap(
        forceRefresh: forceRefresh,
      );
      state = bootstrap;
    } catch (_) {
      // Try direct service call as last resort
      try {
        final bootstrap =
            await DriverBootstrapService.instance.fetchBootstrap();
        state = bootstrap;
      } catch (_) {
        state = null;
      }
    }
  }

  Future<void> forceRefresh() async {
    state = await _syncRepository.forceRefresh();
  }

  void clear() {
    state = null;
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
    StateNotifierProvider<BootstrapNotifier, DriverBootstrap?>((ref) {
  final syncRepo = ref.watch(syncRepositoryProvider);
  return BootstrapNotifier(syncRepo);
});

final driverSessionStateProvider = Provider<DriverSessionState>((ref) {
  final bootstrap = ref.watch(bootstrapProvider);
  if (bootstrap == null) return DriverSessionState.loading;
  if (!bootstrap.user.active) return DriverSessionState.profileIncomplete;
  return bootstrap.resolveState();
});
