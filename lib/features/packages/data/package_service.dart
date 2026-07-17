import 'package:flutter/foundation.dart';
import 'package:tracking_system_app/core/config/constants.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/core/pagination/page_result.dart';
import 'package:tracking_system_app/core/pagination/paged_scroll_mixin.dart';
import 'package:tracking_system_app/features/packages/domain/package.dart';
import 'package:tracking_system_app/features/sync/data/local_cache.dart';

class PackageService {
  static PackageService? _instance;
  static PackageService get instance => _instance ??= PackageService._();
  PackageService._();

  final _client = SupabaseConfig.client;

  Future<String?> _resolveEmpresaId() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final core = await _client
          .from('core_usuarios')
          .select('empresa_id')
          .eq('auth_user_id', user.id)
          .filter('deleted_at', 'is', null)
          .maybeSingle();
      return core?['empresa_id'] as String?;
    } catch (e) {
      debugPrint('PackageService._resolveEmpresaId: $e');
      return null;
    }
  }

  Future<Map<String, String>> _loadEstadoMap(Iterable<String> estadoIds) async {
    final ids = estadoIds.where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final estados = await _client
          .from('shipping_estados_envio')
          .select('id,codigo,nombre')
          .inFilter('id', ids);
      final map = <String, String>{};
      for (final e in estados as List) {
        final id = e['id'] as String?;
        if (id == null) continue;
        map[id] =
            (e['nombre'] as String?) ?? (e['codigo'] as String?) ?? '';
      }
      return map;
    } catch (e) {
      debugPrint('PackageService._loadEstadoMap: $e');
      return {};
    }
  }

  Future<Map<String, String>> _loadClienteMap(Iterable<String> clienteIds) async {
    final ids = clienteIds.where((e) => e.isNotEmpty).toSet().toList();
    if (ids.isEmpty) return {};
    try {
      final clientes = await _client
          .from('customers_clientes')
          .select('id,nombre')
          .inFilter('id', ids);
      final map = <String, String>{};
      for (final c in clientes as List) {
        map[c['id'] as String] = c['nombre'] as String? ?? '';
      }
      return map;
    } catch (e) {
      debugPrint('PackageService clientes: $e');
      return {};
    }
  }

  Future<List<Package>> _mapRows(List rows) async {
    if (rows.isEmpty) return [];
    final estadoMap = await _loadEstadoMap(
      rows.map((p) => p['estado_actual'] as String? ?? ''),
    );
    final clienteMap = await _loadClienteMap(
      rows.map((p) => p['cliente_id'] as String? ?? ''),
    );

    return rows.map((p) {
      final map = Map<String, dynamic>.from(p as Map);
      final estId = map['estado_actual'] as String?;
      map['estado_nombre'] = estId != null ? (estadoMap[estId] ?? '') : '';
      final clienteId = map['cliente_id'] as String?;
      if (clienteId != null && clienteMap.containsKey(clienteId)) {
        map['destinatario_nombre'] = clienteMap[clienteId];
      }
      return _mapToPackage(map);
    }).toList();
  }

  /// Página de inventario de la empresa (preferido para UI).
  Future<PageResult<Package>> fetchEmpresaPackagesPage({
    int page = 0,
    int pageSize = AppConstants.packagesPageSize,
    String? search,
  }) async {
    final empresaId = await _resolveEmpresaId();
    if (empresaId == null) {
      // Sin sesión de red: intentar cache genérica
      return _loadCachedPage(
        tripId: '',
        page: page,
        pageSize: pageSize,
        search: search,
      );
    }

    final range = PageRange.of(page, pageSize: pageSize);

    try {
      var query = _client
          .from('shipping_paquetes')
          .select(
            'id,tracking_number,peso,prioridad,contenido,requiere_firma,requiere_otp,'
            'tipo,fragil,valor_declarado,fecha_entrega_estimada,fecha_entrega_real,'
            'estado_actual,direccion_destino,cliente_id',
          )
          .eq('empresa_id', empresaId)
          .filter('deleted_at', 'is', null);

      final q = search?.trim();
      if (q != null && q.isNotEmpty) {
        query = query.or(
          'tracking_number.ilike.%$q%,contenido.ilike.%$q%',
        );
      }

      final data = await query
          .order('created_at', ascending: false)
          .range(range.from, range.to);

      final items = await _mapRows(data as List);
      if (page == 0 && (search == null || search.trim().isEmpty)) {
        await _persistPackages(items);
      }
      return PageResult(
        items: items,
        page: page,
        pageSize: range.pageSize,
        hasMore: items.length >= range.pageSize,
      );
    } catch (e, st) {
      debugPrint('fetchEmpresaPackagesPage: $e\n$st');
      return _loadCachedPage(
        tripId: '',
        page: page,
        pageSize: pageSize,
        search: search,
      );
    }
  }

  /// Página de paquetes del viaje: red si hay, snapshot local si no.
  Future<PageResult<Package>> fetchPackagesForTripPage(
    String tripId, {
    int page = 0,
    int pageSize = AppConstants.packagesPageSize,
    String? search,
  }) async {
    if (tripId.isEmpty) {
      return fetchEmpresaPackagesPage(
        page: page,
        pageSize: pageSize,
        search: search,
      );
    }

    try {
      final online = await fetchPackagesForTripPageOnline(
        tripId,
        page: page,
        pageSize: pageSize,
        search: search,
      );
      if (online.items.isNotEmpty || page > 0) {
        return online;
      }
      // Página 0 vacía en red: intentar cache (puede haber datos offline previos)
      final cached = await _loadCachedPage(
        tripId: tripId,
        page: page,
        pageSize: pageSize,
        search: search,
      );
      if (cached.items.isNotEmpty) return cached;
      return online;
    } catch (e) {
      debugPrint('fetchPackagesForTripPage offline fallback: $e');
      return _loadCachedPage(
        tripId: tripId,
        page: page,
        pageSize: pageSize,
        search: search,
      );
    }
  }

  /// Solo red (usado por SyncEngine al refrescar snapshot). Guarda cache al éxito.
  Future<PageResult<Package>> fetchPackagesForTripPageOnline(
    String tripId, {
    int page = 0,
    int pageSize = AppConstants.packagesPageSize,
    String? search,
  }) async {
    if (tripId.isEmpty) {
      return PageResult.empty(page: page, pageSize: pageSize);
    }

    final range = PageRange.of(page, pageSize: pageSize);
    final bridge = await _client
        .from('operations_viajes_paquetes')
        .select('paquete_id')
        .eq('viaje_id', tripId)
        .filter('deleted_at', 'is', null)
        .range(range.from, range.to);

    final packageIds = (bridge as List)
        .map((e) => e['paquete_id'] as String?)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    if (packageIds.isEmpty) {
      if (page == 0) {
        final empresa = await fetchEmpresaPackagesPage(
          page: page,
          pageSize: pageSize,
          search: search,
        );
        if (empresa.items.isNotEmpty) {
          await _persistPackages(empresa.items, tripId: tripId);
        }
        return empresa;
      }
      return PageResult.empty(page: page, pageSize: pageSize);
    }

    var items = await fetchPackagesByIdsWithEstado(packageIds);
    final q = search?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      items = items
          .where(
            (p) =>
                p.trackingNumber.toLowerCase().contains(q) ||
                (p.notes?.toLowerCase().contains(q) ?? false) ||
                (p.recipientName?.toLowerCase().contains(q) ?? false),
          )
          .toList();
    }

    // Primera página sin búsqueda: reemplazar snapshot
    if (page == 0 && (search == null || search.trim().isEmpty)) {
      await _persistPackages(items, tripId: tripId);
    }

    return PageResult(
      items: items,
      page: page,
      pageSize: pageSize,
      hasMore: packageIds.length >= pageSize,
    );
  }

  Future<void> _persistPackages(List<Package> items, {String? tripId}) async {
    try {
      final cache = await LocalCache.create();
      await cache.savePackages(items, tripId: tripId);
    } catch (e) {
      debugPrint('PackageService persist: $e');
    }
  }

  Future<PageResult<Package>> _loadCachedPage({
    required String tripId,
    required int page,
    required int pageSize,
    String? search,
  }) async {
    try {
      final cache = await LocalCache.create();
      var items = await cache.loadPackages(tripId: tripId);
      final q = search?.trim().toLowerCase();
      if (q != null && q.isNotEmpty) {
        items = items
            .where(
              (p) =>
                  p.trackingNumber.toLowerCase().contains(q) ||
                  (p.notes?.toLowerCase().contains(q) ?? false) ||
                  (p.recipientName?.toLowerCase().contains(q) ?? false),
            )
            .toList();
      }
      final from = page * pageSize;
      if (from >= items.length) {
        return PageResult.empty(page: page, pageSize: pageSize);
      }
      final to = (from + pageSize).clamp(0, items.length);
      final slice = items.sublist(from, to);
      return PageResult(
        items: slice,
        page: page,
        pageSize: pageSize,
        hasMore: to < items.length,
        total: items.length,
      );
    } catch (e) {
      debugPrint('PackageService cache load: $e');
      return PageResult.empty(page: page, pageSize: pageSize);
    }
  }

  Future<List<String>> fetchPackageIdsForTrip(String tripId) async {
    // Solo primera página de IDs (entrega / escaneo) — acotado
    final page = await fetchPackagesForTripPage(
      tripId,
      page: 0,
      pageSize: AppConstants.packagesPageSize,
    );
    return page.items.map((p) => p.id).toList();
  }

  Future<List<Package>> fetchPackagesByIdsWithEstado(List<String> ids) async {
    if (ids.isEmpty) return [];
    // Nunca más de maxPageSize IDs por request
    final limited = ids.take(AppConstants.maxPageSize).toList();
    try {
      final data = await _client
          .from('shipping_paquetes')
          .select(
            'id,tracking_number,peso,prioridad,contenido,requiere_firma,requiere_otp,'
            'tipo,fragil,valor_declarado,fecha_entrega_estimada,fecha_entrega_real,'
            'estado_actual,direccion_destino,cliente_id',
          )
          .inFilter('id', limited);

      return _mapRows(data as List);
    } catch (e) {
      debugPrint('fetchPackagesByIdsWithEstado: $e');
      try {
        final orClauses = limited.map((id) => 'id.eq.$id').join(',');
        final data = await _client
            .from('shipping_paquetes')
            .select(
              'id,tracking_number,peso,prioridad,contenido,requiere_firma,requiere_otp,'
              'tipo,fragil,valor_declarado,fecha_entrega_estimada,fecha_entrega_real,'
              'estado_actual,direccion_destino,cliente_id',
            )
            .or(orClauses);
        return _mapRows(data as List);
      } catch (e2) {
        debugPrint('fetchPackagesByIdsWithEstado OR: $e2');
        return [];
      }
    }
  }

  /// Compat: primera página del inventario.
  Future<List<Package>> fetchEmpresaPackages() async {
    final page = await fetchEmpresaPackagesPage(page: 0);
    return page.items;
  }

  Future<List<Package>> fetchPackagesForTrip(String tripId) async {
    final page = await fetchPackagesForTripPage(tripId, page: 0);
    return page.items;
  }

  Future<List<Package>> fetchAllPackages(String empresaId) async {
    return fetchEmpresaPackages();
  }

  Package _mapToPackage(Map<String, dynamic> p) {
    final statusName = (p['estado_nombre'] as String?)
        ?? (p['estado_codigo'] as String?)
        ?? '';
    final prioridad = (p['prioridad'] as String?) ?? 'normal';

    final rawWeight = p['peso'];
    final weight = rawWeight != null
        ? '${(rawWeight as num).toStringAsFixed(1)} kg'
        : '—';

    return Package(
      id: p['id'] as String,
      trackingNumber: (p['tracking_number'] as String?) ?? '',
      recipientName: p['destinatario_nombre'] as String?
          ?? p['cliente_nombre'] as String?,
      address: null,
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
    final s = statusName.toLowerCase().trim();
    if (s.contains('entreg')) return PackageStatus.delivered;
    if (s.contains('ruta') ||
        s.contains('reparto') ||
        s.contains('tránsito') ||
        s.contains('transito') ||
        s.contains('despach')) {
      return PackageStatus.inTransit;
    }
    return PackageStatus.pending;
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
