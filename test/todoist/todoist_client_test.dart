import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hue_memory/todoist/todoist_client.dart';

void main() {
  test('listLabels and listOpenTasks use api/v1 and paginate results', () async {
    final seen = <Uri>[];
    final mock = MockClient((request) async {
      seen.add(request.url);
      expect(request.url.path, startsWith('/api/v1/'));
      expect(request.headers['Authorization'], 'Bearer tok');

      if (request.url.path == '/api/v1/labels') {
        final cursor = request.url.queryParameters['cursor'];
        if (cursor == null) {
          return http.Response(
            jsonEncode({
              'results': [
                {'id': 'l1', 'name': 'high'},
              ],
              'next_cursor': 'page2',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        expect(cursor, 'page2');
        return http.Response(
          jsonEncode({
            'results': [
              {'id': 'l2', 'name': 'low'},
            ],
            'next_cursor': null,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/api/v1/tasks') {
        return http.Response(
          jsonEncode({
            'results': [
              {
                'id': 't1',
                'content': 'Call dentist',
                'labels': ['high'],
              },
            ],
            'next_cursor': null,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('unexpected ${request.url}', 500);
    });

    final client = TodoistClient(apiToken: 'tok', httpClient: mock);
    final labels = await client.listLabels();
    expect(labels.map((l) => l.name).toList(), ['high', 'low']);

    final tasks = await client.listOpenTasks();
    expect(tasks.single.content, 'Call dentist');
    expect(tasks.single.labels, ['high']);

    expect(
      seen.map((u) => u.path).toList(),
      ['/api/v1/labels', '/api/v1/labels', '/api/v1/tasks'],
    );
  });

  test('createInboxTask and closeTask hit api/v1 paths', () async {
    final mock = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/api/v1/tasks') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['content'], 'Ship');
        expect(body['labels'], ['medium']);
        expect(body['priority'], 3);
        expect(body['parent_id'], 'parent99');
        expect(body['due_date'], '2026-11-20');
        return http.Response(
          jsonEncode({
            'id': 'new1',
            'content': 'Ship',
            'labels': ['medium'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/tasks/new1/close') {
        return http.Response('', 204);
      }
      return http.Response('unexpected ${request.method} ${request.url}', 500);
    });

    final client = TodoistClient(apiToken: 'tok', httpClient: mock);
    final created = await client.createInboxTask(
      content: 'Ship',
      labels: ['medium'],
      priority: 3,
      parentId: 'parent99',
      dueDate: DateTime(2026, 11, 20),
    );
    expect(created.id, 'new1');
    await client.closeTask('new1');
  });

  test(
    'ensureLabels reuses existing spelling and creates only missing names',
    () async {
      final createdNames = <String>[];
      final mock = MockClient((request) async {
        if (request.method == 'GET' && request.url.path == '/api/v1/labels') {
          return http.Response(
            jsonEncode({
              'results': [
                {'id': 'l1', 'name': 'Deshan'},
                {'id': 'l2', 'name': 'high'},
              ],
              'next_cursor': null,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'POST' && request.url.path == '/api/v1/labels') {
          final name =
              (jsonDecode(request.body) as Map<String, dynamic>)['name']
                  as String;
          createdNames.add(name);
          return http.Response(
            jsonEncode({'id': 'new-$name', 'name': name}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          'unexpected ${request.method} ${request.url}',
          500,
        );
      });

      final client = TodoistClient(apiToken: 'tok', httpClient: mock);
      final out = await client.ensureLabels(['deshan', 'high', 'zoë', 'thabo']);

      expect(createdNames, ['zoë', 'thabo']);
      expect(out['deshan']!.name, 'Deshan');
      expect(out['deshan']!.id, 'l1');
      expect(out['high']!.id, 'l2');
      expect(out['zoë']!.id, 'new-zoë');
      expect(out['thabo']!.name, 'thabo');
    },
  );

  test('verifyConnection fails clearly on 410 deprecated', () async {
    final mock = MockClient((request) async {
      return http.Response('This endpoint is deprecated.', 410);
    });
    final client = TodoistClient(
      apiToken: 'tok',
      httpClient: mock,
      baseUrl: 'https://api.todoist.com/rest/v2',
    );
    final result = await client.verifyConnection();
    expect(result.ok, isFalse);
    expect(result.message, contains('410'));
  });

  test('createInboxTask sends X-Request-Id only when given', () async {
    final ids = <String?>[];
    final mock = MockClient((request) async {
      ids.add(request.headers['X-Request-Id']);
      return http.Response(
        jsonEncode({'id': 't1', 'content': 'A'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = TodoistClient(apiToken: 'tok', httpClient: mock);
    await client.createInboxTask(content: 'A', requestId: 'rid-1');
    await client.createInboxTask(content: 'A');
    expect(ids, ['rid-1', null]);
  });

  test('updateTask patches content and priority; 404 reads as not found',
      () async {
    final bodies = <Map<String, dynamic>>[];
    final mock = MockClient((request) async {
      expect(request.url.path, startsWith('/api/v1/tasks/'));
      if (request.url.path.endsWith('/gone')) {
        return http.Response('{"error":"Task not found"}', 404);
      }
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode({'id': 't1', 'content': 'New'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = TodoistClient(apiToken: 'tok', httpClient: mock);

    await client.updateTask('t1', content: 'New', priority: 4);
    await client.updateTask('t1', priority: 1);
    expect(bodies, [
      {'content': 'New', 'priority': 4},
      {'priority': 1},
    ]);

    await expectLater(
      client.updateTask('gone', content: 'x'),
      throwsA(
        isA<TodoistApiException>()
            .having((e) => e.isNotFound, 'isNotFound', true),
      ),
    );
  });

  test('newRequestId is a UUID v4 and unique', () {
    final a = TodoistClient.newRequestId();
    final b = TodoistClient.newRequestId();
    expect(
      a,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(a, isNot(b));
  });
}
