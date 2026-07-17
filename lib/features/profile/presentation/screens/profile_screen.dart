import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tracking_system_app/features/profile/domain/driver_profile.dart';
import 'package:tracking_system_app/features/profile/domain/profile_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final asyncProfile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => ref.read(profileProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: asyncProfile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorBody(
          message: e.toString(),
          onRetry: () => ref.read(profileProvider.notifier).refresh(),
        ),
        data: (profile) {
          if (profile == null) {
            return _ErrorBody(
              message: 'No hay sesión activa',
              onRetry: () => ref.read(profileProvider.notifier).refresh(),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(profileProvider.notifier).refresh(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                children: [
                  _AvatarHeader(profile: profile, colorScheme: colorScheme),
                  const SizedBox(height: 12),
                  Text(
                    profile.fullName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    profile.rolNombre ?? 'Conductor',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StatusChip(label: profile.statusLabel, colorScheme: colorScheme),
                  const SizedBox(height: 28),
                  _InfoCard(profile: profile, theme: theme, colorScheme: colorScheme),
                  const SizedBox(height: 24),
                  _ActionButtons(
                    onEdit: () => _showEditSheet(context, ref, profile),
                    onChangePassword: () =>
                        _showChangePasswordSheet(context, ref),
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(height: 24),
                  _LogoutButton(
                    onLogout: () => _confirmLogout(context, ref),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
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
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
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
      await ref.read(profileProvider.notifier).logout();
      if (!context.mounted) return;
      context.go('/login');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cerrar sesión: $e')),
      );
    }
  }

  void _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    DriverProfile profile,
  ) {
    final nombreCtrl = TextEditingController(text: profile.nombre);
    final apellidoCtrl = TextEditingController(text: profile.apellido);
    final telefonoCtrl = TextEditingController(text: profile.telefono ?? '');
    var saving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Editar perfil',
                      style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nombreCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: apellidoCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Apellido',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: telefonoCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'El correo y la licencia se gestionan desde la oficina.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              if (nombreCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('El nombre es obligatorio'),
                                  ),
                                );
                                return;
                              }
                              setSheet(() => saving = true);
                              try {
                                await ref
                                    .read(profileProvider.notifier)
                                    .updateProfile(
                                      nombre: nombreCtrl.text.trim(),
                                      apellido: apellidoCtrl.text.trim(),
                                      telefono: telefonoCtrl.text.trim(),
                                    );
                                if (!ctx.mounted) return;
                                Navigator.of(ctx).pop();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Perfil actualizado'),
                                    backgroundColor: Color(0xFF176351),
                                  ),
                                );
                              } catch (e) {
                                setSheet(() => saving = false);
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Guardar cambios'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      nombreCtrl.dispose();
      apellidoCtrl.dispose();
      telefonoCtrl.dispose();
    });
  }

  void _showChangePasswordSheet(BuildContext context, WidgetRef ref) {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var saving = false;
    var obscure1 = true;
    var obscure2 = true;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Cambiar contraseña',
                      style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: passCtrl,
                      obscureText: obscure1,
                      decoration: InputDecoration(
                        labelText: 'Nueva contraseña',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscure1
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setSheet(() => obscure1 = !obscure1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmCtrl,
                      obscureText: obscure2,
                      decoration: InputDecoration(
                        labelText: 'Confirmar contraseña',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscure2
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setSheet(() => obscure2 = !obscure2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              final p = passCtrl.text;
                              final c = confirmCtrl.text;
                              if (p.length < 6) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Mínimo 6 caracteres',
                                    ),
                                  ),
                                );
                                return;
                              }
                              if (p != c) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Las contraseñas no coinciden',
                                    ),
                                  ),
                                );
                                return;
                              }
                              setSheet(() => saving = true);
                              try {
                                await ref
                                    .read(profileProvider.notifier)
                                    .changePassword(p);
                                if (!ctx.mounted) return;
                                Navigator.of(ctx).pop();
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Contraseña actualizada'),
                                    backgroundColor: Color(0xFF176351),
                                  ),
                                );
                              } catch (e) {
                                setSheet(() => saving = false);
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Actualizar contraseña'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      passCtrl.dispose();
      confirmCtrl.dispose();
    });
  }
}

class _AvatarHeader extends StatelessWidget {
  final DriverProfile profile;
  final ColorScheme colorScheme;

  const _AvatarHeader({
    required this.profile,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        profile.fotoUrl != null && profile.fotoUrl!.trim().isNotEmpty;

    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primaryContainer,
        border: Border.all(color: colorScheme.primary, width: 3),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? Image.network(
              profile.fotoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _Initials(
                initials: profile.initials,
                color: colorScheme.onPrimaryContainer,
              ),
            )
          : _Initials(
              initials: profile.initials,
              color: colorScheme.onPrimaryContainer,
            ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String initials;
  final Color color;

  const _Initials({required this.initials, required this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final ColorScheme colorScheme;

  const _StatusChip({required this.label, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(Icons.circle, size: 10, color: colorScheme.primary),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
      side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final DriverProfile profile;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _InfoCard({
    required this.profile,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    String? licenciaVence;
    if (profile.vencimientoLicencia != null) {
      final d = profile.vencimientoLicencia!;
      licenciaVence =
          'Vence ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }

    final items = <_InfoItem>[
      _InfoItem(
        icon: Icons.email_outlined,
        label: 'Correo',
        value: profile.email.isEmpty ? '—' : profile.email,
      ),
      _InfoItem(
        icon: Icons.phone_outlined,
        label: 'Teléfono',
        value: (profile.telefono == null || profile.telefono!.isEmpty)
            ? '—'
            : profile.telefono!,
      ),
      _InfoItem(
        icon: Icons.badge_outlined,
        label: 'Licencia',
        value: profile.licenseDisplay,
        subtitle: licenciaVence,
      ),
      _InfoItem(
        icon: Icons.local_shipping_outlined,
        label: 'Vehículo',
        value: profile.vehicleDisplay,
      ),
      _InfoItem(
        icon: Icons.business_outlined,
        label: 'Empresa',
        value: profile.empresaNombre?.isNotEmpty == true
            ? profile.empresaNombre!
            : '—',
      ),
      _InfoItem(
        icon: Icons.verified_outlined,
        label: 'Estado',
        value: profile.activo ? profile.statusLabel : 'Usuario inactivo',
      ),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 56,
                  endIndent: 16,
                  color: colorScheme.outlineVariant,
                ),
              ListTile(
                leading: Icon(items[i].icon, color: colorScheme.primary),
                title: Text(
                  items[i].label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      items[i].value,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (items[i].subtitle != null)
                      Text(
                        items[i].subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
                isThreeLine: items[i].subtitle != null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onChangePassword;
  final ColorScheme colorScheme;

  const _ActionButtons({
    required this.onEdit,
    required this.onChangePassword,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar perfil'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onChangePassword,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Cambiar contraseña'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onLogout;

  const _LogoutButton({required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onLogout,
        icon: Icon(Icons.logout, color: error),
        label: Text('Cerrar sesión', style: TextStyle(color: error)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: error),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off_outlined,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            const Text('No se pudo cargar el perfil'),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });
}
