import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/network/cache.dart';

void main() {
  setUp(() => NetworkCacheManager().clear());
  tearDown(() => NetworkCacheManager().clear());

  Dio client(_ResponseAdapter adapter, {NetworkCacheManager? cache}) {
    final dio = Dio()..httpClientAdapter = adapter;
    dio.interceptors.add(cache ?? NetworkCacheManager());
    addTearDown(dio.close);
    return dio;
  }

  NetworkCache cache(Uri uri, int size) {
    return NetworkCache(
      uri: uri,
      requestHeaders: const {},
      responseHeaders: const {},
      data: '',
      time: DateTime.now(),
      size: size,
    );
  }

  test('setCache evicts older entries before exceeding memory limit', () {
    final manager = NetworkCacheManager()..clear();
    final first = Uri.parse('https://example.com/first');
    final second = Uri.parse('https://example.com/second');

    manager.setCache(cache(first, 6 * 1024 * 1024));
    manager.setCache(cache(second, 6 * 1024 * 1024));

    expect(manager.getCache(first), isNull);
    expect(manager.getCache(second), isNotNull);
    expect(manager.size, lessThanOrEqualTo(10 * 1024 * 1024));
  });

  test('setCache replacement keeps size accounting correct', () {
    final manager = NetworkCacheManager()..clear();
    final uri = Uri.parse('https://example.com/image');

    manager.setCache(cache(uri, 1024));
    manager.setCache(cache(uri, 2048));

    expect(manager.getCache(uri), isNotNull);
    expect(manager.size, 2048);
  });

  test('setCache skips entries larger than memory limit', () {
    final manager = NetworkCacheManager()..clear();
    final uri = Uri.parse('https://example.com/large-image');

    manager.setCache(cache(uri, 11 * 1024 * 1024));

    expect(manager.getCache(uri), isNull);
    expect(manager.size, 0);
  });

  test('setCache removes old entry when replacement is too large', () {
    final manager = NetworkCacheManager()..clear();
    final uri = Uri.parse('https://example.com/image');

    manager.setCache(cache(uri, 1024));
    manager.setCache(cache(uri, 11 * 1024 * 1024));

    expect(manager.getCache(uri), isNull);
    expect(manager.size, 0);
  });

  for (final header in ['authorization', 'token', 'cookie']) {
    test('cache isolates requests with different $header values', () async {
      final adapter = _ResponseAdapter();
      final dio = client(adapter);
      final first = await dio.get<String>(
        'https://example.com/private',
        options: Options(headers: {header: 'first-account'}),
      );
      final second = await dio.get<String>(
        'https://example.com/private',
        options: Options(headers: {header: 'second-account'}),
      );

      expect(adapter.requests, 2);
      expect(first.data, 'response-1');
      expect(second.data, 'response-2');
    });
  }

  test('identical request headers match regardless of casing', () async {
    final adapter = _ResponseAdapter();
    final dio = client(adapter);
    await dio.get<String>(
      'https://example.com/private',
      options: Options(headers: {'Authorization': 'same-account'}),
    );
    final cached = await dio.get<String>(
      'https://example.com/private',
      options: Options(headers: {'authorization': 'same-account'}),
    );

    expect(adapter.requests, 1);
    expect(cached.data, 'response-1');
    expect(cached.headers.value('venera-cache'), 'true');
  });

  test('cache does not mix decoded JSON and raw bytes', () async {
    final adapter = _ResponseAdapter(
      body: '{"value":1}',
      contentType: 'application/json',
    );
    final dio = client(adapter);
    final decoded = await dio.get<Map<String, dynamic>>(
      'https://example.com/data',
    );
    final raw = await dio.get<List<int>>(
      'https://example.com/data',
      options: Options(responseType: ResponseType.bytes),
    );

    expect(decoded.data, {'value': 1});
    expect(raw.data, utf8.encode('{"value":1}'));
    expect(adapter.requests, 2);
  });

  test('cached headers are independent of returned request options', () async {
    final adapter = _ResponseAdapter();
    final dio = client(adapter);
    final first = await dio.get<String>(
      'https://example.com/private',
      options: Options(headers: {'authorization': 'first-account'}),
    );
    first.requestOptions.headers['authorization'] = 'second-account';
    await dio.get<String>(
      'https://example.com/private',
      options: Options(headers: {'authorization': 'second-account'}),
    );

    expect(adapter.requests, 2);
  });

  test('adapter-added headers do not prevent cache reuse', () async {
    final adapter = _ResponseAdapter(
      addedHeaders: {'User-Agent': 'default-agent'},
    );
    final dio = client(adapter);
    await dio.get<String>('https://example.com/transport-headers');
    final second = await dio.get<String>(
      'https://example.com/transport-headers',
    );

    expect(adapter.requests, 1);
    expect(second.data, 'response-1');
    expect(second.headers.value('venera-cache'), 'true');
  });

  test('partial responses are never replayed as complete responses', () async {
    final adapter = _ResponseAdapter(statusCode: 206);
    final dio = client(adapter);
    await dio.get<String>('https://example.com/partial');
    final second = await dio.get<String>('https://example.com/partial');

    expect(adapter.requests, 2);
    expect(second.statusCode, 206);
    expect(second.headers.value('venera-cache'), isNull);
  });

  test('mutating JSON responses cannot change later cache hits', () async {
    final adapter = _ResponseAdapter(
      body: '{"items":[{"title":"original"}]}',
      contentType: 'application/json',
    );
    final dio = client(adapter);
    const url = 'https://example.com/mutable-json';
    final first = await dio.get<Map<String, dynamic>>(url);
    first.data!['items'][0]['title'] = 'changed after network response';

    final second = await dio.get<Map<String, dynamic>>(url);
    expect(second.data!['items'][0]['title'], 'original');
    second.data!['items'].clear();

    final third = await dio.get<Map<String, dynamic>>(url);
    expect(third.data!['items'][0]['title'], 'original');
    expect(adapter.requests, 1);
  });

  test(
    'mutating cached bytes and header lists does not change stored data',
    () async {
      final adapter = _ResponseAdapter(body: 'original');
      final dio = client(adapter);
      const url = 'https://example.com/mutable-bytes';
      Future<Response<List<int>>> request() => dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final first = await request();
      first.data![0] = 0;

      final second = await request();
      expect(second.data, utf8.encode('original'));
      expect(second.data, isA<Uint8List>());
      second.data![1] = 0;
      second.headers[Headers.contentTypeHeader]!.add('injected');

      final third = await request();
      expect(third.data, utf8.encode('original'));
      expect(third.headers[Headers.contentTypeHeader], ['text/plain']);
      expect(adapter.requests, 1);
    },
  );

  test(
    'GET bodies bypass URI-only caching without replacing an ordinary GET',
    () async {
      final adapter = _ResponseAdapter();
      final dio = client(adapter);
      const url = 'https://example.com/body-query';
      final ordinary = await dio.get<String>(url);
      final first = await dio.get<String>(url, data: 'first query');
      final second = await dio.get<String>(url, data: 'second query');
      final cached = await dio.get<String>(url);

      expect(ordinary.data, 'response-1');
      expect(first.data, 'response-2');
      expect(second.data, 'response-3');
      expect(cached.data, 'response-1');
      expect(adapter.requests, 3);
    },
  );

  for (final directive in ['no-store', 'no-cache']) {
    test('response Cache-Control $directive is not cached', () async {
      final adapter = _ResponseAdapter(
        responseHeaders: {
          'cache-control': ['private, $directive'],
        },
      );
      final dio = client(adapter);
      const url = 'https://example.com/uncacheable-response';
      await dio.get<String>(url);
      final second = await dio.get<String>(url);

      expect(second.data, 'response-2');
      expect(adapter.requests, 2);
      expect(NetworkCacheManager().getCache(Uri.parse(url)), isNull);
    });

    test(
      'request Cache-Control $directive bypasses reads and writes',
      () async {
        final adapter = _ResponseAdapter();
        final dio = client(adapter);
        const url = 'https://example.com/uncacheable-request';
        await dio.get<String>(url);
        final options = Options(headers: {'Cache-Control': directive});
        final second = await dio.get<String>(url, options: options);
        final third = await dio.get<String>(url, options: options);
        final cached = await dio.get<String>(url);

        expect(second.data, 'response-2');
        expect(third.data, 'response-3');
        expect(cached.data, 'response-1');
        expect(adapter.requests, 3);
      },
    );
  }

  void seedStaleCache(NetworkCacheManager manager, Uri uri) {
    manager.setCache(
      NetworkCache(
        uri: uri,
        requestHeaders: const {},
        responseHeaders: const {
          Headers.contentTypeHeader: ['text/plain'],
        },
        data: 'stale-response',
        time: DateTime.now().subtract(const Duration(minutes: 1)),
        size: 14,
        responseType: ResponseType.plain,
      ),
    );
  }

  test('failed HEAD validation falls back to GET', () async {
    var headRequests = 0;
    final manager = NetworkCacheManager.withRevalidator((options) async {
      expect(options.method, 'HEAD');
      headRequests++;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: options, statusCode: 405),
      );
    });
    final uri = Uri.parse('https://example.com/head-unsupported');
    seedStaleCache(manager, uri);
    final adapter = _ResponseAdapter();
    final dio = client(adapter, cache: manager);

    final response = await dio
        .get<String>(uri.toString())
        .timeout(const Duration(seconds: 1));

    expect(headRequests, 1);
    expect(adapter.requests, 1);
    expect(response.data, 'response-1');
    expect(response.headers.value('venera-cache'), isNull);
  });

  test('HEAD cancellation does not start a fallback GET', () async {
    final token = CancelToken();
    final manager = NetworkCacheManager.withRevalidator((options) async {
      token.cancel('stopped');
      throw token.cancelError!;
    });
    final uri = Uri.parse('https://example.com/head-canceled');
    seedStaleCache(manager, uri);
    final adapter = _ResponseAdapter();
    final dio = client(adapter, cache: manager);

    await expectLater(
      dio
          .get<String>(uri.toString(), cancelToken: token)
          .timeout(const Duration(seconds: 1)),
      throwsA(
        isA<DioException>().having(
          (error) => error.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    await pumpEventQueue();
    expect(adapter.requests, 0);
  });

  test('HEAD cancellation errors propagate without a request token', () async {
    final manager = NetworkCacheManager.withRevalidator((options) async {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
        error: 'canceled by revalidation transport',
      );
    });
    final uri = Uri.parse('https://example.com/head-cancel-error');
    seedStaleCache(manager, uri);
    final adapter = _ResponseAdapter();
    final dio = client(adapter, cache: manager);

    await expectLater(
      dio.get<String>(uri.toString()).timeout(const Duration(seconds: 1)),
      throwsA(
        isA<DioException>()
            .having((error) => error.type, 'type', DioExceptionType.cancel)
            .having((error) => error.requestOptions.method, 'method', 'GET'),
      ),
    );
    expect(adapter.requests, 0);
  });

  test('successful HEAD validation reuses cached data', () async {
    final manager = NetworkCacheManager.withRevalidator((options) async {
      return Response(
        requestOptions: options,
        statusCode: 200,
        headers: Headers.fromMap({
          Headers.contentTypeHeader: ['text/plain'],
          'date': ['new response timestamp'],
        }),
      );
    });
    final uri = Uri.parse('https://example.com/head-unchanged');
    seedStaleCache(manager, uri);
    final adapter = _ResponseAdapter();
    final dio = client(adapter, cache: manager);

    final response = await dio.get<String>(uri.toString());

    expect(adapter.requests, 0);
    expect(response.data, 'stale-response');
    expect(response.headers.value('venera-cache'), 'true');
  });
}

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter({
    this.body,
    this.contentType = 'text/plain',
    this.statusCode = 200,
    this.addedHeaders = const {},
    this.responseHeaders = const {},
  });

  final String? body;
  final String contentType;
  final int statusCode;
  final Map<String, dynamic> addedHeaders;
  final Map<String, List<String>> responseHeaders;
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    options.headers.addAll(addedHeaders);
    return ResponseBody.fromString(
      body ?? 'response-$requests',
      statusCode,
      headers: {
        Headers.contentTypeHeader: [contentType],
        ...responseHeaders,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
