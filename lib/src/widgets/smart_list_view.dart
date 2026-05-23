import 'package:flutter/material.dart';

import '../controller/smart_list_controller.dart';
import '../core/smart_list_state.dart';
import 'default_state_builders.dart';

/// Drop-in list widget that binds to a [SmartListController] and renders the
/// appropriate UI for every state (loading, error, empty, populated).
///
/// The widget is intentionally thin — it composes Flutter primitives
/// ([ListView.separated], [RefreshIndicator], [NotificationListener]) rather
/// than re-implementing them. All visuals are customisable through the
/// `*Builder` parameters; defaults from [DefaultSmartListStates] kick in
/// when none are provided.
///
/// Auto-pagination: when the user scrolls within
/// [loadMoreThreshold] pixels of the bottom, [SmartListController.loadNextPage]
/// is invoked. The threshold doubles as a pre-fetch hint.
class SmartListView<T> extends StatefulWidget {
  final SmartListController<T> controller;
  final SmartListItemBuilder<T> itemBuilder;

  final SmartListSeparatorBuilder? separatorBuilder;
  final SmartListWidgetBuilder? loadingBuilder;
  final SmartListWidgetBuilder? loadingMoreBuilder;
  final SmartListWidgetBuilder? emptyBuilder;
  final SmartListSearchEmptyBuilder? searchEmptyBuilder;
  final SmartListErrorBuilder? errorBuilder;

  /// Builder for the *inline* footer shown when a subsequent-page fetch
  /// fails (the first page already loaded — items are visible). When `null`,
  /// the default compact "Failed to load more / Retry" row is used.
  /// This is intentionally separate from [errorBuilder], which is the
  /// full-screen fallback shown when the first page fails with no items.
  final SmartListErrorBuilder? loadMoreErrorBuilder;

  final SmartListFooterBuilder<T>? footerBuilder;

  /// Whether to wrap the list in a [RefreshIndicator] for pull-to-refresh.
  final bool enableRefresh;

  /// Pixel distance from the bottom at which the next page should be requested.
  final double loadMoreThreshold;

  /// Optional padding around the list contents.
  final EdgeInsetsGeometry? padding;

  /// Scroll physics override — defaults to Flutter's per-platform physics.
  final ScrollPhysics? physics;

  /// Optional scroll controller override. If null, an internal one is used so
  /// the widget can respond to scroll notifications.
  final ScrollController? scrollController;

  /// Whether the list is laid out and scrolled in reverse order — useful for
  /// chat-style screens where the newest item sits at the bottom and earlier
  /// items load by scrolling up. Forwarded directly to [ListView.reverse].
  final bool reverse;

  const SmartListView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.separatorBuilder,
    this.loadingBuilder,
    this.loadingMoreBuilder,
    this.emptyBuilder,
    this.searchEmptyBuilder,
    this.errorBuilder,
    this.loadMoreErrorBuilder,
    this.footerBuilder,
    this.enableRefresh = true,
    this.loadMoreThreshold = 240,
    this.padding,
    this.physics,
    this.scrollController,
    this.reverse = false,
  });

  @override
  State<SmartListView<T>> createState() => _SmartListViewState<T>();
}

class _SmartListViewState<T> extends State<SmartListView<T>> {
  ScrollController? _internalController;
  bool _disposed = false;

  ScrollController? get _controller {
    if (widget.scrollController != null) return widget.scrollController;
    // After dispose, do not resurrect a fresh ScrollController — it would
    // leak (we'll never dispose it) and indicates a stale callback.
    if (_disposed) return null;
    return _internalController ??= ScrollController();
  }

  @override
  void initState() {
    super.initState();
    _scheduleInitialLoad(widget.controller);
  }

