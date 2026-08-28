import 'dart:async';
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
      home: const ExampleHome(),
    );
  }
}

class Post {
  final int id;
  final String title;
  final String body;
  Post({required this.id, required this.title, required this.body});
}

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

  Future<SmartListPage<Post>> fetch(
    SmartListPageRequest req,
    SmartListCancelToken cancel,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    cancel.throwIfCancelled();

    if (_rng.nextInt(20) == 0) {
      throw TimeoutException('Network glitch — please retry');
    }

    Iterable<Post> source = _all;
    if (req.query != null && req.query!.isNotEmpty) {
      final q = req.query!.toLowerCase();
      source = source.where((p) => p.title.toLowerCase().contains(q));
    }

    final list = source.toList();
    final start = req.cursor != null
        ? int.parse(req.cursor!)
        : (req.page - 1) * req.pageSize;
    if (start >= list.length) return const SmartListPage(items: []);
    final end = (start + req.pageSize).clamp(0, list.length);
    final slice = list.sublist(start, end);
    final hasMore = end < list.length;
    return SmartListPage<Post>(
      items: slice,
      hasMore: hasMore,
      nextCursor: hasMore ? '$end' : null,
      totalCount: list.length,
    );
  }
}

class ExampleHome extends StatelessWidget {
  const ExampleHome({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SmartList 1.0'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'ListView'),
              Tab(text: 'Sliver'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            PostsListTab(),
            PostsSliverTab(),
          ],
        ),
      ),
    );
  }
}

class PostsListTab extends StatefulWidget {
  const PostsListTab({super.key});

  @override
  State<PostsListTab> createState() => _PostsListTabState();
}

class _PostsListTabState extends State<PostsListTab>
    with AutomaticKeepAliveClientMixin {
  final _api = FakePostsApi();
  late final SmartListController<Post> _controller;
  final _searchController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = SmartListController<Post>.simple(
      fetcher: _api.fetch,
      pageSize: 15,
      uniqueKey: (p) => p.id,
      listId: 'posts-list',
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
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
        Expanded(
          child: SmartListView<Post>(
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
              subtitle: Text(
                post.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class PostsSliverTab extends StatefulWidget {
  const PostsSliverTab({super.key});

  @override
  State<PostsSliverTab> createState() => _PostsSliverTabState();
}

class _PostsSliverTabState extends State<PostsSliverTab>
    with AutomaticKeepAliveClientMixin {
  final _api = FakePostsApi();
  late final SmartListController<Post> _controller;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _controller = SmartListController<Post>(
      fetcher: _api.fetch,
      strategyBuilder: () => CursorPaginationStrategy<Post>(pageSize: 15),
      uniqueKey: (p) => p.id,
      listId: 'posts-sliver',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Cursor pagination inside CustomScrollView'),
            ),
          ),
          SmartListSliver<Post>(
            controller: _controller,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, post, __) => ListTile(
              leading: CircleAvatar(child: Text('${post.id}')),
              title: Text(post.title),
            ),
          ),
        ],
      ),
    );
  }
}
