import 'dart:typed_data';

import 'package:venera_next/network/app_dio.dart';

class NetworkCache {
  final Uri uri;

  final Map<String, dynamic> requestHeaders;

  final Map<String, List<String>> responseHeaders;

  final Object? data;

  final DateTime time;

  final int size;

  final ResponseType responseType;

  const NetworkCache({
    required this.uri,
    required this.requestHeaders,
    required this.responseHeaders,
    required this.data,
    required this.time,
    required this.size,
    this.responseType = ResponseType.json,
  });
}

class NetworkCacheManager extends Interceptor {
  NetworkCacheManager._() : this.withRevalidator(_revalidateWithAppDio);

  /// An independent cache with a caller-provided HEAD request implementation.
  NetworkCacheManager.withRevalidator(this._revalidate);

  final Future<Response<dynamic>> Function(RequestOptions) _revalidate;

  static Future<Response<dynamic>> _revalidateWithAppDio(
    RequestOptions options,
  ) async {
    final dio = AppDio();
    try {
      return await dio.fetch(options);
    } finally {
      dio.close();
    }
  }

  static final NetworkCacheManager instance = NetworkCacheManager._();

  factory NetworkCacheManager() => instance;

  final Map<Uri, NetworkCache> _cache = {};

  int size = 0;

  NetworkCache? getCache(Uri uri) {
    return _cache[uri];
  }

  static const _maxCacheSize = 10 * 1024 * 1024;
  static const _requestHeadersKey = 'venera-cache-request-headers';

  static Map<String, dynamic> _copyRequestHeaders(
    Map<String, dynamic> headers,
  ) => headers.map(
    (key, value) => MapEntry(key, value is List ? List.of(value) : value),
  );

  static Map<String, List<String>> _copyResponseHeaders(
    Map<String, List<String>> headers,
  ) => headers.map((key, value) => MapEntry(key, List<String>.of(value)));

  static Object? _copyData(Object? data) {
    if (data is Uint8List) return Uint8List.fromList(data);
    if (data is List<int>) return List<int>.of(data);
    if (data is List) return data.map(_copyData).toList();
    if (data is Map<String, dynamic>) {
      return data.map((key, value) => MapEntry(key, _copyData(value)));
    }
    if (data is Map) {
      return data.map((key, value) => MapEntry(key, _copyData(value)));
    }
    return data;
  }

  static bool _forbidsCache(Map<String, dynamic> headers) {
    return headers.entries.any((entry) {
      if (entry.key.toLowerCase() != 'cache-control') return false;
      final value = entry.value;
      final directives = (value is List ? value.join(',') : value.toString())
          .toLowerCase()
          .split(',')
          .map((directive) => directive.trim().split('=').first.trim());
      return directives.any(
        (value) => value == 'no-store' || value == 'no-cache',
      );
    });
  }

  void setCache(NetworkCache cache) {
    if (_cache.containsKey(cache.uri)) {
      size -= _cache[cache.uri]!.size;
      _cache.remove(cache.uri);
    }
    if (cache.size > _maxCacheSize) {
      return;
    }
    while (_cache.isNotEmpty && size + cache.size > _maxCacheSize) {
      size -= _cache.values.first.size;
      _cache.remove(_cache.keys.first);
    }
    _cache[cache.uri] = cache;
    size += cache.size;
  }

  void removeCache(Uri uri) {
    var cache = _cache[uri];
    if (cache != null) {
      size -= cache.size;
    }
    _cache.remove(uri);
  }

