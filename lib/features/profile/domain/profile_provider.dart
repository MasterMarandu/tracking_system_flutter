import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';
import 'package:tracking_system_app/features/profile/data/profile_service.dart';
import 'package:tracking_system_app/features/profile/domain/driver_profile.dart';
import 'package:tracking_system_app/features/sync/domain/sync_engine.dart';

class ProfileNotifier extends AsyncNotifier<DriverProfile?> {
  @override
  Future<DriverProfile?> build() async {
    // Reaccionar a cambios de bootstrap (login/logout/refresh)
    ref.watch(bootstrapProvider);
    try {
      return await ProfileService.instance.fetchProfile();
    } catch (e) {
      // Fallback: armar perfil desde bootstrap ya cargado
      final boot = ref.read(bootstrapProvider).valueOrNull;
      if (boot == null) rethrow;
      final parts = boot.user.name.trim().split(RegExp(r'\s+'));
      final nombre = parts.isNotEmpty ? parts.first : '';
      final apellido =
          parts.length > 1 ? parts.sublist(1).join(' ') : '';
      return DriverProfile(
        usuarioId: boot.user.id,
        conductorId: boot.driver.id.isEmpty ? null : boot.driver.id,
        nombre: nombre,
        apellido: apellido,
        email: boot.user.email ?? '',
        telefono: boot.user.phone ?? boot.driver.phone,
        activo: boot.user.active,
        rolNombre: boot.user.role,
        empresaId: boot.user.companyId,
        licencia: boot.driver.license,
        conductorEstado: boot.driver.status,
        fotoUrl: boot.driver.photoUrl,
        vehiculoId: boot.vehicle?.id,
        vehiculoLabel: boot.vehicle != null
            ? '${boot.vehicle!.plate} · ${boot.vehicle!.brand} ${boot.vehicle!.model}'
                .trim()
            : null,
        vehiculoMatricula: boot.vehicle?.plate,
      );
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ProfileService.instance.fetchProfile());
  }

  Future<void> updateProfile({
    String? nombre,
    String? apellido,
    String? telefono,
  }) async {
    final current = state.valueOrNull;
    if (current == null) throw Exception('Perfil no cargado');

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return ProfileService.instance.updateProfile(
        usuarioId: current.usuarioId,
        conductorId: current.conductorId,
        nombre: nombre,
        apellido: apellido,
        telefono: telefono,
      );
    });

    // Refrescar bootstrap para que el dashboard use el nombre actualizado
    try {
      await ref.read(bootstrapProvider.notifier).forceRefresh();
    } catch (_) {}
  }

  Future<void> changePassword(String newPassword) async {
    await ProfileService.instance.changePassword(newPassword: newPassword);
  }

  Future<void> logout() async {
    try {
      await ref.read(syncEngineProvider.notifier).clearAll();
    } catch (_) {}
    ref.read(bootstrapProvider.notifier).clear();
    await ProfileService.instance.signOut();
  }
}

final profileProvider =
    AsyncNotifierProvider<ProfileNotifier, DriverProfile?>(
  ProfileNotifier.new,
);
