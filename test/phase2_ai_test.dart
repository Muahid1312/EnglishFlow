import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/services/ai_teacher_service.dart';

import 'stability_services_test.dart' as fixtures;
import 'support/phase2_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixtures.TestSecureStorage storage;
  late MockAiTransport transport;
  late SecureAiTeacherService ai;
  setUp(() async {
    storage = fixtures.TestSecureStorage();
    transport = MockAiTransport();
    ai = SecureAiTeacherService(
        storage: storage,
        transport: transport,
        timeout: const Duration(milliseconds: 100));
    await ai.saveApiKey(AiProvider.openAi, 'dummy-private-key');
  });
  test(
      'actual client builds correct OpenAI HTTPS request and parses a mocked response',
      () async {
    expect(
        await ai.complete(const [AiMessage('user', 'Please help my English.')]),
        'Helpful B1–B2 feedback.');
    expect(
        transport.uri.toString(), 'https://api.openai.com/v1/chat/completions');
    expect(transport.headers!['Authorization'], 'Bearer dummy-private-key');
    expect(transport.body!['model'], 'gpt-4.1-mini');
    expect((transport.body!['messages'] as List).first['role'], 'system');
    expect((transport.body!['messages'] as List).last['content'],
        'Please help my English.');
    expect(transport.calls, 1);
  });
  test('Anthropic configuration reuses the same service with correct protocol',
      () async {
    await ai.saveConfiguration(AiConfiguration.defaults(AiProvider.anthropic),
        apiKey: 'dummy-anthropic-key');
    transport.response = AiHttpResponse(
        200,
        jsonEncode({
          'content': [
            {'type': 'text', 'text': 'An actual mocked response.'}
          ]
        }));
    expect(await ai.complete(const [AiMessage('user', 'Help')]),
        'An actual mocked response.');
    expect(transport.headers!['x-api-key'], 'dummy-anthropic-key');
    expect(transport.headers!['anthropic-version'], '2023-06-01');
    expect(transport.body!['system'], contains('American English'));
    expect(transport.uri!.host, 'api.anthropic.com');
  });
  test(
      'custom HTTPS endpoint and model persist without exposing the stored key',
      () async {
    await ai.saveConfiguration(
        const AiConfiguration(
            provider: AiProvider.custom,
            model: 'local-compatible-model',
            endpoint: 'https://example.test/v1/chat/completions'),
        apiKey: 'custom-secret');
    final c = await ai.getConfiguration();
    expect(c.model, 'local-compatible-model');
    expect((await ai.checkStatus()).message, isNot(contains('custom-secret')));
    await ai.complete(const [AiMessage('user', 'Help')]);
    expect(transport.uri!.host, 'example.test');
  });
  test(
      'insecure endpoints, URL userinfo and builtin endpoint substitution are rejected',
      () async {
    for (final endpoint in [
      'http://example.test/chat',
      'https://key@example.test/chat'
    ]) {
      await expectLater(
          ai.saveConfiguration(
              AiConfiguration(
                  provider: AiProvider.custom, model: 'm', endpoint: endpoint),
              apiKey: 'key'),
          throwsA(isA<AiFailure>()));
    }
    await expectLater(
        ai.saveConfiguration(
            const AiConfiguration(
                provider: AiProvider.openAi,
                model: 'm',
                endpoint: 'https://other.test/chat'),
            apiKey: 'key'),
        throwsA(isA<AiFailure>()));
    expect(transport.calls, 0);
  });
  for (final status in [401, 403, 429, 500, 302]) {
    test(
        'HTTP $status returns safe errors, never raw provider text or automatic retries',
        () async {
      transport.response = AiHttpResponse(
          status, 'dummy-private-key from provider error',
          retryAfter: '60');
      try {
        await ai.complete(const [AiMessage('user', 'Help')]);
        fail('Expected failure');
      } on AiFailure catch (error) {
        expect(error.message, isNot(contains('dummy-private-key')));
        expect(
            error.code,
            status == 401 || status == 403
                ? AiError.authentication
                : status == 429
                    ? AiError.rateLimited
                    : AiError.rejected);
        if (status == 429) {
          expect(error.retryAfter, const Duration(seconds: 60));
        }
      }
      expect(transport.calls, 1);
    });
  }
  test(
      'rate-limit cooldown blocks repeat network requests until configuration changes',
      () async {
    transport.response = const AiHttpResponse(429, '{}', retryAfter: '60');
    await expectLater(ai.complete(const [AiMessage('user', 'Help')]),
        throwsA(isA<AiFailure>()));
    transport.response = const AiHttpResponse(
        200, '{"choices":[{"message":{"content":"Ready"}}]}');
    await expectLater(
        ai.complete(const [AiMessage('user', 'Help')]),
        throwsA(isA<AiFailure>()
            .having((e) => e.code, 'code', AiError.rateLimited)));
    expect(transport.calls, 1);
    await ai.saveApiKey(AiProvider.openAi, 'replacement-test-key');
    expect(await ai.complete(const [AiMessage('user', 'Help')]), 'Ready');
    expect(transport.calls, 2);
  });
  test(
      'network timeout and network failure preserve explicit unavailable states',
      () async {
    transport.waiting = Completer<AiHttpResponse>();
    await expectLater(
        ai.complete(const [AiMessage('user', 'Help')], requestId: 'timeout'),
        throwsA(
            isA<AiFailure>().having((e) => e.code, 'code', AiError.timeout)));
    expect(ai.isRequestActive('timeout'), isFalse);
    transport.waiting = null;
    transport.failure = const SocketException('sensitive network details');
    await expectLater(
        ai.complete(const [AiMessage('user', 'Help')]),
        throwsA(
            isA<AiFailure>().having((e) => e.code, 'code', AiError.network)));
  });
  test('invalid or empty responses never fabricate an answer', () async {
    for (final response in [
      'not json',
      '{}',
      '{"choices":[]}',
      '{"choices":[{"message":{"content":""}}]}'
    ]) {
      transport.response = AiHttpResponse(200, response);
      await expectLater(
          ai.complete(const [AiMessage('user', 'Help')]),
          throwsA(isA<AiFailure>()
              .having((e) => e.code, 'code', AiError.invalidResponse)));
    }
  });
  test('missing credentials prevents all network requests', () async {
    await ai.clearCredentials();
    await expectLater(ai.complete(const [AiMessage('user', 'Help')]),
        throwsA(isA<AiFailure>()));
    expect(transport.calls, 0);
  });
  test(
      'duplicate request id shares one in-flight request and history is bounded',
      () async {
    transport.waiting = Completer<AiHttpResponse>();
    final history = List.generate(
        100, (i) => AiMessage(i.isEven ? 'user' : 'assistant', 'Message $i'));
    final first = ai.complete(history, requestId: 'same');
    final second = ai.complete(history, requestId: 'same');
    await Future<void>.delayed(Duration.zero);
    expect(transport.calls, 1);
    expect((transport.body!['messages'] as List).length, 21);
    transport.waiting!.complete(transport.response);
    expect(await first, await second);
    expect(ai.isRequestActive('same'), isFalse);
  });
  for (final task in AiTask.values) {
    test('${task.name} assistance sends an actual task-specific request',
        () async {
      await ai.complete(
          const [AiMessage('user', 'Explicitly selected content')],
          task: task);
      expect((transport.body!['messages'] as List).first['content'],
          contains('B1–B2'));
      expect(transport.calls, 1);
    });
  }
}
