/// Resultado de una página de datos (listas largas / memoria acotada).
class PageResult<T> {
  final List<T> items;
  final int page;
  final int pageSize;
  final bool hasMore;
  final int? total;

  const PageResult({
    required this.items,
    required this.page,
    required this.pageSize,
    required this.hasMore,
    this.total,
  });

  factory PageResult.empty({int page = 0, int pageSize = 20}) => PageResult(
        items: const [],
        page: page,
        pageSize: pageSize,
        hasMore: false,
        total: 0,
      );

  int get count => items.length;
}

/// Estado mutable de una lista paginada en UI.
class PagedListState<T> {
  final List<T> items;
  final int nextPage;
  final bool hasMore;
  final bool isInitialLoading;
  final bool isLoadingMore;
  final String? error;
  final int? total;

  const PagedListState({
    this.items = const [],
    this.nextPage = 0,
    this.hasMore = true,
    this.isInitialLoading = true,
    this.isLoadingMore = false,
    this.error,
    this.total,
  });

  PagedListState<T> copyWith({
    List<T>? items,
    int? nextPage,
    bool? hasMore,
    bool? isInitialLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
    int? total,
  }) {
    return PagedListState<T>(
      items: items ?? this.items,
      nextPage: nextPage ?? this.nextPage,
      hasMore: hasMore ?? this.hasMore,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
      total: total ?? this.total,
    );
  }
}
