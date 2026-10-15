import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/models/circle.dart';

/// A channel in a template's outline.
class CircleTemplateChannel {
  const CircleTemplateChannel({
    required this.name,
    required this.kind,
    this.categoryKey,
  });

  factory CircleTemplateChannel.fromJson(Map<String, dynamic> json) {
    return CircleTemplateChannel(
      name: json['name'] as String? ?? '',
      kind: CircleChannelKind.fromJson(json['kind']),
      categoryKey: json['category_key'] as String?,
    );
  }

  final String name;
  final CircleChannelKind kind;
  final String? categoryKey;
}

/// A category in a template's outline.
class CircleTemplateCategory {
  const CircleTemplateCategory({required this.key, required this.name});

  factory CircleTemplateCategory.fromJson(Map<String, dynamic> json) {
    return CircleTemplateCategory(
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? '',
    );
  }

  final String key;
  final String name;
}

/// A role in a template's outline.
class CircleTemplateRole {
  const CircleTemplateRole({required this.name, this.color});

  factory CircleTemplateRole.fromJson(Map<String, dynamic> json) {
    return CircleTemplateRole(
      name: json['name'] as String? ?? '',
      color: (json['color'] as num?)?.toInt(),
    );
  }

  final String name;

  /// 0xRRGGBB, or null.
  final int? color;
}

/// A saved circle layout that new circles can start from.
class CircleTemplate {
  const CircleTemplate({
    required this.id,
    required this.circleId,
    required this.code,
    required this.name,
    required this.updatedAt,
    this.circleName = '',
    this.description,
    this.creatorName,
    this.usageCount = 0,
    this.roleCount = 0,
    this.categoryCount = 0,
    this.channelCount = 0,
    this.categories = const [],
    this.channels = const [],
    this.roles = const [],
  });

  factory CircleTemplate.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) parse) {
      return [
        for (final item in json[key] as List<dynamic>? ?? const [])
          if (item is Map) parse(Map<String, dynamic>.from(item)),
      ];
    }

    return CircleTemplate(
      id: json['id'] as String,
      circleId: json['circle_id'] as String,
      circleName: json['circle_name'] as String? ?? '',
      code: json['code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      creatorName: json['creator_name'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String).toUtc(),
      usageCount: (json['usage_count'] as num?)?.toInt() ?? 0,
      roleCount: (json['role_count'] as num?)?.toInt() ?? 0,
      categoryCount: (json['category_count'] as num?)?.toInt() ?? 0,
      channelCount: (json['channel_count'] as num?)?.toInt() ?? 0,
      categories: list('categories', CircleTemplateCategory.fromJson),
      channels: list('channels', CircleTemplateChannel.fromJson),
      roles: list('roles', CircleTemplateRole.fromJson),
    );
  }

  static const maxNameLength = 100;
  static const maxDescriptionLength = 120;

  final String id;
  final String circleId;

  /// The circle the template was saved from.
  final String circleName;

  /// Shared to let others create a circle from the template.
  final String code;
  final String name;
  final String? description;
  final String? creatorName;

  /// When the layout was last saved (created or synced).
  final DateTime updatedAt;

  /// How many circles were created from it.
  final int usageCount;
  final int roleCount;
  final int categoryCount;
  final int channelCount;

  /// The outline, in previews only.
  final List<CircleTemplateCategory> categories;
  final List<CircleTemplateChannel> channels;
  final List<CircleTemplateRole> roles;
}

/// Pulls a template code out of what someone pasted: the code itself, or
/// any text ending with it (such as a link). Null when there is none.
String? parseCircleTemplateCode(String input) {
  final match = RegExp(r'([A-Za-z0-9]{10})\W*$').firstMatch(input.trim());
  return match?.group(1)?.toLowerCase();
}

final circleTemplateRepositoryProvider = Provider<CircleTemplateRepository>((
  ref,
) {
  return CircleTemplateRepository(ref.watch(circleRpcProvider));
});

/// A circle's template, for its managers; null when it has none.
final circleTemplateProvider = FutureProvider.autoDispose
    .family<CircleTemplate?, String>((ref, circleId) {
      return ref.watch(circleTemplateRepositoryProvider).getTemplate(circleId);
    });

class CircleTemplateRepository {
  const CircleTemplateRepository(this._rpc);

  final CircleRpc _rpc;

  Future<CircleTemplate?> getTemplate(String circleId) async {
    final result = await _rpc('get_circle_template', {
      'target_circle_id': circleId,
    });
    return result == null ? null : CircleTemplate.fromJson(rpcObject(result));
  }

  Future<CircleTemplate> createTemplate({
    required String circleId,
    required String name,
    String? description,
  }) async {
    final result = await _rpc('create_circle_template', {
      'target_circle_id': circleId,
      'template_name': name.trim(),
      'template_description': description?.trim(),
    });
    return CircleTemplate.fromJson(rpcObject(result));
  }

  /// Saves the circle's current layout into the template, with a new name
  /// and description when given.
  Future<CircleTemplate> syncTemplate(
    String templateId, {
    String? name,
    String? description,
  }) async {
    final result = await _rpc('sync_circle_template', {
      'target_template_id': templateId,
      'template_name': name?.trim(),
      'template_description': description?.trim(),
    });
    return CircleTemplate.fromJson(rpcObject(result));
  }

  Future<void> deleteTemplate(String templateId) async {
    await _rpc('delete_circle_template', {'target_template_id': templateId});
  }

  /// The template behind [code], with its outline.
  Future<CircleTemplate> previewTemplate(String code) async {
    final result = await _rpc('preview_circle_template', {
      'template_code': code,
    });
    return CircleTemplate.fromJson(rpcObject(result));
  }

  /// Creates a circle named [name] from the template; returns its id.
  Future<String> createCircleFromTemplate({
    required String code,
    required String name,
  }) async {
    final result = await _rpc('create_circle_from_template', {
      'template_code': code,
      'circle_name': name.trim(),
    });
    return result as String;
  }
}