  @override
  void didUpdateWidget(covariant SmartListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Hosted controller swapped — kick off the new one's initial load.
    // `loadInitial()` is a safe no-op when the new controller already has
    // items, so it's fine to call unconditionally on identity change.
    if (!identical(oldWidget.controller, widget.controller)) {
      _scheduleInitialLoad(widget.controller);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _internalController?.dispose();
    super.dispose();
  }

  /// Schedule the initial load on the next frame, but only if this State is
  /// still mounted *and* still bound to [target] when the callback fires.
  /// Without these guards, dispose-then-fire or rapid controller swaps could
  /// trigger fetches against a stale or unmounted widget.
  void _scheduleInitialLoad(SmartListController<T> target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!identical(widget.controller, target)) return;
      target.loadInitial();
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final remaining =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    if (remaining <= widget.loadMoreThreshold) {
      widget.controller.loadNextPage();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SmartListState<T>>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        Widget child;
        // Non-list states (loading/error/empty) are centred widgets and are
        // not inherently scrollable. When refresh is enabled, they need to
        // live inside an always-scrollable viewport so the pull-to-refresh
        // gesture has something to grab. `isPlaceholder` flags those cases.
        bool isPlaceholder = false;

        if (state.isInitialLoading) {
          child = (widget.loadingBuilder ?? DefaultSmartListStates.loading)(
            context,
          );
          isPlaceholder = true;
        } else if (state.hasError && state.items.isEmpty) {
          final retry = state.isSearchActive
              ? () => widget.controller.search(state.query!)
              : widget.controller.refresh;
          child = (widget.errorBuilder ?? DefaultSmartListStates.error)(
            context,
            state.error ?? 'Unknown error',
            retry,
          );
          isPlaceholder = true;
        } else if (state.isSearchEmpty) {
          child =
              (widget.searchEmptyBuilder ?? DefaultSmartListStates.searchEmpty)(
            context,
            state.query!,
          );
          isPlaceholder = true;
        } else if (state.isEmpty) {
          child = (widget.emptyBuilder ?? DefaultSmartListStates.empty)(
            context,
          );
          isPlaceholder = true;
        } else {
          child = _buildList(context, state);
        }

        if (!widget.enableRefresh) return child;

        if (isPlaceholder) {
          // Wrap the placeholder in a viewport-sized scrollable so the pull
          // gesture is always available — even on error/empty/initial-loading
          // where the content itself is just a centred widget. A `ListView`
          // with one viewport-tall child keeps every internal box bounded
          // and avoids 'Center forces an infinite height' under
          // `SingleChildScrollView`.
          final placeholder = child;
          child = LayoutBuilder(
            builder: (context, constraints) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: constraints.maxHeight,
                  child: placeholder,
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: widget.controller.refresh,
          child: child,
        );
      },
    );
  }

  Widget _buildList(BuildContext context, SmartListState<T> state) {
    final itemCount = state.items.length + 1; // +1 for footer slot

    Widget defaultFooter() {
      if (state.isLoadingMore) {
        return (widget.loadingMoreBuilder ??
            DefaultSmartListStates.loadingMore)(context);
      }
      if (state.hasError) {
        // A *pagination* error: items are visible, only the next page failed.
        // Use the compact inline builder (or the user's override) so we don't
        // dump a full-screen error widget at the bottom of the list.
        return (widget.loadMoreErrorBuilder ??
            DefaultSmartListStates.loadMoreError)(
          context,
          state.error ?? 'Unknown error',
          widget.controller.loadNextPage,
        );
      }
      return const SizedBox.shrink();
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: ListView.separated(
        controller: _controller,
        padding: widget.padding,
        physics: widget.physics ??
            (widget.enableRefresh
                ? const AlwaysScrollableScrollPhysics()
                : null),
        reverse: widget.reverse,
        itemCount: itemCount,
        separatorBuilder: (context, index) {
          // Suppress only the separator between the last real item and the
          // footer slot. `index == items.length - 1` is the gap that sits
          // *before* the footer; every smaller index is a gap between two
          // real items and should render normally.
          if (index == state.items.length - 1) return const SizedBox.shrink();
          return widget.separatorBuilder?.call(context, index) ??
              const SizedBox.shrink();
        },
        itemBuilder: (context, index) {
          if (index >= state.items.length) {
            return widget.footerBuilder?.call(context, state) ??
                defaultFooter();
          }
          return widget.itemBuilder(context, state.items[index], index);
        },
      ),
    );
  }
}
