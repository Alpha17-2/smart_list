import 'dart:math';

import 'package:flutter/material.dart';
import 'package:smart_list/smart_list.dart';

void main() => runApp(const SmartListExampleApp());

class SmartListExampleApp extends StatelessWidget {
  const SmartListExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartList Example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const PostsPage(),
    );
  }
}

// A model. In a real app this would come from your API layer.
class Post {
  final int id;
  final String title;
  final String body;
  Post({required this.id, required this.title, required this.body});
}

/// A fake paginated API to exercise the controller. It demonstrates:
///   * page-based pagination with a known total
///   * server-side search (case-insensitive substring)
///   * artificial latency + occasional flaky errors
class FakePostsApi {
  final List<Post> _all = List<Post>.generate(
    87,
    (i) => Post(
      id: i + 1,
      title: 'Post #${i + 1}',
      body: 'This is the body of post number ${i + 1}.',
    ),
  );
  final _rng = Random();

  Future<SmartListPage<Post>> fetch(SmartListPageRequest req) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));

    // Simulate occasional transient failure to exercise retry/error UI.
    if (_rng.nextInt(20) == 0) {
      throw Exception('Network glitch — please retry');
    }

    Iterable<Post> source = _all;
    if (req.query != null && req.query!.isNotEmpty) {
      final q = req.query!.toLowerCase();
      source = source.where((p) => p.title.toLowerCase().contains(q));
    }

    final list = source.toList();
    final start = (req.page - 1) * req.pageSize;
    if (start >= list.length) return const SmartListPage(items: []);
    final end = (start + req.pageSize).clamp(0, list.length);
    final slice = list.sublist(start, end);
    return SmartListPage<Post>(
      items: slice,
      hasMore: end < list.length,
      totalCount: list.length,
    );
  }
}

class PostsPage extends StatefulWidget {
  const PostsPage({super.key});

  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> {
  final _api = FakePostsApi();
  late final SmartListController<Post> _controller;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = SmartListController<Post>.simple(
      fetcher: _api.fetch,
      pageSize: 15,
      uniqueKey: (p) => p.id,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartList demo'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search posts…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: ValueListenableBuilder(
                  valueListenable: _controller,
                  builder: (_, state, __) {
                    if (!state.isSearchActive) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _controller.clearSearch();
                      },
                    );
                  },
                ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: _controller.search,
            ),
          ),
        ),
      ),
      body: SmartListView<Post>(
        controller: _controller,
        emptyBuilder: (context) {
          return const Center(
            child: Text('No posts found. Try a different search?'),
          );
        },
        padding: const EdgeInsets.symmetric(vertical: 8),
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, post, __) => ListTile(
          leading: CircleAvatar(child: Text('${post.id}')),
          title: Text(post.title),
          subtitle: Text(post.body, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}
