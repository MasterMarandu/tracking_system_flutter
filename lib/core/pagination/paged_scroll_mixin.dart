import 'package:flutter/material.dart';
import 'package:tracking_system_app/core/config/constants.dart';

/// Escucha el scroll y pide la siguiente página cerca del final.
mixin PagedScrollMixin<T extends StatefulWidget> on State<T> {
  final ScrollController pagedScrollController = ScrollController();

  /// Distancia al final (px) para disparar carga.
  double get loadMoreThreshold => 320;

  @override
  void initState() {
    super.initState();
    pagedScrollController.addListener(_onPagedScroll);
  }

  @override
  void dispose() {
    pagedScrollController.removeListener(_onPagedScroll);
    pagedScrollController.dispose();
    super.dispose();
  }

  void _onPagedScroll() {
    if (!pagedScrollController.hasClients) return;
    final pos = pagedScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - loadMoreThreshold) {
      onLoadMoreRequested();
    }
  }

  /// Implementar en la pantalla: cargar página siguiente.
  void onLoadMoreRequested();

  Widget buildLoadMoreFooter({
    required bool isLoadingMore,
    required bool hasMore,
  }) {
    if (!hasMore && !isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text(
            'No hay más resultados',
            style: TextStyle(fontSize: 12, color: Color(0xFF6E7B77)),
          ),
        ),
      );
    }
    if (!isLoadingMore) return const SizedBox(height: 24);
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

/// Helpers de rango Supabase `.range(from, to)`.
class PageRange {
  final int from;
  final int to;
  final int page;
  final int pageSize;

  const PageRange({
    required this.from,
    required this.to,
    required this.page,
    required this.pageSize,
  });

  factory PageRange.of(int page, {int pageSize = AppConstants.defaultPageSize}) {
    final size = pageSize.clamp(1, AppConstants.maxPageSize);
    final from = page * size;
    return PageRange(
      from: from,
      to: from + size - 1,
      page: page,
      pageSize: size,
    );
  }
}
