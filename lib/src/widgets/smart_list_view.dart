import 'package:flutter/material.dart';

import '../controller/smart_list_controller.dart';
import '../core/smart_list_phase.dart';
import '../core/smart_list_state.dart';
import 'default_state_builders.dart';
import 'load_more_gate.dart';

/// Drop-in list widget that binds to a [SmartListController] and renders the
/// appropriate UI for every state (loading, error, empty, populated).
///
/// The widget is intentionally thin — it composes Flutter primitives
/// ([ListView.separated], [RefreshIndicator], [NotificationListener]) rather
/// than re-implementing them. All visuals are customisable through the
/// `*Builder` parameters; defaults from [DefaultSmartListStates] kick in
/// when none are provided.
///
/// Auto-pagination: when remaining distance **crosses**
/// [loadMoreThreshold] pixels of the bottom, [SmartListController.loadNextPage]
/// is invoked.
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
  final SmartListErrorBuilder? loadMoreErrorBuilder;

  final SmartListFooterBuilder<T>? footerBuilder;
  final SmartListWidgetBuilder? searchLoadingBuilder;

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

  final double? cacheExtent;

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
    this.searchLoadingBuilder,
    this.enableRefresh = true,
    this.loadMoreThreshold = 240,
    this.padding,
    this.physics,
    this.scrollController,
    this.reverse = false,
    this.cacheExtent,
  });

  @override
  State<SmartListView<T>> createState() => _SmartListViewState<T>();
}

class _SmartListViewState<T> extends State<SmartListView<T>> {
  ScrollController? _internalController;
  final LoadMoreGate _loadMoreGate = LoadMoreGate();
  bool _disposed = false;

  ScrollController? get _controller {
    if (widget.scrollController != null) return widget.scrollController;
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
    if (!identical(oldWidget.controller, widget.controller)) {
      _loadMoreGate.reset();
      _scheduleInitialLoad(widget.controller);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _internalController?.dispose();
    super.dispose();
  }

  void _scheduleInitialLoad(SmartListController<T> target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!identical(widget.controller, target)) return;
      target.loadInitial();
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification.metrics.maxScrollExtent <= 0) return false;
    final state = widget.controller.value;
    if (state.isBusy || state.hasReachedEnd) return false;
    final remaining =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    if (_loadMoreGate.shouldLoadMore(remaining, widget.loadMoreThreshold)) {
      widget.controller.loadNextPage();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final body = _SmartListBody<T>(
      controller: widget.controller,
      itemBuilder: widget.itemBuilder,
      separatorBuilder: widget.separatorBuilder,
      loadingMoreBuilder: widget.loadingMoreBuilder,
      searchLoadingBuilder: widget.searchLoadingBuilder,
      loadMoreErrorBuilder: widget.loadMoreErrorBuilder,
      footerBuilder: widget.footerBuilder,
      padding: widget.padding,
      physics: widget.physics,
      reverse: widget.reverse,
      cacheExtent: widget.cacheExtent,
      enableRefresh: widget.enableRefresh,
      loadMoreThreshold: widget.loadMoreThreshold,
      scrollController: _controller,
      onScrollNotification: _onScrollNotification,
    );

    return ValueListenableBuilder<SmartListState<T>>(
      valueListenable: widget.controller,
      builder: (context, state, child) {
        Widget content;
        bool isPlaceholder = false;

        if (state.isInitialLoading) {
          content = (widget.loadingBuilder ?? DefaultSmartListStates.loading)(
            context,
          );
          isPlaceholder = true;
        } else if (state.hasError && state.items.isEmpty) {
          final retry = state.isSearchActive
              ? () => widget.controller.search(state.query!)
              : widget.controller.refresh;
          content = (widget.errorBuilder ?? DefaultSmartListStates.error)(
            context,
            state.error ?? 'Unknown error',
            retry,
          );
          isPlaceholder = true;
        } else if (state.isSearchEmpty) {
          content =
              (widget.searchEmptyBuilder ?? DefaultSmartListStates.searchEmpty)(
            context,
            state.query!,
          );
          isPlaceholder = true;
        } else if (state.isEmpty) {
          content = (widget.emptyBuilder ?? DefaultSmartListStates.empty)(
            context,
          );
          isPlaceholder = true;
        } else {
          content = child!;
        }

        if (!widget.enableRefresh) return content;

        if (isPlaceholder) {
          final placeholder = content;
          content = LayoutBuilder(
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
          child: content,
        );
      },
      child: body,
    );
  }
}

/// The populated `ListView` portion of [SmartListView], extracted so it can
/// subscribe to the controller independently of loading / error / empty chrome.
class _SmartListBody<T> extends StatefulWidget {
  final SmartListController<T> controller;
  final SmartListItemBuilder<T> itemBuilder;
  final SmartListSeparatorBuilder? separatorBuilder;
  final SmartListWidgetBuilder? loadingMoreBuilder;
  final SmartListWidgetBuilder? searchLoadingBuilder;
  final SmartListErrorBuilder? loadMoreErrorBuilder;
  final SmartListFooterBuilder<T>? footerBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final bool reverse;
  final double? cacheExtent;
  final bool enableRefresh;
  final double loadMoreThreshold;
  final ScrollController? scrollController;
  final bool Function(ScrollNotification) onScrollNotification;

