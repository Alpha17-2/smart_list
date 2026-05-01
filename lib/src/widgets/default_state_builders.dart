import 'package:flutter/material.dart';

import '../core/smart_list_state.dart';

/// Builder signatures for the various UI states. Each is optional on
/// [SmartListView]; when omitted, the defaults below are used.
typedef SmartListWidgetBuilder = Widget Function(BuildContext context);
typedef SmartListErrorBuilder = Widget Function(
  BuildContext context,
  Object error,
  VoidCallback retry,
);
typedef SmartListItemBuilder<T> = Widget Function(
  BuildContext context,
  T item,
  int index,
);
typedef SmartListSeparatorBuilder = Widget Function(
  BuildContext context,
  int index,
);

/// A small collection of sensible default state widgets. They are deliberately
/// minimal so they look acceptable in any app while still being easy to
/// override.
class DefaultSmartListStates {
  DefaultSmartListStates._();

  static Widget loading(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(),
      ),
    );
  }

  static Widget loadingMore(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  static Widget empty(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('No items'),
      ),
    );
  }

  static Widget searchEmpty(BuildContext context, String query) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('No results for "$query"'),
      ),
    );
  }

  static Widget error(
    BuildContext context,
    Object error,
    VoidCallback retry,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32),
            const SizedBox(height: 12),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: retry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

/// Search-empty builder receives the active query so the message can include it.
typedef SmartListSearchEmptyBuilder = Widget Function(
  BuildContext context,
  String query,
);

/// Footer builder for the bottom of the list — typically used to show the
/// "loading more" indicator or an "end of list" sentinel.
typedef SmartListFooterBuilder = Widget Function(
  BuildContext context,
  SmartListState<dynamic> state,
);
