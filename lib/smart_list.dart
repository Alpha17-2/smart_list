/// SmartList — a unified, production-ready abstraction for paginated,
/// searchable, cached lists in Flutter.
///
/// See the package README and the `example/` app for end-to-end usage.
/// The 2-line "happy path":
///
/// ```dart
/// final controller = SmartListController.simple(
///   fetcher: (req) async => SmartListPage(items: await api.fetch(req.page)),
/// );
///
/// SmartListView<Post>(
///   controller: controller,
///   itemBuilder: (context, post, _) => PostCard(post),
/// );
/// ```
library;

// Core
export 'src/core/smart_list_phase.dart';
export 'src/core/smart_list_state.dart';
export 'src/core/smart_list_exception.dart';
export 'src/core/typedefs.dart';

// Pagination
export 'src/pagination/pagination_request.dart';
export 'src/pagination/pagination_response.dart';
export 'src/pagination/pagination_strategy.dart';
export 'src/pagination/page_pagination_strategy.dart';
export 'src/pagination/cursor_pagination_strategy.dart';
export 'src/pagination/offset_pagination_strategy.dart';

// Cache
export 'src/cache/cache_key.dart';
export 'src/cache/cache_store.dart';
export 'src/cache/memory_cache_store.dart';

// Utils
export 'src/utils/debouncer.dart';
export 'src/utils/request_token.dart';
export 'src/utils/retry_policy.dart';

// Controller
export 'src/controller/smart_list_controller.dart';

// Widgets
export 'src/widgets/smart_list_view.dart';
export 'src/widgets/default_state_builders.dart';
