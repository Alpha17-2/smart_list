import 'dart:convert';
import 'dart:io';

import 'package:smart_list/smart_list.dart';

/// Example-only JSON file cache. Copy into your app — this is not a core
/// package dependency. [T] must be JSON-encodable (or provide [encode]/[decode]).
class JsonFileCacheStore<T> implements SmartListCacheStore<T> {
  JsonFileCacheStore({
    required this.file,
    required this.decode,
    Object? Function(T value)? encode,
  }) : encode = encode ?? ((value) => value);

  final File file;
  final T Function(Object? json) decode;
  final Object? Function(T value) encode;

  Map<String, dynamic> _load() {
    if (!file.existsSync()) return <String, dynamic>{};
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  void _save(Map<String, dynamic> data) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(data));
  }

  String _key(SmartListCacheKey key) =>
      '${key.listId}|${key.query}|${key.page}|${key.cursor}|${key.filters}';

  @override
  SmartListPage<T>? read(SmartListCacheKey key) {
    final raw = _load()[_key(key)];
    if (raw is! Map) return null;
    final items = (raw['items'] as List<dynamic>).map(decode).toList();
    return SmartListPage<T>(
      items: items,
      hasMore: raw['hasMore'] as bool?,
      nextCursor: raw['nextCursor'] as String?,
    );
  }

  @override
  void write(SmartListCacheKey key, SmartListPage<T> page) {
    final data = _load();
    data[_key(key)] = {
      'items': page.items.map(encode).toList(),
      'hasMore': page.hasMore,
      'nextCursor': page.nextCursor,
    };
    _save(data);
  }

  @override
  void invalidate(SmartListCacheKey key) {
    final data = _load()..remove(_key(key));
    _save(data);
  }

  @override
  void invalidateQuery(String? query) {
    final data = _load();
    data.removeWhere((k, _) => k.split('|').elementAt(1) == '${query ?? ''}');
    _save(data);
  }

  @override
  void invalidateScope({
    Object? listId,
    String? query,
    Map<String, Object?> filters = const {},
  }) {
    final data = _load();
    data.removeWhere((k, _) {
      final parts = k.split('|');
      if (parts.length < 5) return false;
      if (listId != null && parts[0] != '$listId') return false;
      if (parts[1] != '${query ?? ''}') return false;
      return true;
    });
    _save(data);
  }

  @override
  void clear() {
    if (file.existsSync()) file.deleteSync();
  }
}
