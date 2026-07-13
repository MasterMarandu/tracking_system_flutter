import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tracking_system_app/features/dashboard/providers/bootstrap_provider.dart';
import 'package:tracking_system_app/features/packages/data/package_service.dart';
import 'package:tracking_system_app/features/packages/domain/package.dart';

final packagesProvider = FutureProvider<List<Package>>((ref) async {
  final bootstrap = ref.watch(bootstrapProvider).valueOrNull;
  final tripId = bootstrap?.trip?.id;

  if (tripId == null || tripId.isEmpty) {
    return [];
  }

  return PackageService.instance.fetchPackagesForTrip(tripId);
});
