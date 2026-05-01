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

  ScrollController get _controller =>
      widget.scrollController ?? (_internalController ??= ScrollController());

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

        if (state.isInitialLoading) {
          child = (widget.loadingBuilder ?? DefaultSmartListStates.loading)(
            context,
          );
        } else if (state.hasError && state.items.isEmpty) {
          final retry = state.isSearchActive
              ? () => widget.controller.search(state.query!)
              : widget.controller.refresh;
          child = (widget.errorBuilder ?? DefaultSmartListStates.error)(
            context,
            state.error ?? 'Unknown error',
            retry,
          );
        } else if (state.isSearchEmpty) {
          child =
              (widget.searchEmptyBuilder ?? DefaultSmartListStates.searchEmpty)(
            context,
            state.query!,
          );
        } else if (state.isEmpty) {
          child = (widget.emptyBuilder ?? DefaultSmartListStates.empty)(
            context,
          );
        } else {
          child = _buildList(context, state);
        }

        if (!widget.enableRefresh) return child;
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
        return (widget.errorBuilder ?? DefaultSmartListStates.error)(
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
          if (index >= state.items.length - 1) return const SizedBox.shrink();
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
