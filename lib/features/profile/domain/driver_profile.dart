/// Perfil del conductor en la app (core_usuarios + fleet_conductores + vehículo/empresa).
class DriverProfile {
  final String usuarioId;
  final String? conductorId;
  final String nombre;
  final String apellido;
  final String email;
  final String? telefono;
  final bool activo;
  final String? rolNombre;
  final String empresaId;
  final String? empresaNombre;
  final String? licencia;
  final String? tipoLicencia;
  final DateTime? vencimientoLicencia;
  final String conductorEstado;
  final String? fotoUrl;
  final String? vehiculoId;
  final String? vehiculoLabel;
  final String? vehiculoMatricula;

  const DriverProfile({
    required this.usuarioId,
    this.conductorId,
    required this.nombre,
    required this.apellido,
    required this.email,
    this.telefono,
    required this.activo,
    this.rolNombre,
    required this.empresaId,
    this.empresaNombre,
    this.licencia,
    this.tipoLicencia,
    this.vencimientoLicencia,
    this.conductorEstado = 'disponible',
    this.fotoUrl,
    this.vehiculoId,
    this.vehiculoLabel,
    this.vehiculoMatricula,
  });

  String get fullName {
    final n = '$nombre $apellido'.trim();
    return n.isEmpty ? 'Conductor' : n;
  }

  String get initials {
    final a = nombre.trim().isNotEmpty ? nombre.trim()[0] : '';
    final b = apellido.trim().isNotEmpty ? apellido.trim()[0] : '';
    final s = '$a$b'.toUpperCase();
    return s.isEmpty ? '?' : s;
  }

  String get statusLabel {
    switch (conductorEstado.toLowerCase()) {
      case 'en_ruta':
        return 'En ruta';
      case 'descanso':
        return 'Descanso';
      case 'inactivo':
        return 'Inactivo';
      case 'disponible':
      default:
        return activo ? 'Disponible' : 'Inactivo';
    }
  }

  String get licenseDisplay {
    if (licencia == null || licencia!.isEmpty) return '—';
    if (tipoLicencia != null && tipoLicencia!.isNotEmpty) {
      return '$licencia · $tipoLicencia';
    }
    return licencia!;
  }

  String get vehicleDisplay {
    if (vehiculoLabel != null && vehiculoLabel!.trim().isNotEmpty) {
      return vehiculoLabel!;
    }
    if (vehiculoMatricula != null && vehiculoMatricula!.isNotEmpty) {
      return vehiculoMatricula!;
    }
    return 'Sin vehículo asignado';
  }

  DriverProfile copyWith({
    String? nombre,
    String? apellido,
    String? email,
    String? telefono,
    String? fotoUrl,
  }) {
    return DriverProfile(
      usuarioId: usuarioId,
      conductorId: conductorId,
      nombre: nombre ?? this.nombre,
      apellido: apellido ?? this.apellido,
      email: email ?? this.email,
      telefono: telefono ?? this.telefono,
      activo: activo,
      rolNombre: rolNombre,
      empresaId: empresaId,
      empresaNombre: empresaNombre,
      licencia: licencia,
      tipoLicencia: tipoLicencia,
      vencimientoLicencia: vencimientoLicencia,
      conductorEstado: conductorEstado,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      vehiculoId: vehiculoId,
      vehiculoLabel: vehiculoLabel,
      vehiculoMatricula: vehiculoMatricula,
    );
  }
}
