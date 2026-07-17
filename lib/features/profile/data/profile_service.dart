import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/features/profile/domain/driver_profile.dart';

class ProfileService {
  static ProfileService? _instance;
  static ProfileService get instance => _instance ??= ProfileService._();
  ProfileService._();

  final _client = SupabaseConfig.client;

  Future<DriverProfile> fetchProfile() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      throw Exception('No hay sesión activa');
    }

    try {
      final core = await _client
          .from(SupabaseConfig.tableUsuarios)
          .select(
            'id, nombre, apellido, email, telefono, activo, empresa_id, rol_id, '
            'rol:core_roles(nombre), '
            'empresa:core_empresas(nombre)',
          )
          .eq('auth_user_id', authUser.id)
          .filter('deleted_at', 'is', null)
          .maybeSingle();

      if (core != null) {
        return _mapUsuario(Map<String, dynamic>.from(core));
      }
    } catch (e) {
      debugPrint('ProfileService fetch joins: $e');
    }

    final plain = await _client
        .from(SupabaseConfig.tableUsuarios)
        .select(
          'id, nombre, apellido, email, telefono, activo, empresa_id, rol_id',
        )
        .eq('auth_user_id', authUser.id)
        .filter('deleted_at', 'is', null)
        .maybeSingle();

    if (plain == null) {
      throw Exception('Usuario no encontrado en core_usuarios');
    }
    return _enrichPlain(Map<String, dynamic>.from(plain));
  }

  Future<DriverProfile> _enrichPlain(Map<String, dynamic> u) async {
    String? empresaNombre;
    String? rolNombre;
    final empresaId = u['empresa_id'] as String?;
    final rolId = u['rol_id'] as String?;

    if (empresaId != null) {
      try {
        final e = await _client
            .from(SupabaseConfig.tableEmpresas)
            .select('nombre')
            .eq('id', empresaId)
            .maybeSingle();
        empresaNombre = e?['nombre'] as String?;
      } catch (e) {
        debugPrint('ProfileService empresa: $e');
      }
    }
    if (rolId != null) {
      try {
        final r = await _client
            .from(SupabaseConfig.tableRoles)
            .select('nombre')
            .eq('id', rolId)
            .maybeSingle();
        rolNombre = r?['nombre'] as String?;
      } catch (e) {
        debugPrint('ProfileService rol: $e');
      }
    }

    final base = DriverProfile(
      usuarioId: u['id'] as String,
      nombre: (u['nombre'] as String?) ?? '',
      apellido: (u['apellido'] as String?) ?? '',
      email: (u['email'] as String?) ?? '',
      telefono: u['telefono'] as String?,
      activo: u['activo'] as bool? ?? true,
      rolNombre: rolNombre ?? 'Conductor',
      empresaId: empresaId ?? '',
      empresaNombre: empresaNombre,
    );

    return _withConductor(base);
  }

  Future<DriverProfile> _mapUsuario(Map<String, dynamic> u) async {
    final rol = u['rol'];
    final empresa = u['empresa'];
    String? rolNombre;
    String? empresaNombre;
    if (rol is Map) rolNombre = rol['nombre'] as String?;
    if (empresa is Map) empresaNombre = empresa['nombre'] as String?;

    final base = DriverProfile(
      usuarioId: u['id'] as String,
      nombre: (u['nombre'] as String?) ?? '',
      apellido: (u['apellido'] as String?) ?? '',
      email: (u['email'] as String?) ?? '',
      telefono: u['telefono'] as String?,
      activo: u['activo'] as bool? ?? true,
      rolNombre: rolNombre ?? 'Conductor',
      empresaId: (u['empresa_id'] as String?) ?? '',
      empresaNombre: empresaNombre,
    );

    return _withConductor(base);
  }

  Future<DriverProfile> _withConductor(DriverProfile base) async {
    try {
      final cond = await _client
          .from(SupabaseConfig.tableConductores)
          .select(
            'id, licencia, tipo_licencia, vencimiento_licencia, telefono, '
            'foto, estado, vehiculo_actual, nombre, apellido',
          )
          .eq('usuario_id', base.usuarioId)
          .filter('deleted_at', 'is', null)
          .maybeSingle();

      if (cond == null) return base;

      String? vehiculoLabel;
      String? vehiculoMatricula;
      final vehiculoId = cond['vehiculo_actual'] as String?;

      if (vehiculoId != null) {
        try {
          final v = await _client
              .from(SupabaseConfig.tableVehiculos)
              .select('matricula, marca, modelo')
              .eq('id', vehiculoId)
              .filter('deleted_at', 'is', null)
              .maybeSingle();
          if (v != null) {
            vehiculoMatricula = v['matricula'] as String?;
            final marca = (v['marca'] as String?)?.trim() ?? '';
            final modelo = (v['modelo'] as String?)?.trim() ?? '';
            final parts = <String>[
              if (vehiculoMatricula != null && vehiculoMatricula.isNotEmpty)
                vehiculoMatricula,
              if (marca.isNotEmpty || modelo.isNotEmpty)
                '$marca $modelo'.trim(),
            ];
            vehiculoLabel = parts.join(' · ');
          }
        } catch (e) {
          debugPrint('ProfileService vehiculo: $e');
        }
      }

      DateTime? venc;
      final rawVenc = cond['vencimiento_licencia'];
      if (rawVenc is String) {
        venc = DateTime.tryParse(rawVenc);
      }

      final telefonoCond = (cond['telefono'] as String?)?.trim();
      final telefono = (telefonoCond != null && telefonoCond.isNotEmpty)
          ? telefonoCond
          : base.telefono;

      final condNombre = (cond['nombre'] as String?)?.trim() ?? '';
      final condApellido = (cond['apellido'] as String?)?.trim() ?? '';

      return DriverProfile(
        usuarioId: base.usuarioId,
        conductorId: cond['id'] as String?,
        nombre: base.nombre.trim().isNotEmpty
            ? base.nombre
            : (condNombre.isNotEmpty ? condNombre : base.nombre),
        apellido: base.apellido.trim().isNotEmpty
            ? base.apellido
            : condApellido,
        email: base.email,
        telefono: telefono,
        activo: base.activo,
        rolNombre: base.rolNombre,
        empresaId: base.empresaId,
        empresaNombre: base.empresaNombre,
        licencia: cond['licencia'] as String?,
        tipoLicencia: cond['tipo_licencia'] as String?,
        vencimientoLicencia: venc,
        conductorEstado: (cond['estado'] as String?) ?? 'disponible',
        fotoUrl: cond['foto'] as String?,
        vehiculoId: vehiculoId,
        vehiculoLabel: vehiculoLabel,
        vehiculoMatricula: vehiculoMatricula,
      );
    } catch (e) {
      debugPrint('ProfileService conductor: $e');
      return base;
    }
  }

  /// Actualiza datos editables del perfil (usuario + conductor si existe).
  Future<DriverProfile> updateProfile({
    required String usuarioId,
    String? nombre,
    String? apellido,
    String? telefono,
    String? conductorId,
  }) async {
    final userPatch = <String, dynamic>{
      if (nombre != null) 'nombre': nombre.trim(),
      if (apellido != null) 'apellido': apellido.trim(),
      if (telefono != null)
        'telefono': telefono.trim().isEmpty ? null : telefono.trim(),
    };

    if (userPatch.isNotEmpty) {
      await _client
          .from(SupabaseConfig.tableUsuarios)
          .update(userPatch)
          .eq('id', usuarioId);
    }

    if (conductorId != null && conductorId.isNotEmpty) {
      final condPatch = <String, dynamic>{
        if (nombre != null) 'nombre': nombre.trim(),
        if (apellido != null) 'apellido': apellido.trim(),
        if (telefono != null)
          'telefono': telefono.trim().isEmpty ? null : telefono.trim(),
      };
      if (condPatch.isNotEmpty) {
        try {
          await _client
              .from(SupabaseConfig.tableConductores)
              .update(condPatch)
              .eq('id', conductorId);
        } catch (e) {
          debugPrint('ProfileService update conductor: $e');
        }
      }
    }

    return fetchProfile();
  }

  Future<void> changePassword({required String newPassword}) async {
    if (newPassword.length < 6) {
      throw Exception('La contraseña debe tener al menos 6 caracteres');
    }
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
  }
}
