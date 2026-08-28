import 'package:flutter/material.dart';

import '../controller/smart_list_controller.dart';
import '../core/smart_list_state.dart';
import 'default_state_builders.dart';
import 'load_more_gate.dart';

/// Sliver counterpart of [SmartListView] for [CustomScrollView] shells.
///
/// Place inside `slivers:`; pull-to-refresh belongs on the surrounding
/// [CustomScrollView] (e.g. wrap it in [RefreshIndicator]).
class SmartListSliver<T> extends StatefulWidget {
  final SmartListController<T> controller;
  final SmartListItemBuilder<T> itemBuilder;
  final SmartListSeparatorBuilder? separatorBuilder;
  final SmartListWidgetBuilder? loadingBuilder;
  final SmartListWidgetBuilder? loadingMoreBuilder;
  final SmartListWidgetBuilder? searchLoadingBuilder;
  final SmartListWidgetBuilder? emptyBuilder;
  final SmartListSearchEmptyBuilder? searchEmptyBuilder;
  final SmartListErrorBuilder? errorBuilder;
  final SmartListFooterBuilder<T>? footerBuilder;
  final double loadMoreThreshold;
  final double? itemExtent;
  final Widget? prototypeItem;

  const SmartListSliver({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.separatorBuilder,
    this.loadingBuilder,
    this.loadingMoreBuilder,
    this.searchLoadingBuilder,
    this.emptyBuilder,
    this.searchEmptyBuilder,
    this.errorBuilder,
    this.footerBuilder,
    this.loadMoreThreshold = 240,
    this.itemExtent,
    this.prototypeItem,
  });

  @override
  State<SmartListSliver<T>> createState() => _SmartListSliverState<T>();
}

class _SmartListSliverState<T> extends State<SmartListSliver<T>> {
  final LoadMoreGate _loadMoreGate = LoadMoreGate();
  ScrollPosition? _position;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.loadInitial();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_onScrollPosition);
      _position = position;
      _position?.addListener(_onScrollPosition);
    }
  }

  @override
  void didUpdateWidget(covariant SmartListSliver<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _loadMoreGate.reset();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.controller.loadInitial();
      });
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScrollPosition);
    super.dispose();
  }

  void _onScrollPosition() {
    final position = _position;
    if (position == null) return;
    if (position.axis != Axis.vertical) return;
    final state = widget.controller.value;
    if (state.isBusy || state.hasReachedEnd) return;
    final remaining = position.maxScrollExtent - position.pixels;
    if (_loadMoreGate.shouldLoadMore(remaining, widget.loadMoreThreshold)) {
      widget.controller.loadNextPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SmartListState<T>>(
      valueListenable: widget.controller,
      builder: (context, state, _) {
        if (state.isInitialLoading) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: (widget.loadingBuilder ?? DefaultSmartListStates.loading)(
              context,
            ),
          );
        }
        if (state.hasError && state.items.isEmpty) {
          final retry = state.isSearchActive
              ? () => widget.controller.search(state.query!)
              : widget.controller.refresh;
          return SliverFillRemaining(
            hasScrollBody: false,
            child: (widget.errorBuilder ?? DefaultSmartListStates.error)(
              context,
              state.error ?? 'Unknown error',
              retry,
            ),
          );
        }
        if (state.isSearchEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: (widget.searchEmptyBuilder ??
                DefaultSmartListStates.searchEmpty)(context, state.query!),
          );
        }
        if (state.isEmpty) {
          return SliverFillRemaining(
            hasScrollBody: false,
            child: (widget.emptyBuilder ?? DefaultSmartListStates.empty)(
              context,
            ),
          );
        }
        return _buildListSliver(context, state);
      },
    );
  }

  Widget _buildListSliver(BuildContext context, SmartListState<T> state) {
    final itemCount = state.items.length + 1;

    Widget footer() {
      if (state.isLoadingMore ||
          (state.isSearchLoading && state.items.isNotEmpty)) {
        return (widget.searchLoadingBuilder ??
            widget.loadingMoreBuilder ??
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

    Widget itemBuilder(BuildContext context, int index) {
      if (index >= state.items.length) return footer();
      final child =
          widget.itemBuilder(context, state.items[index], index);
      if (widget.separatorBuilder == null || index >= state.items.length - 1) {
        return child;
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          widget.separatorBuilder!(context, index),
        ],
      );
    }

    if (widget.itemExtent != null) {
      return SliverFixedExtentList(
        itemExtent: widget.itemExtent!,
        delegate: SliverChildBuilderDelegate(
          itemBuilder,
          childCount: itemCount,
        ),
      );
    }
    if (widget.prototypeItem != null) {
      return SliverPrototypeExtentList(
        prototypeItem: widget.prototypeItem!,
        delegate: SliverChildBuilderDelegate(
          itemBuilder,
          childCount: itemCount,
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        itemBuilder,
        childCount: itemCount,
      ),
    );
  }
}
