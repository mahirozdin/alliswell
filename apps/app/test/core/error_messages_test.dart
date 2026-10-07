import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alliswell/src/core/api_exception.dart';
import 'package:alliswell/src/core/error_messages.dart';
import 'package:alliswell/src/features/auth/data/models.dart';
import 'package:alliswell/src/features/auth/ui/auth_messages.dart';
import 'package:alliswell/src/i18n/i18n.dart';

/// OPH-357 (UI-AUDIT #24): a failure with no `code` — the limiter's old 429,
/// a 404 from a proxy, a 5xx — reached Turkish screens as the client's English
/// placeholder "Unexpected server response", and the panels printed
/// `ApiException(HTTP_429): …` verbatim.
DioException _failure(
  int status, {
  Object? data,
  Map<String, List<String>> headers = const {},
}) {
  final options = RequestOptions(path: '/api/v1/x');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
      data: data,
      headers: Headers.fromMap(headers),
    ),
  );
}

void main() {
  tearDown(() => AwI18n.instance.setActiveCached(const Locale('en')));

  group('asApiException', () {
    test('UI-AUDIT #24: RATE_LIMITED carries the wait from the body', () {
      final e = asApiException(
        _failure(
          429,
          data: {
            'statusCode': 429,
            'code': 'RATE_LIMITED',
            'error': 'Too Many Requests',
            'message': 'Rate limit exceeded, retry in 42 seconds',
            'retryAfter': 42,
          },
          headers: {
            'retry-after': ['42'],
          },
        ),
      );
      expect(e.code, 'RATE_LIMITED');
      expect(e.statusCode, 429);
      expect(e.retryAfter, 42);
    });

    test('UI-AUDIT #24: an older server\'s codeless 429 still yields its '
        'Retry-After', () {
      final e = asApiException(
        _failure(
          429,
          data: {
            'statusCode': 429,
            'error': 'Too Many Requests',
            'message': 'Rate limit exceeded, retry in 58 seconds',
          },
          headers: {
            'retry-after': ['58'],
          },
        ),
      );
      expect(e.code, 'HTTP_429');
      expect(e.retryAfter, 58);
    });

    test('no response is a NETWORK_ERROR', () {
      final e = asApiException(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(e.code, 'NETWORK_ERROR');
      expect(e.statusCode, isNull);
    });
  });

  group('localizedError', () {
    for (final locale in const [Locale('tr'), Locale('en')]) {
      final lang = locale.languageCode;

      test('UI-AUDIT #24 [$lang]: a 429 says how long to wait', () {
        AwI18n.instance.setActiveCached(locale);
        final message = localizedError(
          const ApiException(
            'RATE_LIMITED',
            'Rate limit exceeded, retry in 42 seconds',
            statusCode: 429,
            retryAfter: 42,
          ),
        );
        expect(message, 'error.RATE_LIMITED'.tr(args: {'seconds': '42'}));
        expect(message, contains('42'));
        expect(message, isNot(contains('Rate limit exceeded')));
      });

      test('UI-AUDIT #24 [$lang]: codeless statuses are translated, never '
          'the placeholder', () {
        AwI18n.instance.setActiveCached(locale);
        String of(int status) => localizedError(
          asApiException(_failure(status, data: '<html>busy</html>')),
        );
        expect(of(429), 'error.HTTP_429'.tr());
        expect(of(404), 'error.notFound'.tr());
        expect(of(500), 'error.server'.tr());
        expect(of(502), 'error.server'.tr());
        expect(of(418), 'error.unknown'.tr());
        for (final status in [429, 404, 500, 502, 418]) {
          expect(of(status), isNot(contains('Unexpected server response')));
        }
      });

      test('UI-AUDIT #16 [$lang]: the generic 5xx body is translated', () {
        AwI18n.instance.setActiveCached(locale);
        final message = localizedError(
          asApiException(
            _failure(
              500,
              data: {
                'statusCode': 500,
                'code': 'INTERNAL_ERROR',
                'error': 'Internal Server Error',
                'message': 'Internal server error',
              },
            ),
          ),
        );
        expect(message, 'error.INTERNAL_ERROR'.tr());
        expect(message, isNot('Internal server error'));
      });
    }

    test('the Turkish 429 reads "Çok fazla istek, N sn sonra …"', () {
      AwI18n.instance.setActiveCached(const Locale('tr'));
      expect(
        localizedError(const ApiException('RATE_LIMITED', 'x', retryAfter: 7)),
        startsWith('Çok fazla istek, 7 sn sonra'),
      );
      expect(
        localizedError(const ApiException('HTTP_500', 'x')),
        'Sunucu bu isteği tamamlayamadı. Biraz sonra tekrar dene.',
      );
    });

    test('a coded error keeps its own translation, then its message', () {
      AwI18n.instance.setActiveCached(const Locale('en'));
      expect(
        localizedError(const ApiException('PERM_DENIED', 'nope')),
        'error.PERM_DENIED'.tr(),
      );
      expect(
        localizedError(const ApiException('SOME_NEW_CODE', 'Server words')),
        'Server words',
      );
      expect(localizedError(StateError('boom')), 'error.unknown'.tr());
    });
  });

  group('friendlyAuthMessage', () {
    test(
      'UI-AUDIT #24: sign-in on a 429 says how long to wait, in Turkish',
      () {
        AwI18n.instance.setActiveCached(const Locale('tr'));
        final message = friendlyAuthMessage(
          const AuthException(
            'HTTP_429',
            'Unexpected server response',
            statusCode: 429,
            retryAfter: 42,
          ),
        );
        expect(message, startsWith('Çok fazla istek, 42 sn sonra'));
        expect(
          friendlyAuthMessage(
            const AuthException('HTTP_503', 'Unexpected server response'),
          ),
          'error.server'.tr(),
        );
        // The codes it always knew are unchanged.
        expect(
          friendlyAuthMessage(
            const AuthException('AUTH_INVALID_CREDENTIALS', 'Invalid'),
          ),
          'error.AUTH_INVALID_CREDENTIALS'.tr(),
        );
      },
    );
  });
}
