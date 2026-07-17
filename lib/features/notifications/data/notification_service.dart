import 'package:flutter/foundation.dart';
import 'package:tracking_system_app/core/config/constants.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/core/pagination/page_result.dart';
import 'package:tracking_system_app/core/pagination/paged_scroll_mixin.dart';
import 'package:tracking_system_app/features/notifications/domain/app_notification.dart';

class NotificationService {
  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._();
  NotificationService._();

  final _client = SupabaseConfig.client;

  Future<({String? usuarioId, String? empresaId, String? conductorId})>
      _resolveContext() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return (usuarioId: null, empresaId: null, conductorId: null);
    }
    try {
      final core = await _client
          .from('core_usuarios')
          .select('id, empresa_id')
          .eq('auth_user_id', user.id)
          .filter('deleted_at', 'is', null)
          .maybeSingle();
      if (core == null) {
        return (usuarioId: null, empresaId: null, conductorId: null);
      }
      final usuarioId = core['id'] as String?;
      final empresaId = core['empresa_id'] as String?;
      String? conductorId;
      if (usuarioId != null) {
        final cond = await _client
            .from('fleet_conductores')
            .select('id')
            .eq('usuario_id', usuarioId)
            .filter('deleted_at', 'is', null)
            .maybeSingle();
        conductorId = cond?['id'] as String?;
      }
      return (
        usuarioId: usuarioId,
        empresaId: empresaId,
        conductorId: conductorId,
      );
    } catch (e) {
      debugPrint('NotificationService context: $e');
      return (usuarioId: null, empresaId: null, conductorId: null);
    }
  }

  /// Página de notificaciones desde DB (eventos de viaje + communication_notificaciones).
  Future<PageResult<AppNotification>> fetchPage({
    int page = 0,
    int pageSize = AppConstants.notificationsPageSize,
  }) async {
    final ctx = await _resolveContext();
    if (ctx.empresaId == null) {
      return PageResult.empty(page: page, pageSize: pageSize);
    }

    final range = PageRange.of(page, pageSize: pageSize);
    final items = <AppNotification>[];

    // 1) Eventos de viajes del conductor (o de la empresa si no es conductor)
    try {
      List<String> tripIds = [];
      if (ctx.conductorId != null) {
        final links = await _client
            .from('operations_viajes_conductores')
            .select('viaje_id')
            .eq('conductor_id', ctx.conductorId!)
            .filter('deleted_at', 'is', null)
            .limit(80);
        tripIds = (links as List)
            .map((e) => e['viaje_id'] as String?)
            .whereType<String>()
            .toList();
      }

      if (tripIds.isNotEmpty) {
        final events = await _client
            .from('operations_viajes_eventos')
            .select(
              'id, tipo, descripcion, metadata, created_at, viaje_id, '
              'viaje:operations_viajes(codigo)',
            )
            .inFilter('viaje_id', tripIds.take(40).toList())
            .filter('deleted_at', 'is', null)
            .order('created_at', ascending: false)
            .range(range.from, range.to);

        for (final e in events as List) {
          items.add(_mapEvento(Map<String, dynamic>.from(e as Map)));
        }
      } else if (ctx.empresaId != null) {
        // Fallback: eventos de viajes de la empresa (últimos)
        final events = await _client
            .from('operations_viajes_eventos')
            .select(
              'id, tipo, descripcion, metadata, created_at, viaje_id, '
              'viaje:operations_viajes!inner(codigo, empresa_id)',
            )
            .eq('viaje.empresa_id', ctx.empresaId!)
            .filter('deleted_at', 'is', null)
            .order('created_at', ascending: false)
            .range(range.from, range.to);

        for (final e in events as List) {
          items.add(_mapEvento(Map<String, dynamic>.from(e as Map)));
        }
      }
    } catch (e) {
      debugPrint('NotificationService eventos: $e');
      // Fallback sin join
      try {
        if (ctx.conductorId != null) {
          final links = await _client
              .from('operations_viajes_conductores')
              .select('viaje_id')
              .eq('conductor_id', ctx.conductorId!)
              .filter('deleted_at', 'is', null)
              .limit(40);
          final tripIds = (links as List)
              .map((e) => e['viaje_id'] as String?)
              .whereType<String>()
              .toList();
          if (tripIds.isNotEmpty) {
            final events = await _client
                .from('operations_viajes_eventos')
                .select('id, tipo, descripcion, metadata, created_at, viaje_id')
                .inFilter('viaje_id', tripIds)
                .filter('deleted_at', 'is', null)
                .order('created_at', ascending: false)
                .range(range.from, range.to);
            for (final e in events as List) {
              items.add(_mapEvento(Map<String, dynamic>.from(e as Map)));
            }
          }
        }
      } catch (e2) {
        debugPrint('NotificationService eventos fallback: $e2');
      }
    }

    // 2) communication_notificaciones del usuario (si existe y hay filas)
    if (page == 0 && ctx.usuarioId != null) {
      try {
        final rows = await _client
            .from('communication_notificaciones')
            .select(
              'id, titulo, mensaje, tipo, leido, created_at, fecha_leido',
            )
            .eq('usuario_id', ctx.usuarioId!)
            .filter('deleted_at', 'is', null)
            .order('created_at', ascending: false)
            .limit(pageSize);

        for (final r in rows as List) {
          items.add(_mapComms(Map<String, dynamic>.from(r as Map)));
        }
      } catch (e) {
        debugPrint('NotificationService comms: $e');
      }
    }

    // Deduplicar por id y ordenar
    final byId = <String, AppNotification>{};
    for (final n in items) {
      byId[n.id] = n;
    }
    final sorted = byId.values.toList()
      ..sort((a, b) => b.time.compareTo(a.time));

    // Página ya viene del range de eventos; hasMore si trajo pageSize
    final hasMore = sorted.length >= pageSize ||
        (items.where((i) => i.source == 'evento').length >= pageSize);

    return PageResult(
      items: sorted,
      page: page,
      pageSize: pageSize,
      hasMore: hasMore,
    );
  }

  Future<void> markAsRead(AppNotification n) async {
    if (n.source != 'notificacion') return;
    try {
      await _client.from('communication_notificaciones').update({
        'leido': true,
        'fecha_leido': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', n.id);
    } catch (e) {
      debugPrint('markAsRead: $e');
    }
  }

  Future<void> markAllCommsAsRead(String usuarioId) async {
    try {
      await _client.from('communication_notificaciones').update({
        'leido': true,
        'fecha_leido': DateTime.now().toUtc().toIso8601String(),
      }).eq('usuario_id', usuarioId).eq('leido', false);
    } catch (e) {
      debugPrint('markAllCommsAsRead: $e');
    }
  }

  AppNotification _mapEvento(Map<String, dynamic> e) {
    final tipo = (e['tipo'] as String?) ?? 'sistema';
    final viaje = e['viaje'];
    String? codigo;
    if (viaje is Map) {
      codigo = viaje['codigo'] as String?;
    }
    final meta = e['metadata'];
    final pkgs = meta is Map
        ? (meta['packages_updated'] ?? meta['packages_delivered'])
        : null;

    final mapped = _mapTipo(tipo);
    String title;
    String message;

    switch (tipo) {
      case 'entrega':
        title = 'Entrega registrada';
        message = [
          if (codigo != null) codigo,
          e['descripcion'] as String? ?? 'Entrega completada',
          if (pkgs != null) '$pkgs paquete(s)',
        ].join(' · ');
        break;
      case 'otp_verificado':
        title = 'OTP verificado';
        message = [
          if (codigo != null) codigo,
          e['descripcion'] as String? ?? 'Código confirmado',
        ].join(' · ');
        break;
      case 'viaje_programado':
        title = 'Viaje programado';
        message = codigo != null
            ? '$codigo · listo para operar'
            : (e['descripcion'] as String? ?? 'Viaje programado');
        break;
      case 'conductor_asignado':
        title = 'Conductor asignado';
        message = [
          if (codigo != null) codigo,
          e['descripcion'] as String? ?? 'Asignación actualizada',
        ].join(' · ');
        break;
      case 'vehiculo_asignado':
        title = 'Vehículo asignado';
        message = [
          if (codigo != null) codigo,
          e['descripcion'] as String? ?? 'Vehículo del viaje',
        ].join(' · ');
        break;
      case 'cambio_estado':
        title = 'Estado del viaje';
        message = [
          if (codigo != null) codigo,
          e['descripcion'] as String? ?? tipo,
        ].join(' · ');
        break;
      default:
        title = e['descripcion'] as String? ?? tipo.replaceAll('_', ' ');
        message = codigo ?? tipo;
    }

    final created = e['created_at'] != null
        ? DateTime.tryParse(e['created_at'] as String)?.toLocal()
        : null;

    final age = created != null
        ? DateTime.now().difference(created)
        : const Duration(days: 2);

    return AppNotification(
      id: e['id'] as String,
      type: mapped,
      title: title,
      message: message,
      time: created ?? DateTime.now(),
      source: 'evento',
      rawTipo: tipo,
      isRead: age.inHours >= 24,
    );
  }

  AppNotification _mapComms(Map<String, dynamic> r) {
    final tipo = (r['tipo'] as String?) ?? 'info';
    return AppNotification(
      id: r['id'] as String,
      type: _mapTipo(tipo),
      title: (r['titulo'] as String?) ?? 'Notificación',
      message: (r['mensaje'] as String?) ?? '',
      time: r['created_at'] != null
          ? (DateTime.tryParse(r['created_at'] as String)?.toLocal() ??
              DateTime.now())
          : DateTime.now(),
      source: 'notificacion',
      rawTipo: tipo,
      isRead: r['leido'] as bool? ?? false,
    );
  }

  NotificationType _mapTipo(String tipo) {
    final t = tipo.toLowerCase();
    if (t.contains('entrega') || t.contains('delivery') || t == 'otp_verificado') {
      return NotificationType.delivery;
    }
    if (t.contains('incid') || t.contains('alert') || t.contains('fall')) {
      return NotificationType.incident;
    }
    if (t.contains('viaje') ||
        t.contains('conductor') ||
        t.contains('vehiculo') ||
        t.contains('parada')) {
      return NotificationType.trip;
    }
    if (t == 'error' || t == 'warning') {
      return NotificationType.alert;
    }
    return NotificationType.system;
  }
}
