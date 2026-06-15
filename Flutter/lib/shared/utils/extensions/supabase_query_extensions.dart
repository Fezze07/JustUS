import 'package:supabase_flutter/supabase_flutter.dart';

extension SupabaseQueryExtensions<T> on PostgrestFilterBuilder<T> {
  PostgrestFilterBuilder<T> maybeFilterIn(
    String column,
    List<Object> values,
  ) {
    if (values.isEmpty) return this;
    return inFilter(column, values);
  }

  PostgrestFilterBuilder<T> maybeEq(
    String column,
    Object? value,
  ) {
    if (value == null) return this;
    return eq(column, value);
  }

  PostgrestFilterBuilder<T> maybeGt(
    String column,
    Object? value,
  ) {
    if (value == null) return this;
    return gt(column, value);
  }
}

extension SupabaseQueryTransformer<T> on PostgrestTransformBuilder<T> {
  Future<List<Map<String, dynamic>>> toList() async {
    final result = await this;
    return List<Map<String, dynamic>>.from(result as List);
  }

  Future<Map<String, dynamic>?> toSingle() async {
    return await maybeSingle();
  }
}
