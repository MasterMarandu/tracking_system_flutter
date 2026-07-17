import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/features/authentication/presentation/screens/login_screen.dart';
import 'package:tracking_system_app/features/authentication/presentation/screens/splash_screen.dart';
import 'package:tracking_system_app/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:tracking_system_app/features/trips/presentation/screens/trips_screen.dart';
import 'package:tracking_system_app/features/trips/presentation/screens/trip_detail_screen.dart';
import 'package:tracking_system_app/features/tracking/presentation/screens/tracking_screen.dart';
import 'package:tracking_system_app/features/packages/presentation/screens/packages_screen.dart';
import 'package:tracking_system_app/features/packages/presentation/screens/package_detail_screen.dart';
import 'package:tracking_system_app/features/packages/domain/packages_provider.dart';
import 'package:tracking_system_app/features/delivery/presentation/screens/delivery_screen.dart';
import 'package:tracking_system_app/features/incidents/presentation/screens/incidents_screen.dart';
import 'package:tracking_system_app/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:tracking_system_app/features/chat/presentation/screens/chat_screen.dart';
import 'package:tracking_system_app/features/profile/presentation/screens/profile_screen.dart';
import 'package:tracking_system_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:tracking_system_app/features/sync/presentation/screens/sync_screen.dart';
import 'package:tracking_system_app/core/widgets/main_scaffold.dart';

final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final GlobalKey<NavigatorState> _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    debugLogDiagnostics: true,
    routes: [
      // Splash Screen
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      
      // Login Screen
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      
      // Main App Shell with Bottom Navigation
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          // Dashboard
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DashboardScreen(),
            ),
          ),
          
          // Trips
          GoRoute(
            path: '/trips',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TripsScreen(),
            ),
            routes: [
              GoRoute(
                path: ':tripId',
                parentNavigatorKey: _rootNavigatorKey,
                builder: (context, state) => TripDetailScreen(
                  tripId: state.pathParameters['tripId']!,
                ),
              ),
            ],
          ),
          
          // Tracking Map
          GoRoute(
            path: '/tracking',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TrackingScreen(),
            ),
          ),
          
          // Packages
          GoRoute(
            path: '/packages',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: PackagesScreen(),
            ),
            routes: [
              GoRoute(
                path: ':packageId',
                parentNavigatorKey: _rootNavigatorKey,
                builder: (context, state) {
                  final packageId = state.pathParameters['packageId']!;
                  final packages = ref.read(packagesProvider).valueOrNull ?? [];
                  final pkg = packages.where((p) => p.id == packageId).firstOrNull;
                  if (pkg == null) {
                    return Scaffold(
                      appBar: AppBar(title: Text('Paquete $packageId')),
                      body: const Center(child: Text('Paquete no encontrado')),
                    );
                  }
                  return PackageDetailScreen(package: pkg);
                },
              ),
            ],
          ),
          
          // More Menu
          GoRoute(
            path: '/more',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: _MoreScreen(),
            ),
          ),
        ],
      ),
      
      // Delivery Screen (full screen)
      GoRoute(
        path: '/delivery/:packageId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => DeliveryScreen(
          packageId: state.pathParameters['packageId']!,
        ),
      ),
      
      // Incidents Screen
      GoRoute(
        path: '/incidents',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const IncidentsScreen(),
      ),
      
      // Notifications Screen
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),
      
      // Chat Screen
      GoRoute(
        path: '/chat/:chatId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ChatScreen(
          chatId: state.pathParameters['chatId']!,
        ),
      ),
      
      // Profile Screen
      GoRoute(
        path: '/profile',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ProfileScreen(),
      ),
      
      // Settings Screen
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
      ),
      
      // Sync Screen
      GoRoute(
        path: '/sync',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SyncScreen(),
      ),
    ],
    redirect: (context, state) {
      final session = SupabaseConfig.client.auth.currentSession;
      final isAuthenticated = session != null;
      final isOnSplash = state.matchedLocation == '/splash';

      if (isOnSplash) return null;

      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register' ||
          state.matchedLocation == '/forgot-password';

      if (isAuthenticated && isAuthRoute) {
        return '/dashboard';
      }

      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              state.matchedLocation,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/dashboard'),
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    ),
  );
});

class _MoreScreen extends StatelessWidget {
  const _MoreScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          _buildMenuItem(
            context,
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            onTap: () => context.push('/notifications'),
          ),
          _buildMenuItem(
            context,
            icon: Icons.chat_outlined,
            title: 'Chat',
            onTap: () => context.push('/chat/general'),
          ),
          _buildMenuItem(
            context,
            icon: Icons.report_outlined,
            title: 'Incidencias',
            onTap: () => context.push('/incidents'),
          ),
          _buildMenuItem(
            context,
            icon: Icons.sync_outlined,
            title: 'Sincronización',
            onTap: () => context.push('/sync'),
          ),
          _buildMenuItem(
            context,
            icon: Icons.person_outline,
            title: 'Perfil',
            onTap: () => context.push('/profile'),
          ),
          _buildMenuItem(
            context,
            icon: Icons.settings_outlined,
            title: 'Ajustes',
            onTap: () => context.push('/settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
