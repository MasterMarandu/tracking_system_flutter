import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // TODO: Replace with your Supabase credentials
  static const String supabaseUrl = 'https://kodeainncvxncxdbihwr.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtvZGVhaW5uY3Z4bmN4ZGJpaHdyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM1MTcyNDcsImV4cCI6MjA5OTA5MzI0N30.radeL6husEzum6-QmdzM_igA581tC1h2fE4GhYhv9oE';
  
  // Storage Buckets
  static const String bucketAvatars = 'avatars';
  static const String bucketDocuments = 'documents';
  static const String bucketSignatures = 'signatures';
  static const String bucketPhotos = 'photos';
  static const String bucketQrCodes = 'qr-codes';
  
  // Table Names
  static const String tableUsuarios = 'core_usuarios';
  static const String tableEmpresas = 'core_empresas';
  static const String tableSucursales = 'core_sucursales';
  static const String tableRoles = 'core_roles';
  static const String tablePermisos = 'core_permisos';
  static const String tableConfiguraciones = 'core_configuraciones';
  
  static const String tableDispositivosGps = 'fleet_dispositivos_gps';
  static const String tableVehiculos = 'fleet_vehiculos';
  static const String tableRemolques = 'fleet_remolques';
  static const String tableConductores = 'fleet_conductores';
  static const String tableMantenimientos = 'fleet_mantenimientos';
  
  static const String tableClientes = 'customers_clientes';
  static const String tableDirecciones = 'customers_direcciones';
  static const String tableRemitentes = 'customers_remitentes';
  static const String tableDestinatarios = 'customers_destinatarios';
  
  static const String tableGeocercas = 'operations_geocercas';
  static const String tableRutas = 'operations_rutas';
  static const String tableParadas = 'operations_paradas';
  static const String tableViajes = 'operations_viajes';
  static const String tableCheckpoints = 'operations_checkpoints';
  
  static const String tableEstadosEnvio = 'shipping_estados_envio';
  static const String tablePaquetes = 'shipping_paquetes';
  static const String tableCargas = 'shipping_cargas';
  static const String tablePaquetesCargas = 'shipping_paquetes_cargas';
  static const String tableHistorialEstados = 'shipping_historial_estados';
  
  static const String tableTrackingGps = 'tracking_gps';
  static const String tableTrackingEventos = 'tracking_eventos';
  static const String tableTrackingAlertas = 'tracking_alertas';
  static const String tableTrackingSesiones = 'tracking_sesiones';
  
  static const String tableFirmas = 'delivery_firmas';
  static const String tableEntregas = 'delivery_entregas';
  static const String tableFotografias = 'delivery_fotografias';
  static const String tableIncidencias = 'delivery_incidencias';
  
  static const String tableChats = 'communication_chats';
  static const String tableChatMensajes = 'communication_chat_mensajes';
  static const String tableNotificaciones = 'communication_notificaciones';
  
  static const String tableAuditoria = 'audit_auditoria';
  static const String tableDocumentos = 'storage_documentos';
  
  // Realtime Channels
  static const String channelTracking = 'tracking';
  static const String channelMessages = 'messages';
  static const String channelNotifications = 'notifications';
  static const String channelTripUpdates = 'trip-updates';
  
  // RPC Functions
  static const String rpcGenerarTrackingNumber = 'generar_tracking_number';
  static const String rpcCalcularDistancia = 'calcular_distancia_km';
  static const String rpcGetDriverBootstrap = 'get_driver_bootstrap';
  
  // Views
  static const String viewPaquetesCompleto = 'v_paquetes_completo';
  static const String viewViajesActivos = 'v_viajes_activos';
  static const String viewUltimaPosicionGps = 'v_ultima_posicion_gps';
  
  static SupabaseClient get client => Supabase.instance.client;
  
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      realtimeClientOptions: const RealtimeClientOptions(
        eventsPerSecond: 2,
      ),
    );
  }
}
