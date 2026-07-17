import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tracking_system_app/core/config/constants.dart';
import 'package:tracking_system_app/features/settings/domain/app_settings.dart';
import 'package:tracking_system_app/features/settings/domain/settings_provider.dart';
import 'package:tracking_system_app/features/sync/domain/sync_engine.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final settings = ref.watch(settingsProvider);
    final pendingOps = ref.watch(pendingSyncCountProvider);
    final syncStatus = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          _sectionHeader('Apariencia', colorScheme, theme),
          _card(
            colorScheme,
            children: [
              ListTile(
                leading: Icon(
                  settings.themeMode == ThemeMode.dark
                      ? Icons.dark_mode
                      : settings.themeMode == ThemeMode.light
                          ? Icons.light_mode
                          : Icons.brightness_auto,
                  color: colorScheme.primary,
                ),
                title: const Text('Tema'),
                subtitle: Text(
                  settings.themeLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
                onTap: () => _pickTheme(context, ref, settings.themeMode),
              ),
              _divider(colorScheme),
              SwitchListTile(
                secondary: Icon(
                  Icons.screen_lock_portrait_outlined,
                  color: colorScheme.primary,
                ),
                title: const Text('Pantalla siempre activa'),
                subtitle: Text(
                  settings.keepScreenOn
                      ? 'Preferencia guardada (para tracking en ruta)'
                      : 'La pantalla puede apagarse con el sistema',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: settings.keepScreenOn,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).setKeepScreenOn(v),
              ),
            ],
          ),
          _sectionHeader('Idioma', colorScheme, theme),
          _card(
            colorScheme,
            children: [
              ListTile(
                leading: Icon(Icons.language, color: colorScheme.primary),
                title: const Text('Idioma de la app'),
                subtitle: Text(
                  settings.languageLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
                onTap: () => _pickLanguage(context, ref, settings.languageCode),
              ),
            ],
          ),
          _sectionHeader('Notificaciones', colorScheme, theme),
          _card(
            colorScheme,
            children: [
              SwitchListTile(
                secondary: Icon(
                  Icons.notifications_outlined,
                  color: colorScheme.primary,
                ),
                title: const Text('Notificaciones push'),
                subtitle: Text(
                  settings.notificationsEnabled
                      ? 'Alertas locales activadas'
                      : 'Notificaciones desactivadas en la app',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: settings.notificationsEnabled,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .setNotificationsEnabled(v),
              ),
              _divider(colorScheme),
              SwitchListTile(
                secondary: Icon(
                  Icons.route_outlined,
                  color: colorScheme.primary,
                ),
                title: const Text('Alertas de viaje'),
                subtitle: Text(
                  settings.tripAlertsEnabled
                      ? 'Paradas, entregas e incidencias'
                      : 'Sin alertas de viaje',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                value: settings.tripAlertsEnabled,
                onChanged: settings.notificationsEnabled
                    ? (v) => ref
                        .read(settingsProvider.notifier)
                        .setTripAlertsEnabled(v)
                    : null,
              ),
              _divider(colorScheme),
              ListTile(
                leading: Icon(
                  Icons.notifications_active_outlined,
                  color: colorScheme.primary,
                ),
                title: const Text('Centro de notificaciones'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
                onTap: () => context.push('/notifications'),
              ),
            ],
          ),
          _sectionHeader('Datos y sincronización', colorScheme, theme),
          _card(
            colorScheme,
            children: [
              ListTile(
                leading: Icon(Icons.sync, color: colorScheme.primary),
                title: const Text('Centro de sincronización'),
                subtitle: Text(
                  pendingOps > 0
                      ? '$pendingOps pendiente${pendingOps == 1 ? '' : 's'}'
                      : _syncSubtitle(syncStatus, settings),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
                onTap: () => context.push('/sync'),
              ),
              _divider(colorScheme),
              ListTile(
                leading: Icon(Icons.cloud_sync_outlined, color: colorScheme.primary),
                title: const Text('Sincronizar ahora'),
                subtitle: Text(
                  settings.lastSyncAt != null
                      ? 'Última: ${_formatWhen(settings.lastSyncAt!)}'
                      : 'Forzar actualización del viaje y cola offline',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => _syncNow(context, ref),
              ),
              _divider(colorScheme),
              ListTile(
                leading: Icon(Icons.restart_alt, color: colorScheme.primary),
                title: const Text('Restablecer preferencias'),
                subtitle: Text(
                  'Tema, notificaciones e idioma a valores por defecto',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                onTap: () => _resetPrefs(context, ref),
              ),
            ],
          ),
          _sectionHeader('Cuenta', colorScheme, theme),
          _card(
            colorScheme,
            children: [
              ListTile(
                leading: Icon(Icons.person_outline, color: colorScheme.primary),
                title: const Text('Mi perfil'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
                onTap: () => context.push('/profile'),
              ),
              _divider(colorScheme),
              ListTile(
                leading: Icon(Icons.lock_outline, color: colorScheme.primary),
                title: const Text('Cambiar contraseña'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
                onTap: () => context.push('/profile'),
              ),
            ],
          ),
          _sectionHeader('Privacidad y legal', colorScheme, theme),
          _card(
            colorScheme,
            children: [
              ListTile(
                leading: Icon(Icons.lock_outline, color: colorScheme.primary),
                title: const Text('Política de privacidad'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
                onTap: () => _showInfoDialog(
                  context,
                  title: 'Política de privacidad',
                  body:
                      'Routio procesa ubicación, entregas e incidencias para la operación logística de tu empresa. '
                      'Los datos se almacenan en la infraestructura de la empresa (Supabase) y no se venden a terceros. '
                      'Para ejercer derechos de acceso o eliminación, contactá a tu administrador.',
                ),
              ),
              _divider(colorScheme),
              ListTile(
                leading:
                    Icon(Icons.description_outlined, color: colorScheme.primary),
                title: const Text('Términos de uso'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
                onTap: () => _showInfoDialog(
                  context,
                  title: 'Términos de uso',
                  body:
                      'El uso de la app del conductor está sujeto a las políticas de tu empresa. '
                      'Debés usar la app solo para operaciones asignadas y mantener la sesión segura. '
                      'El mal uso de datos o evidencias puede ser auditado.',
                ),
              ),
              _divider(colorScheme),
              ListTile(
                leading: Icon(Icons.delete_outline, color: colorScheme.error),
                title: Text(
                  'Eliminar cuenta',
                  style: TextStyle(color: colorScheme.error),
                ),
                onTap: () => _showInfoDialog(
                  context,
                  title: 'Eliminar cuenta',
                  body:
                      'La eliminación de cuentas se gestiona desde la oficina (soft delete en core_usuarios). '
                      'Contactá a tu administrador para desactivar el acceso. '
                      'Desde la app podés cerrar sesión en cualquier momento.',
                ),
              ),
            ],
          ),
          _sectionHeader('Acerca de', colorScheme, theme),
          _card(
            colorScheme,
            children: [
              ListTile(
                leading: Icon(Icons.info_outline, color: colorScheme.primary),
                title: const Text('Acerca de Routio'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
                onTap: () => _showAbout(context, settings),
              ),
              _divider(colorScheme),
              ListTile(
                leading: Icon(Icons.help_outline, color: colorScheme.primary),
                title: const Text('Ayuda y soporte'),
                trailing: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
                onTap: () => _showInfoDialog(
                  context,
                  title: 'Ayuda y soporte',
                  body:
                      'Para problemas de viaje, entregas o acceso, contactá a tu operador o administrador de empresa. '
                      'Si hay operaciones pendientes sin red, usá el Centro de sincronización cuando recuperes conexión.',
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Column(
              children: [
                Icon(
                  Icons.navigation_rounded,
                  size: 44,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  AppConstants.appName,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${AppConstants.appTagline} · ${settings.versionLabel}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '© 2026 Routio',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => _confirmLogout(context, ref),
              icon: Icon(Icons.logout, color: colorScheme.error),
              label: Text(
                'Cerrar sesión',
                style: TextStyle(color: colorScheme.error),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: BorderSide(color: colorScheme.error),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(
    String title,
    ColorScheme colorScheme,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _card(ColorScheme colorScheme, {required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider(ColorScheme colorScheme) {
    return Divider(
      height: 1,
      indent: 56,
      color: colorScheme.outlineVariant,
    );
  }

  String _syncSubtitle(SyncStatus status, AppSettings settings) {
    switch (status) {
      case SyncStatus.syncing:
        return 'Sincronizando…';
      case SyncStatus.offline:
        return 'Sin conexión';
      case SyncStatus.error:
        return 'Error de sincronización';
      case SyncStatus.idle:
        if (settings.lastSyncAt != null) {
          return 'Última sync: ${_formatWhen(settings.lastSyncAt!)}';
        }
        return 'Todo al día';
    }
  }

  String _formatWhen(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'ahora';
    if (diff.inHours < 1) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    return '${local.day}/${local.month}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickTheme(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    final selected = await showModalBottomSheet<ThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.brightness_auto),
                title: const Text('Sistema'),
                trailing: current == ThemeMode.system
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, ThemeMode.system),
              ),
              ListTile(
                leading: const Icon(Icons.light_mode),
                title: const Text('Claro'),
                trailing: current == ThemeMode.light
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(ctx, ThemeMode.light),
              ),
              ListTile(
                leading: const Icon(Icons.dark_mode),
                title: const Text('Oscuro'),
                trailing:
                    current == ThemeMode.dark ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, ThemeMode.dark),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      await ref.read(settingsProvider.notifier).setThemeMode(selected);
    }
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.translate),
                title: const Text('Español'),
                subtitle: const Text('Idioma principal de Routio'),
                trailing: current == 'es' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, 'es'),
              ),
              ListTile(
                leading: const Icon(Icons.translate),
                title: const Text('English'),
                subtitle: const Text('Próximamente (se guarda la preferencia)'),
                trailing: current == 'en' ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, 'en'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (selected != null) {
      await ref.read(settingsProvider.notifier).setLanguage(selected);
      if (!context.mounted) return;
      if (selected == 'en') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Preferencia guardada. La UI completa en inglés llegará pronto.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Sincronizando…')),
    );
    try {
      await ref.read(settingsProvider.notifier).syncNow();
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Sincronización completada'),
          backgroundColor: Color(0xFF176351),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo sincronizar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _resetPrefs(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restablecer preferencias'),
        content: const Text(
          'Se restablecerán tema, idioma y notificaciones. No se cierra la sesión.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restablecer'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(settingsProvider.notifier).resetPreferences();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Preferencias restablecidas')),
    );
  }

  void _showInfoDialog(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context, AppSettings settings) {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: settings.versionLabel,
      applicationIcon: Icon(
        Icons.navigation_rounded,
        size: 40,
        color: Theme.of(context).colorScheme.primary,
      ),
      children: [
        const SizedBox(height: 12),
        const Text(
          'App del conductor para gestión de viajes, entregas, '
          'tracking GPS e incidencias. Parte de la plataforma Routio.',
        ),
      ],
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Seguro que quieres salir de la app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Salir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(settingsProvider.notifier).logout();
      if (!context.mounted) return;
      context.go('/login');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cerrar sesión: $e')),
      );
    }
  }
}
