import 'package:flutter/foundation.dart';

import 'smart_list_phase.dart';

/// Immutable snapshot of a [SmartListController]'s state.
///
/// `SmartListState` is intentionally immutable — every mutation goes through
/// [copyWith], producing a new instance. This enables cheap equality checks,
/// predictable rebuilds, and trivial debugging of state transitions.
@immutable
class SmartListState<T> {
  /// All items currently held by the controller. When a search is active, this
  /// list contains only the search results; the pre-search items are kept
  /// separately by the controller and restored on `clearSearch`.
  final List<T> items;

  /// Lifecycle phase. See [SmartListPhase].
  final SmartListPhase phase;

  /// The error from the most recent failed fetch, if any.
  final Object? error;

  /// Stack trace associated with [error]. Useful for diagnostics.
  final StackTrace? stackTrace;

  /// `true` once the data source signals there are no more pages.
  final bool hasReachedEnd;

  /// The active search query, or `null` if no search is in progress.
  /// An empty string is treated as "no search".
  final String? query;

  /// User-supplied filters that scope the fetch (e.g. `{status: 'open'}`).
  final Map<String, dynamic> filters;

  /// Number of retry attempts made for the most recent fetch.
  final int retryAttempt;

  const SmartListState({
    this.items = const [],
    this.phase = SmartListPhase.initial,
    this.error,
    this.stackTrace,
    this.hasReachedEnd = false,
    this.query,
    this.filters = const {},
    this.retryAttempt = 0,
  });

  /// Initial empty state — convenience constructor.
  factory SmartListState.initial() => SmartListState<T>(items: const []);

  // ─── Derived booleans ────────────────────────────────────────────────────

  /// First-page load with no items yet visible.
  bool get isInitialLoading => phase == SmartListPhase.loading && items.isEmpty;

  /// A subsequent-page fetch is in flight.
  bool get isLoadingMore => phase == SmartListPhase.loadingMore;

  /// A pull-to-refresh is in flight.
  bool get isRefreshing => phase == SmartListPhase.refreshing;

  /// Convenience — fetch is in any in-flight phase.
  bool get isBusy =>
      phase == SmartListPhase.loading ||
      phase == SmartListPhase.loadingMore ||
      phase == SmartListPhase.refreshing;

  /// `true` if the most recent fetch ended in error.
  bool get hasError => phase == SmartListPhase.error;

  /// `true` when a fetch succeeded but produced no items at all.
  /// Distinct from `hasReachedEnd`, which can be true even with items.
  bool get isEmpty => items.isEmpty && phase == SmartListPhase.success;

  /// `true` when a non-empty search query is active.
  bool get isSearchActive => query != null && query!.isNotEmpty;

  /// `true` when the empty result is specifically the result of a search.
  bool get isSearchEmpty => isEmpty && isSearchActive;

  // ─── copyWith ────────────────────────────────────────────────────────────

  /// Returns a copy of this state with the provided fields replaced.
  ///
  /// Pass [clearError] to drop a previously set error (since `null` cannot
  /// distinguish "leave unchanged" from "set to null"). Same for
  /// [clearQuery] and [clearStackTrace].
  SmartListState<T> copyWith({
    List<T>? items,
    SmartListPhase? phase,
    Object? error,
    StackTrace? stackTrace,
    bool? hasReachedEnd,
    String? query,
    Map<String, dynamic>? filters,
    int? retryAttempt,
    bool clearError = false,
    bool clearStackTrace = false,
    bool clearQuery = false,
  }) {
    return SmartListState<T>(
      items: items ?? this.items,
      phase: phase ?? this.phase,
      error: clearError ? null : (error ?? this.error),
      stackTrace: clearStackTrace ? null : (stackTrace ?? this.stackTrace),
      hasReachedEnd: hasReachedEnd ?? this.hasReachedEnd,
      query: clearQuery ? null : (query ?? this.query),
      filters: filters ?? this.filters,
      retryAttempt: retryAttempt ?? this.retryAttempt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SmartListState<T> &&
        listEquals(other.items, items) &&
        other.phase == phase &&
        other.error == error &&
        other.hasReachedEnd == hasReachedEnd &&
        other.query == query &&
        mapEquals(other.filters, filters) &&
        other.retryAttempt == retryAttempt;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(items),
        phase,
        error,
        hasReachedEnd,
        query,
        Object.hashAllUnordered(filters.entries),
        retryAttempt,
      );

  @override
  String toString() => 'SmartListState(phase: $phase, items: ${items.length}, '
      'hasReachedEnd: $hasReachedEnd, query: $query, '
      'filters: $filters, error: $error)';
}