  const _SmartListBody({
    super.key,
    required this.controller,
    required this.itemBuilder,
    required this.separatorBuilder,
    required this.loadingMoreBuilder,
    required this.searchLoadingBuilder,
    required this.loadMoreErrorBuilder,
    required this.footerBuilder,
    required this.padding,
    required this.physics,
    required this.reverse,
    required this.cacheExtent,
    required this.enableRefresh,
    required this.loadMoreThreshold,
    required this.scrollController,
    required this.onScrollNotification,
  });

  @override
  State<_SmartListBody<T>> createState() => _SmartListBodyState<T>();
}

class _SmartListBodyState<T> extends State<_SmartListBody<T>> {
  late List<T> _items;
  late SmartListPhase _phase;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final s = widget.controller.state;
    _items = s.items;
    _phase = s.phase;
    _error = s.error;
    widget.controller.addListener(_onControllerChange);
  }

  @override
  void didUpdateWidget(covariant _SmartListBody<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChange);
      widget.controller.addListener(_onControllerChange);
      final s = widget.controller.state;
      _items = s.items;
      _phase = s.phase;
      _error = s.error;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    final s = widget.controller.state;
    if (identical(_items, s.items) &&
        _phase == s.phase &&
        identical(_error, s.error)) {
      return;
    }
    setState(() {
      _items = s.items;
      _phase = s.phase;
      _error = s.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = _items.length + 1;
    final state = widget.controller.state;

    Widget defaultFooter() {
      if (_phase == SmartListPhase.loadingMore ||
          (state.isSearchLoading && _items.isNotEmpty)) {
        return (widget.searchLoadingBuilder ??
            widget.loadingMoreBuilder ??
            DefaultSmartListStates.loadingMore)(context);
      }
      if (_phase == SmartListPhase.error) {
        return (widget.loadMoreErrorBuilder ??
            DefaultSmartListStates.loadMoreError)(
          context,
          _error ?? 'Unknown error',
          widget.controller.loadNextPage,
        );
      }
      return const SizedBox.shrink();
    }

    return NotificationListener<ScrollNotification>(
      onNotification: widget.onScrollNotification,
      child: ListView.separated(
        controller: widget.scrollController,
        padding: widget.padding,
        physics: widget.physics ??
            (widget.enableRefresh
                ? const AlwaysScrollableScrollPhysics()
                : null),
        reverse: widget.reverse,
        cacheExtent: widget.cacheExtent,
        itemCount: itemCount,
        separatorBuilder: (context, index) {
          if (index == _items.length - 1) return const SizedBox.shrink();
          return widget.separatorBuilder?.call(context, index) ??
              const SizedBox.shrink();
        },
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return widget.footerBuilder?.call(context, widget.controller.state) ??
                defaultFooter();
          }
          return widget.itemBuilder(context, _items[index], index);
        },
      ),
    );
  }
}
