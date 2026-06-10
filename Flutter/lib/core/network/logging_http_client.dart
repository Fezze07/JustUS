import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class LoggingHttpClient extends http.BaseClient {
  final http.Client _inner;
  final String _tag;

  LoggingHttpClient(this._inner, {required String tag}) : _tag = tag;

  String _formatRequestDescription(http.BaseRequest request) {
    final uri = request.url;
    final pathSegments = uri.pathSegments;
    if (pathSegments.isEmpty) {
      return '${request.method} ${uri.toString()}';
    }

    // Check if it's Supabase REST API
    if (pathSegments.length >= 3 &&
        pathSegments[0] == 'rest' &&
        pathSegments[1] == 'v1') {
      final tableName = pathSegments[2];
      final queryParams = uri.queryParameters;

      // Handle RPC calls (e.g. /rest/v1/rpc/function_name)
      if (tableName == 'rpc' && pathSegments.length >= 4) {
        final rpcName = pathSegments[3];
        String rpcParams = '';
        if (queryParams.isNotEmpty) {
          rpcParams = ' params($queryParams)';
        } else if (request is http.Request && request.body.isNotEmpty) {
          rpcParams = ' body(${request.body})';
        }
        return 'RPC ${request.method} $rpcName$rpcParams';
      }

      final select = queryParams['select'];
      final selectStr = select != null ? ' select($select)' : '';

      // Extract filters (any query parameter that is not select, order, limit, offset, columns, or format)
      final filters = <String>[];
      queryParams.forEach((key, value) {
        if (!['select', 'order', 'limit', 'offset', 'columns', 'format']
            .contains(key)) {
          filters.add('$key=$value');
        }
      });
      final filterStr =
          filters.isNotEmpty ? ' where(${filters.join(', ')})' : '';

      final order = queryParams['order'];
      final orderStr = order != null ? ' order($order)' : '';

      final limit = queryParams['limit'];
      final limitStr = limit != null ? ' limit($limit)' : '';

      return 'REST ${request.method} $tableName$selectStr$filterStr$orderStr$limitStr';
    }

    // Check if it's Auth API
    if (pathSegments.length >= 3 &&
        pathSegments[0] == 'auth' &&
        pathSegments[1] == 'v1') {
      final endpoint = pathSegments.sublist(2).join('/');
      return 'AUTH ${request.method} /$endpoint';
    }

    // Check if it's Storage API
    if (pathSegments.length >= 3 &&
        pathSegments[0] == 'storage' &&
        pathSegments[1] == 'v1') {
      final endpoint = pathSegments.sublist(2).join('/');
      return 'STORAGE ${request.method} /$endpoint';
    }

    // Default fallback to method + URL for general API
    return '${request.method} ${uri.toString()}';
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stopwatch = Stopwatch()..start();
    final description = _formatRequestDescription(request);

    if (kDebugMode) {
      print('[$_tag] ---> $description started...');
    }

    try {
      final response = await _inner.send(request);
      stopwatch.stop();

      if (kDebugMode) {
        print(
            '[$_tag] <----- ${response.statusCode} - (${stopwatch.elapsedMilliseconds}ms) $description');
      }
      return response;
    } catch (e) {
      stopwatch.stop();
      if (kDebugMode) {
        print(
            '[$_tag] <----- $description failed (${stopwatch.elapsedMilliseconds}ms): $e');
      }
      rethrow;
    }
  }
}
