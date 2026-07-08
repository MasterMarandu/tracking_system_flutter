import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          children: [
            _buildAvatar(context, colorScheme),
            const SizedBox(height: 32),
            _buildInfoSection(colorScheme, theme),
            const SizedBox(height: 24),
            _buildActionButtons(context, colorScheme),
            const SizedBox(height: 24),
            _buildLogoutButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, ColorScheme colorScheme) {
    return Stack(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colorScheme.primaryContainer,
            border: Border.all(
              color: colorScheme.primary,
              width: 3,
            ),
          ),
          child: Icon(
            Icons.person,
            size: 64,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        Positioned(
          bottom: 0,
          right: 0,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary,
              border: Border.all(
                color: colorScheme.surface,
                width: 2,
              ),
            ),
            child: Icon(
              Icons.camera_alt,
              size: 18,
              color: colorScheme.onPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection(ColorScheme colorScheme, ThemeData theme) {
    final infoItems = [
      _InfoItem(icon: Icons.person_outline, label: 'Name', value: 'John Doe'),
      _InfoItem(icon: Icons.email_outlined, label: 'Email', value: 'john.doe@example.com'),
      _InfoItem(icon: Icons.phone_outlined, label: 'Phone', value: '+1 (555) 123-4567'),
      _InfoItem(icon: Icons.badge_outlined, label: 'License', value: 'DL-2024-78901'),
      _InfoItem(icon: Icons.local_shipping_outlined, label: 'Vehicle', value: 'Truck #T-1042'),
      _InfoItem(icon: Icons.business_outlined, label: 'Company', value: 'FastTrack Logistics'),
      _InfoItem(icon: Icons.verified_outlined, label: 'Status', value: 'Active'),
    ];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: List.generate(infoItems.length * 2 - 1, (index) {
            if (index.isOdd) {
              return Divider(
                height: 1,
                indent: 56,
                endIndent: 16,
                color: colorScheme.outlineVariant,
              );
            }
            final item = infoItems[index ~/ 2];
            return ListTile(
              leading: Icon(item.icon, color: colorScheme.primary),
              title: Text(
                item.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              subtitle: Text(
                item.value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, ColorScheme colorScheme) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.edit),
            label: const Text('Edit Profile'),
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
            onPressed: () {},
            icon: const Icon(Icons.lock_outline),
            label: const Text('Change Password'),
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

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Logout'),
              content: const Text('Are you sure you want to logout?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  child: const Text('Logout'),
                ),
              ],
            ),
          );
        },
        icon: Icon(
          Icons.logout,
          color: Theme.of(context).colorScheme.error,
        ),
        label: Text(
          'Logout',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(
            color: Theme.of(context).colorScheme.error,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });
}
