import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_exception.dart';
import '../auth/providers.dart';

/// A workspace as returned by `GET /api/v1/me` (id + display data + my role).
class WorkspaceSummary {
  const WorkspaceSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.colorRgb,
    required this.role,
    this.icon,
  });

  factory WorkspaceSummary.fromJson(Map<String, dynamic> json) =>
      WorkspaceSummary(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        colorRgb: (json['colorRgb'] as String?) ?? '#2563EB',
        icon: json['icon'] as String?,
        role: json['role'] as String,
      );

  final String id;
  final String name;
  final String slug;
  final String colorRgb;
  final String? icon;
  final String role;
}

/// The signed-in user's workspaces. Re-fetches whenever the session changes;
/// empty while signed out.
final workspacesProvider = FutureProvider<List<WorkspaceSummary>>((ref) async {
  final session = ref.watch(authControllerProvider).value;
  if (session == null) return const [];
  final dio = ref.watch(apiClientProvider);
  try {
    final res = await dio.get<Map<String, dynamic>>('/api/v1/me');
    final list = (res.data?['workspaces'] as List?) ?? const [];
    return list
        .map((w) => WorkspaceSummary.fromJson(w as Map<String, dynamic>))
        .toList();
  } on DioException catch (e) {
    throw asApiException(e);
  }
});

/// v1 works in a single workspace: the first one (the personal space created
/// at registration). Multi-workspace switching arrives with Epic 09+.
final currentWorkspaceProvider = Provider<AsyncValue<WorkspaceSummary?>>(
  (ref) => ref
      .watch(workspacesProvider)
      .whenData((list) => list.isEmpty ? null : list.first),
);
