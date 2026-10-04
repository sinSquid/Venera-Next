import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:venera_next/network/cookie_jar.dart';

void main() {
  late CookieJarSql jar;

  setUp(() {
    jar = CookieJarSql(':memory:');
  });

  tearDown(() => jar.dispose());

  test('secure cookies are sent only over HTTPS', () {
    jar.saveFromResponse(Uri.parse('https://example.com/login'), [
      Cookie('session', 'private')..secure = true,
      Cookie('theme', 'dark'),
    ]);

    expect(
      jar.loadForRequest(Uri.parse('https://example.com/')).map((c) => c.name),
      unorderedEquals(['session', 'theme']),
    );
    expect(
      jar.loadForRequestCookieHeader(Uri.parse('http://example.com/')),
      'theme=dark',
    );
  });

  test('cookie paths match exact paths and children at a slash boundary', () {
    jar.saveFromResponse(Uri.parse('https://example.com/foo/login'), [
      Cookie('scoped', 'value')..path = '/foo',
    ]);

    for (final path in ['/foo', '/foo/', '/foo/child']) {
      expect(
        jar.loadForRequestCookieHeader(Uri.parse('https://example.com$path')),
        'scoped=value',
        reason: path,
      );
    }
    for (final path in ['/foobar', '/foo-bar', '/fo', '/']) {
      expect(
        jar.loadForRequestCookieHeader(Uri.parse('https://example.com$path')),
        isEmpty,
        reason: path,
      );
    }
  });

  test('trailing slash cookie paths retain their boundary', () {
    jar.saveFromResponse(Uri.parse('https://example.com/foo/login'), [
      Cookie('scoped', 'value')..path = '/foo/',
    ]);

    expect(
      jar.loadForRequestCookieHeader(Uri.parse('https://example.com/foo/')),
      'scoped=value',
    );
    expect(
      jar.loadForRequestCookieHeader(
        Uri.parse('https://example.com/foo/child'),
      ),
      'scoped=value',
    );
    expect(
      jar.loadForRequestCookieHeader(Uri.parse('https://example.com/foo')),
      isEmpty,
    );
  });

  test('Max-Age zero removes a cookie even when Expires is in the future', () {
    final uri = Uri.parse('https://example.com/');
    jar.saveFromResponseCookieHeader(uri, ['session=active; Path=/']);
    expect(jar.loadForRequestCookieHeader(uri), 'session=active');

    jar.saveFromResponseCookieHeader(uri, [
      'session=deleted; Path=/; Max-Age=0; Expires=Tue, 19 Jan 2038 03:14:07 GMT',
    ]);

    expect(jar.loadForRequestCookieHeader(uri), isEmpty);
  });

  test('positive Max-Age takes precedence over an expired Expires value', () {
    final uri = Uri.parse('https://example.com/');
    jar.saveFromResponseCookieHeader(uri, [
      'session=active; Path=/; Max-Age=3600; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
    ]);

    final cookie = jar.loadForRequest(uri).single;
    expect(cookie.value, 'active');
    expect(cookie.expires, isNotNull);
    expect(cookie.expires!.isAfter(DateTime.now()), isTrue);
    expect(
      cookie.expires!.isBefore(DateTime.now().add(const Duration(hours: 2))),
      isTrue,
    );
  });

  test('negative Max-Age does not create a persistent cookie', () {
    final uri = Uri.parse('https://example.com/');
    jar.saveFromResponseCookieHeader(uri, ['session=expired; Max-Age=-1']);
    expect(jar.loadForRequestCookieHeader(uri), isEmpty);
  });
}
