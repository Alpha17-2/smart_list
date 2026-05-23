import 'package:flutter/material.dart';

import '../controller/smart_list_controller.dart';
import '../core/smart_list_phase.dart';
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
    // Skip notifications fired before the list has any meaningful extent —
    // when the content is shorter than the viewport, `maxScrollExtent` is 0
    // and `remaining` is also 0, so without this guard we'd fire on every
    // metric change even though the list has not reached its end.
    if (notification.metrics.maxScrollExtent <= 0) return false;
    final remaining =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    if (remaining <= widget.loadMoreThreshold) {
      // The controller's own `_paginationLock` is the source of truth — but
      // we still pay for the call (closure + guard chain) on every settle
      // frame during a fling. Cheap to call; harmless when it short-circuits.
      widget.controller.loadNextPage();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // The populated list body is built ONCE per outer-widget rebuild and
    // passed through `ValueListenableBuilder`'s `child:` slot. The body
    // widget reference stays stable across phase-only state changes
    // (e.g. success → loadingMore → success), so Flutter's reconciliation
    // preserves its element + state and skips re-running the itemBuilder
    // for unchanged items. The body subscribes to the controller itself
    // and only setState's when items / phase / error actually change —
    // ignoring noise like query / filters / retryAttempt notifications.
    final body = _SmartListBody<T>(
      controller: widget.controller,
      itemBuilder: widget.itemBuilder,
      separatorBuilder: widget.separatorBuilder,
      loadingMoreBuilder: widget.loadingMoreBuilder,
      loadMoreErrorBuilder: widget.loadMoreErrorBuilder,
      footerBuilder: widget.footerBuilder,
      padding: widget.padding,
      physics: widget.physics,
      reverse: widget.reverse,
      enableRefresh: widget.enableRefresh,
      loadMoreThreshold: widget.loadMoreThreshold,
      scrollController: _controller,
      onScrollNotification: _onScrollNotification,
    );

    return ValueListenableBuilder<SmartListState<T>>(
      valueListenable: widget.controller,
      builder: (context, state, child) {
        Widget content;
        // Non-list states (loading/error/empty) are centred widgets and are
        // not inherently scrollable. When refresh is enabled, they need to
        // live inside an always-scrollable viewport so the pull-to-refresh
        // gesture has something to grab. `isPlaceholder` flags those cases.
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
          // Populated path: return the pre-built body widget. The reference
          // is identical across rebuilds — Flutter preserves the subtree.
          content = child!;
        }

        if (!widget.enableRefresh) return content;

        if (isPlaceholder) {
          // Wrap the placeholder in a viewport-sized scrollable so the pull
          // gesture is always available — even on error/empty/initial-loading
          // where the content itself is just a centred widget. A `ListView`
          // with one viewport-tall child keeps every internal box bounded
          // and avoids 'Center forces an infinite height' under
          // `SingleChildScrollView`.
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

/// The populated `ListView` portion of [SmartListView], extracted into its
/// own widget so it can subscribe to the controller independently of the
/// outer chrome (loading / error / empty / refresh-indicator wrapper).
///
/// It rebuilds only when `state.items`, `state.phase`, or `state.error`
/// changes — three signals that actually affect the rendered output.
/// Other notifications (query, filters, retryAttempt, etc.) are ignored.
class _SmartListBody<T> extends StatefulWidget {
  final SmartListController<T> controller;
  final SmartListItemBuilder<T> itemBuilder;
  final SmartListSeparatorBuilder? separatorBuilder;
  final SmartListWidgetBuilder? loadingMoreBuilder;
  final SmartListErrorBuilder? loadMoreErrorBuilder;
  final SmartListFooterBuilder<T>? footerBuilder;
  final EdgeInsetsGeometry? padding;
  final ScrollPhysics? physics;
  final bool reverse;
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
    required this.loadMoreErrorBuilder,
    required this.footerBuilder,
    required this.padding,
    required this.physics,
    required this.reverse,
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

  /// Filter the controller's full-fat notification stream down to the
  /// signals that actually affect the body's rendered output. This is
  /// the core of the #26 optimisation — without it, every notification
  /// (including filter / query / retryAttempt churn) would trigger a
  /// rebuild of every visible item.
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
    final itemCount = _items.length + 1; // +1 for footer slot

    Widget defaultFooter() {
      if (_phase == SmartListPhase.loadingMore) {
        return (widget.loadingMoreBuilder ??
            DefaultSmartListStates.loadingMore)(context);
      }
      if (_phase == SmartListPhase.error) {
        // A *pagination* error: items are visible, only the next page failed.
        // Use the compact inline builder (or the user's override) so we don't
        // dump a full-screen error widget at the bottom of the list.
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
        itemCount: itemCount,
        separatorBuilder: (context, index) {
          // Suppress only the separator between the last real item and the
          // footer slot. `index == items.length - 1` is the gap that sits
          // *before* the footer; every smaller index is a gap between two
          // real items and should render normally.
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
