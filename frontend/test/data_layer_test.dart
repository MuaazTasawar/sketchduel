import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sketchduel_app/data/datasources/api_datasource.dart';
import 'package:sketchduel_app/data/repositories/game_repository.dart';

import 'fixtures.dart';

const _base = 'http://test/api/v1';

Future<String?> _token({bool forceRefresh = false}) async => 'tok';

http.Response _ok(Object body) => http.Response(jsonEncode(body), 200);

/// A datasource whose "server" is [handler]; the last request it saw goes to [seen].
ApiDatasource _datasource(
  Future<http.Response> Function(http.Request request) handler, {
  TokenProvider? tokens,
  Duration timeout = const Duration(seconds: 5),
  void Function(http.Request request)? seen,
}) {
  return ApiDatasource(
    client: MockClient((request) {
      seen?.call(request);
      return handler(request);
    }),
    baseUrl: _base,
    tokenProvider: tokens,
    timeout: timeout,
  );
}

void main() {
  group('error messages', () {
    test('401 asks the player to log in again, whatever the server said', () {
      expect(
        ApiDatasource.errorMessage(401, {'detail': 'Invalid or expired token'}),
        contains('log in again'),
      );
    });

    test('a plain detail string is passed through', () {
      expect(
        ApiDatasource.errorMessage(404, asMap(err404Json)),
        'Room not found',
      );
      expect(
        ApiDatasource.errorMessage(409, asMap(err409Json)),
        contains('full'),
      );
    });

    test('validation errors (a list) become one readable line per field', () {
      final message = ApiDatasource.errorMessage(422, asMap(err422Json));
      expect(message, startsWith('room_code:'));
      expect(message, contains('at least 4 characters'));
    });

    test('statuses without a detail get a sensible default', () {
      expect(ApiDatasource.errorMessage(429, null), contains('Too many'));
      expect(ApiDatasource.errorMessage(413, null), contains('too large'));
      expect(ApiDatasource.errorMessage(502, null), contains('error 502'));
      expect(
        ApiDatasource.errorMessage(418, <String, dynamic>{}),
        'Request failed (error 418).',
      );
    });

    test('ApiException prints just its message', () {
      expect(
        const ApiException(409, 'Room is full').toString(),
        'Room is full',
      );
    });

    test('the convenience flags', () {
      expect(const ApiException(0, 'x').isNetworkError, isTrue);
      expect(const ApiException(401, 'x').isUnauthorized, isTrue);
      expect(const ApiException(404, 'x').isNotFound, isTrue);
      expect(const ApiException(409, 'x').isConflict, isTrue);
    });
  });

  group('ApiDatasource', () {
    test('GET sends the query string and the bearer token', () async {
      late http.Request seen;
      final api = _datasource(
        (r) async => _ok({'a': 1}),
        tokens: _token,
        seen: (r) => seen = r,
      );
      await api.get('/x', query: {'limit': '5'});
      expect(seen.url.toString(), '$_base/x?limit=5');
      expect(seen.method, 'GET');
      expect(seen.headers['Authorization'], 'Bearer tok');
    });

    test('without a token provider nothing is sent in Authorization', () async {
      late http.Request seen;
      final api = _datasource((r) async => _ok({}), seen: (r) => seen = r);
      await api.get('/x');
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'a signed-out player (null token) sends no Authorization header',
      () async {
        late http.Request seen;
        final api = _datasource(
          (r) async => _ok({}),
          tokens: ({bool forceRefresh = false}) async => null,
          seen: (r) => seen = r,
        );
        await api.get('/x');
        expect(seen.headers.containsKey('Authorization'), isFalse);
      },
    );

    test('POST sends a JSON body with the right content type', () async {
      late http.Request seen;
      final api = _datasource(
        (r) async => _ok({}),
        tokens: _token,
        seen: (r) => seen = r,
      );
      await api.post('/y', {'k': 'v'});
      expect(seen.method, 'POST');
      expect(jsonDecode(seen.body), {'k': 'v'});
      expect(seen.headers['Content-Type'], 'application/json');
    });

    test(
      'a 401 refreshes the token once and retries with the fresh one',
      () async {
        final asked = <String>[];
        var requests = 0;
        late http.Request seen;
        final api = _datasource(
          (r) async {
            requests++;
            return requests == 1
                ? http.Response('{"detail":"Invalid or expired token"}', 401)
                : _ok({'ok': true});
          },
          tokens: ({bool forceRefresh = false}) async {
            asked.add('refresh=$forceRefresh');
            return forceRefresh ? 'fresh' : 'old';
          },
          seen: (r) => seen = r,
        );

        final data = await api.get('/x');
        expect(data['ok'], isTrue);
        expect(requests, 2);
        expect(asked, ['refresh=false', 'refresh=true']);
        expect(seen.headers['Authorization'], 'Bearer fresh');
      },
    );

    test(
      'a persistent 401 stops after two attempts with a friendly message',
      () async {
        var requests = 0;
        final api = _datasource((r) async {
          requests++;
          return http.Response('{"detail":"nope"}', 401);
        }, tokens: _token);
        await expectLater(
          api.get('/x'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 401)
                .having((e) => e.message, 'message', contains('log in again')),
          ),
        );
        expect(requests, 2);
      },
    );

    test('without a token provider a 401 is not retried', () async {
      var requests = 0;
      final api = _datasource((r) async {
        requests++;
        return http.Response('{}', 401);
      });
      await expectLater(api.get('/x'), throwsA(isA<ApiException>()));
      expect(requests, 1);
    });

    test('server errors reach the caller as readable ApiExceptions', () async {
      final conflict = _datasource((r) async => http.Response(err409Json, 409));
      await expectLater(
        conflict.post('/x', {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', contains('full')),
        ),
      );

      final invalid = _datasource((r) async => http.Response(err422Json, 422));
      await expectLater(
        invalid.post('/x', {}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('room_code'),
          ),
        ),
      );

      final html = _datasource(
        (r) async => http.Response('<html>Bad gateway</html>', 502),
      );
      await expectLater(
        html.get('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 502)
              .having((e) => e.message, 'message', contains('error 502')),
        ),
      );
    });

    test('a 200 answer that is not JSON is an error, not a crash', () async {
      final api = _datasource((r) async => http.Response('<html>', 200));
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('unreadable'),
          ),
        ),
      );
    });

    test('a POST answered with a JSON list is rejected', () async {
      final api = _datasource((r) async => _ok([1, 2]));
      await expectLater(
        api.post('/x', {}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('unexpected'),
          ),
        ),
      );
    });

    test('no connection becomes status 0 with a clear message', () async {
      final api = _datasource(
        (r) async => throw http.ClientException('socket'),
      );
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isNetworkError, 'isNetworkError', isTrue)
              .having((e) => e.message, 'message', contains('Cannot reach')),
        ),
      );
    });

    test('a slow server becomes status 0 with a "too long" message', () async {
      final api = _datasource((r) async {
        await Future<void>.delayed(const Duration(seconds: 1));
        return _ok({});
      }, timeout: const Duration(milliseconds: 50));
      await expectLater(
        api.get('/x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 0)
              .having((e) => e.message, 'message', contains('too long')),
        ),
      );
    });
  });

  group('GameRepository', () {
    final log = <String>[];

    // path fragment -> the real JSON the backend sends for it
    final routes = <(String, String)>[
      ('/game/room/create', createRoomJson),
      ('/game/room/join', joinRoomJson),
      ('/game/room/id/', roomActiveJson),
      ('/game/score', scoreFirstJson),
      ('/game/predict', predictJson),
      ('/game/history', historyJson),
      ('/leaderboard/top', leaderboardJson),
      ('/auth/profile/', profileJson),
    ];

    Future<http.Response> server(http.Request r) async {
      final query = r.url.hasQuery ? '?${r.url.query}' : '';
      log.add('${r.method} ${r.url.path}$query ${r.body}');
      for (final (fragment, body) in routes) {
        if (r.url.path.contains(fragment)) return http.Response(body, 200);
      }
      return http.Response('{"detail":"unknown"}', 404);
    }

    GameRepository repo() =>
        GameRepository(api: _datasource(server, tokens: _token));

    setUp(log.clear);

    test('createRoom is a POST with an empty body (no player id)', () async {
      final room = await repo().createRoom();
      expect(log.last, 'POST /api/v1/game/room/create {}');
      expect(room.roomCode.length, 6);
    });

    test(
      'joinRoom trims and upper-cases the code and sends nothing else',
      () async {
        final room = await repo().joinRoom('  ab12cd ');
        expect(log.last, 'POST /api/v1/game/room/join {"room_code":"AB12CD"}');
        expect(room.isActive, isTrue);
      },
    );

    test('getRoom reads the game by id', () async {
      final room = await repo().getRoom('abc-123');
      expect(log.last, startsWith('GET /api/v1/game/room/id/abc-123'));
      expect(room.isActive, isTrue);
    });

    test('submitDrawing sends only the game id and the drawing', () async {
      final result = await repo().submitDrawing(
        gameId: 'g1',
        drawingBase64: 'AAAA',
      );
      expect(
        log.last,
        'POST /api/v1/game/score {"game_id":"g1","drawing_data":"AAAA"}',
      );
      expect(result.submitted, isTrue);
      expect(result.score, 79.29);
    });

    test('predict posts the drawing for the live bar', () async {
      final prediction = await repo().predict(
        gameId: 'g1',
        drawingBase64: 'AAAA',
      );
      expect(log.last, startsWith('POST /api/v1/game/predict'));
      expect(prediction.model, 'mock');
    });

    test('getHistory passes the limit', () async {
      final history = await repo().getHistory(limit: 7);
      expect(log.last, 'GET /api/v1/game/history?limit=7 ');
      expect(history.length, 1);
      expect(history.first.opponentUsername, 'bob');
    });

    test(
      'getLeaderboard returns the raw rows the leaderboard screen reads',
      () async {
        final rows = await repo().getLeaderboard();
        expect(log.last, startsWith('GET /api/v1/leaderboard/top?limit=20'));
        expect(rows.length, 2);
        final first = rows.first as Map;
        for (final key in [
          'rank',
          'username',
          'total_wins',
          'total_games',
          'win_rate',
          'best_score',
        ]) {
          expect(first.containsKey(key), isTrue, reason: key);
        }
      },
    );

    test('getProfile reads a public profile', () async {
      final profile = await repo().getProfile('u-1');
      expect(log.last, startsWith('GET /api/v1/auth/profile/u-1'));
      expect(profile.username, 'alice');
      expect(profile.email, isNull);
    });

    test('errors surface as ApiException with the server message', () async {
      final failing = GameRepository(
        api: _datasource(
          (r) async => http.Response('{"detail":"Game not found"}', 404),
          tokens: _token,
        ),
      );
      await expectLater(
        failing.getRoom('x'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Game not found'),
        ),
      );
    });
  });
}