  void clear() {
    _cache.clear();
    size = 0;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.requestOptions.method != "GET") {
      return handler.next(err);
    }
    return handler.next(err);
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.method != "GET") {
      return handler.next(options);
    }
    final cacheTime = options.headers.remove('cache-time');
    if (options.data != null || _forbidsCache(options.headers)) {
      return handler.next(options);
    }
    // Later interceptors and adapters may add transport headers, such as the
    // default User-Agent. Compare the same request stage on subsequent calls.
    options.extra[_requestHeadersKey] = _copyRequestHeaders(options.headers);
    var cache = getCache(options.uri);
    if (cache == null ||
        cache.responseType != options.responseType ||
        !compareHeaders(options.headers, cache.requestHeaders)) {
      return handler.next(options);
    } else if (cacheTime == 'no') {
      removeCache(options.uri);
      return handler.next(options);
    }
    var time = DateTime.now();
    var diff = time.difference(cache.time);
    if (cacheTime == 'long' && diff < const Duration(hours: 6)) {
      return handler.resolve(
        Response(
          requestOptions: options,
          data: _copyData(cache.data),
          headers: Headers.fromMap(_copyResponseHeaders(cache.responseHeaders))
            ..set('venera-cache', 'true'),
          statusCode: 200,
        ),
      );
    } else if (diff < const Duration(seconds: 5)) {
      return handler.resolve(
        Response(
          requestOptions: options,
          data: _copyData(cache.data),
          headers: Headers.fromMap(_copyResponseHeaders(cache.responseHeaders))
            ..set('venera-cache', 'true'),
          statusCode: 200,
        ),
      );
    } else if (diff < const Duration(hours: 2)) {
      var o = options.copyWith(method: "HEAD");
      try {
        final response = await _revalidate(o);
        if (response.statusCode == 200 &&
            compareHeaders(
              cache.responseHeaders,
              response.headers.map,
              responseHeaders: true,
            )) {
          return handler.resolve(
            Response(
              requestOptions: options,
              data: _copyData(cache.data),
              headers: Headers.fromMap(
                _copyResponseHeaders(cache.responseHeaders),
              )..set('venera-cache', 'true'),
              statusCode: 200,
            ),
          );
        }
      } catch (error) {
        final canceled = options.cancelToken?.cancelError;
        if (canceled != null) {
          return handler.reject(canceled.copyWith(requestOptions: options));
        }
        if (error is DioException && error.type == DioExceptionType.cancel) {
          return handler.reject(error.copyWith(requestOptions: options));
        }
        // HEAD is only an optimization; servers may reject it even when GET
        // succeeds. Always finish the interceptor by falling back to GET.
      }
    }
    removeCache(options.uri);
    handler.next(options);
  }

  static bool compareHeaders(
    Map<String, dynamic> a,
    Map<String, dynamic> b, {
    bool responseHeaders = false,
  }) {
    a = a.map((key, value) => MapEntry(key.toLowerCase(), value));
    b = b.map((key, value) => MapEntry(key.toLowerCase(), value));
    final shouldIgnore = [
      'cache-time',
      'prevent-parallel',
      if (responseHeaders) ...[
        'date',
        'x-varnish',
        'cf-ray',
        'connection',
        'vary',
        'content-encoding',
        'report-to',
        'server-timing',
        'set-cookie',
        'cf-cache-status',
        'cf-request-id',
      ],
    ];
    for (var key in shouldIgnore) {
      a.remove(key);
      b.remove(key);
    }
    if (a.length != b.length) {
      return false;
    }
    for (var key in a.keys) {
      if (a[key] is List && b[key] is List) {
        if (a[key].length != b[key].length) {
          return false;
        }
        for (var i = 0; i < a[key].length; i++) {
          if (a[key][i] != b[key][i]) {
            return false;
          }
        }
      } else if (a[key] != b[key]) {
        return false;
      }
    }
    return true;
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (response.requestOptions.method != "GET" ||
        response.requestOptions.data != null ||
        _forbidsCache(response.requestOptions.headers)) {
      return handler.next(response);
    }
    if (_forbidsCache(response.headers.map)) {
      removeCache(response.requestOptions.uri);
      return handler.next(response);
    }
    if (response.statusCode != 200) {
      return handler.next(response);
    }
    if (isMalformedExpectedJsonResponse(response)) {
      removeCache(response.requestOptions.uri);
      return handler.next(response);
    }
    var size = _calculateSize(response.data);
    if (size != null && size < 1024 * 1024 && size > 0) {
      var cache = NetworkCache(
        uri: response.requestOptions.uri,
        requestHeaders: _copyRequestHeaders(
          response.requestOptions.extra.remove(_requestHeadersKey)
                  as Map<String, dynamic>? ??
              response.requestOptions.headers,
        ),
        responseHeaders: _copyResponseHeaders(response.headers.map),
        data: _copyData(response.data),
        time: DateTime.now(),
        size: size,
        responseType: response.requestOptions.responseType,
      );
      setCache(cache);
    }
    handler.next(response);
  }

  static int? _calculateSize(Object? data) {
    if (data == null) {
      return 0;
    }
    if (data is List<int>) {
      return data.length;
    }
    if (data is Uint8List) {
      return data.length;
    }
    if (data is String) {
      if (data.trim().isEmpty) {
        return 0;
      }
      if (data.length < 512 && data.contains("IP address")) {
        return 0;
      }
      return data.length * 4;
    }
    if (data is Map) {
      return data.toString().length * 4;
    }
    return null;
  }
}
