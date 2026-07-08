import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _isDarkMode = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader('Appearance', colorScheme, theme),
            _buildAppearanceSection(colorScheme, theme),
            const Divider(height: 1),
            _buildSectionHeader('Language', colorScheme, theme),
            _buildLanguageSection(colorScheme, theme),
            const Divider(height: 1),
            _buildSectionHeader('Notifications', colorScheme, theme),
            _buildNotificationSection(colorScheme, theme),
            const Divider(height: 1),
            _buildSectionHeader('Privacy', colorScheme, theme),
            _buildPrivacySection(colorScheme, theme),
            const Divider(height: 1),
            _buildSectionHeader('About', colorScheme, theme),
            _buildAboutSection(colorScheme, theme),
            const Divider(height: 1),
            _buildVersionSection(colorScheme, theme),
            const SizedBox(height: 32),
            _buildLogoutButton(context),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
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

  Widget _buildAppearanceSection(ColorScheme colorScheme, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(
              _isDarkMode ? Icons.dark_mode : Icons.light_mode,
              color: colorScheme.primary,
            ),
            title: const Text('Dark Mode'),
            subtitle: Text(
              _isDarkMode ? 'Dark theme enabled' : 'Light theme enabled',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: _isDarkMode,
            onChanged: (value) {
              setState(() {
                _isDarkMode = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSection(ColorScheme colorScheme, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: Icon(Icons.language, color: colorScheme.primary),
        title: const Text('Language'),
        subtitle: Text(
          'English',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: colorScheme.onSurfaceVariant,
        ),
        onTap: () {},
      ),
    );
  }

  Widget _buildNotificationSection(ColorScheme colorScheme, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: SwitchListTile(
        secondary: Icon(
          Icons.notifications_outlined,
          color: colorScheme.primary,
        ),
        title: const Text('Push Notifications'),
        subtitle: Text(
          _notificationsEnabled
              ? 'Receive push notifications'
              : 'Notifications disabled',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        value: _notificationsEnabled,
        onChanged: (value) {
          setState(() {
            _notificationsEnabled = value;
          });
        },
      ),
    );
  }

  Widget _buildPrivacySection(ColorScheme colorScheme, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.lock_outline, color: colorScheme.primary),
            title: const Text('Privacy Policy'),
            trailing: Icon(
              Icons.chevron_right,
              color: colorScheme.onSurfaceVariant,
            ),
            onTap: () {},
          ),
          Divider(height: 1, indent: 56, color: colorScheme.outlineVariant),
          ListTile(
            leading: Icon(Icons.description_outlined, color: colorScheme.primary),
            title: const Text('Terms of Service'),
            trailing: Icon(
              Icons.chevron_right,
              color: colorScheme.onSurfaceVariant,
            ),
            onTap: () {},
          ),
          Divider(height: 1, indent: 56, color: colorScheme.outlineVariant),
          ListTile(
            leading: Icon(Icons.delete_outline, color: colorScheme.error),
            title: Text(
              'Delete Account',
              style: TextStyle(color: colorScheme.error),
            ),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection(ColorScheme colorScheme, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.info_outline, color: colorScheme.primary),
            title: const Text('About App'),
            trailing: Icon(
              Icons.chevron_right,
              color: colorScheme.onSurfaceVariant,
            ),
            onTap: () {},
          ),
          Divider(height: 1, indent: 56, color: colorScheme.outlineVariant),
          ListTile(
            leading: Icon(Icons.help_outline, color: colorScheme.primary),
            title: const Text('Help & Support'),
            trailing: Icon(
              Icons.chevron_right,
              color: colorScheme.onSurfaceVariant,
            ),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildVersionSection(ColorScheme colorScheme, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.local_shipping,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              'Tracking System',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Version 1.0.0 (Build 1)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '© 2026 Tracking System App',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
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
      ),
    );
  }
}
