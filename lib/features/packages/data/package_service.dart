import 'package:flutter/foundation.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/features/packages/domain/package.dart';

class PackageService {
  static PackageService? _instance;
  static PackageService get instance => _instance ??= PackageService._();
  PackageService._();

  final _client = SupabaseConfig.client;

  Future<List<Package>> fetchPackagesForTrip(String tripId) async {
    final bridgeData = await _client
        .from('operations_viajes_paquetes')
        .select('paquete_id')
        .eq('viaje_id', tripId)
        .filter('deleted_at', 'is', null);

    final packageIds = (bridgeData as List)
        .map((e) => e['paquete_id'] as String?)
        .where((id) => id != null && id.isNotEmpty)
        .cast<String>()
        .toList();

    if (packageIds.isEmpty) return [];

    return _fetchPackagesByIds(packageIds);
  }

  Future<List<Package>> fetchAllPackages(String empresaId) async {
    final data = await _client
        .from(SupabaseConfig.viewPaquetesCompleto)
        .select()
        .eq('empresa_id', empresaId);

    return _buildPackages(data as List);
  }

  Future<List<Package>> _fetchPackagesByIds(List<String> ids) async {
    final orClauses = ids.map((id) => 'id.eq.$id').join(',');
    final data = await _client
        .from(SupabaseConfig.viewPaquetesCompleto)
        .select()
        .or(orClauses);

    return _buildPackages(data as List);
  }

  Future<List<Package>> _buildPackages(List packagesData) async {
    final addressIds = packagesData
        .where((p) => p['direccion_destino'] != null)
        .map((p) => p['direccion_destino'] as String)
        .where((id) => id.isNotEmpty)
        .toList();

    final Map<String, Map<String, dynamic>> addressMap = {};
    if (addressIds.isNotEmpty) {
      try {
        final addrClauses = addressIds.map((id) => 'id.eq.$id').join(',');
        final addressData = await _client
            .from('customers_direcciones')
            .select('id, direccion, ciudad, provincia')
            .or(addrClauses);

        for (final addr in addressData) {
          addressMap[addr['id'] as String] = addr;
        }
      } catch (e) {
        debugPrint('PackageService: error loading addresses: $e');
      }
    }

    return packagesData.map((p) {
      final addr = p['direccion_destino'] != null
          ? addressMap[p['direccion_destino'] as String]
          : null;
      return _mapToPackage(p, addr);
    }).toList();
  }

  Package _mapToPackage(Map<String, dynamic> p, Map<String, dynamic>? addr) {
    final statusName = (p['estado_nombre'] as String?) ?? '';
    final prioridad = (p['prioridad'] as String?) ?? 'normal';

    String addressText = '';
    if (addr != null) {
      addressText = addr['direccion'] as String? ?? '';
      final ciudad = addr['ciudad'] as String?;
      if (ciudad != null && ciudad.isNotEmpty) {
        addressText =
            addressText.isNotEmpty ? '$addressText, $ciudad' : ciudad;
      }
    }

    final rawWeight = p['peso'];
    final weight = rawWeight != null
        ? '${(rawWeight as num).toStringAsFixed(1)} kg'
        : 'N/A';

    return Package(
      id: p['id'] as String,
      trackingNumber: (p['tracking_number'] as String?) ?? '',
      recipientName: p['destinatario_nombre'] as String?,
      address: addressText.isNotEmpty ? addressText : null,
      status: _mapStatus(statusName),
      priority: _mapPriority(prioridad),
      weight: weight,
      notes: p['contenido'] as String?,
      senderName: p['remitente_nombre'] as String?,
      requiresSignature: p['requiere_firma'] as bool? ?? false,
      requiresOtp: p['requiere_otp'] as bool? ?? false,
      declaredValue: (p['valor_declarado'] as num?)?.toDouble(),
      type: p['tipo'] as String?,
      isFragile: p['fragil'] as bool? ?? false,
      estimatedDeliveryDate: p['fecha_entrega_estimada'] != null
          ? DateTime.tryParse(p['fecha_entrega_estimada'] as String)
          : null,
      actualDeliveryDate: p['fecha_entrega_real'] != null
          ? DateTime.tryParse(p['fecha_entrega_real'] as String)
          : null,
    );
  }

  PackageStatus _mapStatus(String statusName) {
    switch (statusName.toLowerCase()) {
      case 'en tránsito':
      case 'en_transito':
      case 'en ruta':
      case 'ruta':
        return PackageStatus.inTransit;
      case 'entregado':
      case 'completado':
        return PackageStatus.delivered;
      default:
        return PackageStatus.pending;
    }
  }

  PackagePriority _mapPriority(String prioridad) {
    switch (prioridad.toLowerCase()) {
      case 'urgente':
        return PackagePriority.urgent;
      case 'alta':
        return PackagePriority.high;
      case 'baja':
        return PackagePriority.low;
      default:
        return PackagePriority.normal;
    }
  }
}
