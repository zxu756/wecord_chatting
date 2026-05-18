import 'package:flutter_riverpod/flutter_riverpod.dart';

final circlesRepositoryProvider = Provider<CirclesRepository>((ref) {
  return const CirclesRepository();
});

class CirclesRepository {
  const CirclesRepository();

  Future<List<CircleSummary>> listCircles() async {
    return const [];
  }
}

class CircleSummary {
  const CircleSummary({
    required this.id,
    required this.name,
    required this.memberCount,
  });

  final String id;
  final String name;
  final int memberCount;
}
