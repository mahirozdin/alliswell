import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';

/// Mirrors the API's tag shape (apps/api routes/tags.js). Management UI is a
/// later task — v1 needs tags for task labeling only.
class Tag {
  const Tag({
    required this.id,
    required this.name,
    required this.slug,
    required this.colorRgb,
  });

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
    id: json['id'] as String,
    name: json['name'] as String,
    slug: json['slug'] as String,
    colorRgb: json['colorRgb'] as String,
  );

  final String id;
  final String name;
  final String slug;
  final String colorRgb;
}

/// Tags of the current workspace (server-sorted by name).
final tagsProvider = FutureProvider<List<Tag>>((ref) async {
  final workspaces = await ref.watch(workspacesProvider.future);
  if (workspaces.isEmpty) return const [];
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get<Map<String, dynamic>>(
      '/api/v1/workspaces/${workspaces.first.id}/tags',
    );
    final items = (res.data?['items'] as List?) ?? const [];
    return items.map((t) => Tag.fromJson(t as Map<String, dynamic>)).toList();
  } on DioException catch (e) {
    throw asApiException(e);
  }
});
