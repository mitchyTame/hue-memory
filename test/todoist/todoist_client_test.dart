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
}
