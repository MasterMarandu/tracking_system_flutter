import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tracking_system_app/core/config/supabase_config.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  String _statusMessage = 'Comprobando sesión...';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _initialize();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    final session = SupabaseConfig.client.auth.currentSession;

    if (session == null) {
      if (!mounted) return;
      context.go('/login');
      return;
    }

    setState(() => _statusMessage = 'Validando sesión...');
    await Future.delayed(const Duration(milliseconds: 400));

    if (!mounted) return;

    setState(() => _statusMessage = 'Sincronizando operación...');
    await ref.read(bootstrapProvider.notifier).loadBootstrap();

    if (!mounted) return;

    final bootstrap = ref.read(bootstrapProvider).valueOrNull;

    if (bootstrap == null) {
      setState(() => _statusMessage = 'Error de conexión');
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      final retrySession = SupabaseConfig.client.auth.currentSession;
      if (retrySession == null) {
        if (!mounted) return;
        context.go('/login');
      } else {
        context.go('/dashboard');
      }
      return;
    }

    if (!bootstrap.user.active) {
      setState(() =>
          _statusMessage = 'Perfil no configurado como conductor');
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.go('/login');
      return;
    }

    if (bootstrap.driver.status == 'inactivo') {
      setState(() => _statusMessage = 'Cuenta de conductor inactiva');
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.go('/login');
      return;
    }

    if (bootstrap.driver.status == 'sin_perfil') {
      setState(() =>
          _statusMessage = 'Tu usuario no está configurado como conductor');
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.go('/login');
      return;
    }

    context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Transform.scale(
                  scale: 1.0 + (_pulseController.value * 0.04),
                  child: child,
                );
              },
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.local_shipping_rounded,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'FleetTrack',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Professional Logistics',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
