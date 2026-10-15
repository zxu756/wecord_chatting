import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/shared/api/supabase_providers.dart';

/// Calls a database function and returns its result.
typedef CircleRpc =
    Future<Object?> Function(String functionName, Map<String, dynamic> params);

/// The RPC used by the announcement, template, tag and bot repositories;
/// tests override it. Without an initialized Supabase client every call
/// fails with a [StateError].
final circleRpcProvider = Provider<CircleRpc>((ref) {
  return (functionName, params) async {
    try {
      final client = ref.read(supabaseClientProvider);
      return await client.rpc<Object?>(functionName, params: params);
    } on AssertionError {
      throw StateError('Supabase must be initialized first.');
    }
  };
});

/// Rows of a function returning a set or a table.
List<Map<String, dynamic>> rpcRows(Object? result) {
  if (result is List) {
    return [
      for (final row in result)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }
  return const [];
}

/// A function's single object result.
Map<String, dynamic> rpcObject(Object? result) {
  if (result is Map) {
    return Map<String, dynamic>.from(result);
  }
  if (result is List && result.isNotEmpty && result.first is Map) {
    return Map<String, dynamic>.from(result.first as Map);
  }
  throw StateError('Unexpected response.');
}
