import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/content/conversation_scenarios.dart';
import 'package:lexiflow/core/database/app_database.dart';
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
    await ai.saveApiKey(AiProvider.openAi, 'test-only-placeholder');
  });
  for (final scenario in conversationScenarios) {
    test('${scenario.title} sends the actual trusted scenario instruction',
        () async {
      await ai.completeCoached(const [AiMessage('user', 'Let us practice.')],
          scenarioId: scenario.id, requestId: scenario.id);
      final system =
          (transport.body!['messages'] as List).first['content'] as String;
      expect(system, contains(scenario.instruction));
      expect(system, contains(scenario.goal));
      expect(system, contains('Do not interrupt with unsolicited corrections'));
      expect((transport.body!['messages'] as List).last['content'],
          'Let us practice.');
    });
  }
  test(
      'feedback requires exchanges and never asks for a fabricated level score',
      () async {
    await expectLater(
        ai.completeCoached(const [AiMessage('user', 'Hi')],
            scenarioId: 'free', feedback: true),
        throwsA(isA<AiFailure>()));
    final messages = <AiMessage>[
      for (var i = 0; i < 3; i++) ...[
        AiMessage('user', 'My real message $i'),
        AiMessage('assistant', 'A saved reply $i')
      ],
      const AiMessage('user', 'Please summarize.')
    ];
    await ai.completeCoached(messages, scenarioId: 'free', feedback: true);
    final system =
        (transport.body!['messages'] as List).first['content'] as String;
    expect(system, contains('actual original wording'));
    expect(system, contains('Do not claim a CEFR'));
  });
  test('duplicate coached request IDs share one HTTP operation', () async {
    transport.waiting = Completer<AiHttpResponse>();
    final first = ai.completeCoached(const [AiMessage('user', 'Hi')],
        scenarioId: 'travel', requestId: 'same');
    final second = ai.completeCoached(const [AiMessage('user', 'Hi')],
        scenarioId: 'travel', requestId: 'same');
    expect(identical(first, second), isTrue);
    while (transport.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    transport.waiting!.complete(transport.response);
    await first;
    await second;
    expect(transport.calls, 1);
  });
  test(
      'logical cancellation works for adapters without an abort API and ignores their late reply',
      () async {
    transport.waiting = Completer<AiHttpResponse>();
    final request = ai.completeCoached(const [AiMessage('user', 'Hi')],
        scenarioId: 'everyday', requestId: 'cancel');
    final assertion = expectLater(
        request,
        throwsA(
            isA<AiFailure>().having((e) => e.code, 'code', AiError.cancelled)));
    while (transport.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(ai.cancelRequest('cancel'), isTrue);
    await assertion;
    transport.waiting!.complete(transport.response);
    await Future<void>.delayed(Duration.zero);
    expect(ai.isRequestActive('cancel'), isFalse);
  });
  test(
      'abort-capable transport receives cancellation and reports a cancelled result',
      () async {
    final cancellable = _AbortTransport();
    final service =
        SecureAiTeacherService(storage: storage, transport: cancellable);
    final request = service.completeCoached(const [AiMessage('user', 'Hi')],
        scenarioId: 'free', requestId: 'abort');
    final assertion = expectLater(
        request,
        throwsA(
            isA<AiFailure>().having((e) => e.code, 'code', AiError.cancelled)));
    await cancellable.started.future;
    expect(service.cancelRequest('abort'), isTrue);
    await assertion;
    await Future<void>.delayed(Duration.zero);
    expect(cancellable.aborted, isTrue);
  });
  for (final status in [401, 403, 429]) {
    test('coached HTTP $status remains a safe typed error', () async {
      transport.response = AiHttpResponse(status, 'untrusted secret error body',
          retryAfter: '20');
      await expectLater(
          ai.completeCoached(const [AiMessage('user', 'Hi')],
              scenarioId: 'workplace'),
          throwsA(isA<AiFailure>().having((e) => e.code, 'code',
              status == 429 ? AiError.rateLimited : AiError.authentication)));
    });
  }
  test(
      'malformed, offline and timed-out coached requests never return fake text',
      () async {
    transport.response = const AiHttpResponse(200, 'not JSON');
    await expectLater(
        ai.completeCoached(const [AiMessage('user', 'Hi')], scenarioId: 'free'),
        throwsA(isA<AiFailure>()
            .having((e) => e.code, 'code', AiError.invalidResponse)));
    transport.failure = const SocketException('offline');
    await expectLater(
        ai.completeCoached(const [AiMessage('user', 'Hi')], scenarioId: 'free'),
        throwsA(
            isA<AiFailure>().having((e) => e.code, 'code', AiError.network)));
    transport.failure = null;
    transport.waiting = Completer<AiHttpResponse>();
    await expectLater(
        ai.completeCoached(const [AiMessage('user', 'Hi')], scenarioId: 'free'),
        throwsA(
            isA<AiFailure>().having((e) => e.code, 'code', AiError.timeout)));
    transport.waiting!.complete(transport.response);
  });
  test('missing credentials are unavailable rather than a simulated assistant',
      () async {
    await ai.clearCredentials();
    expect((await ai.checkStatus()).isReady, isFalse);
    await expectLater(
        ai.completeCoached(const [AiMessage('user', 'Hi')], scenarioId: 'free'),
        throwsA(isA<AiFailure>()));
    expect(transport.calls, 0);
  });
  test(
      'conversation scenario, feedback, order and cancellation survive database restart',
      () async {
    final dir = Directory.systemTemp.createTempSync('lexiflow-phase3-chat-');
    var db = AppDatabase(path: '${dir.path}/db.sqlite');
    try {
      await db.insertAiConversation('chat',
          title: 'Interview practice', scenarioId: 'job_interview');
      final request = await db
          .beginAiRequest('chat', 'My original learner message.', id: 'stable');
      expect(
          await db.beginAiRequest('chat', 'My original learner message.',
              id: 'stable'),
          request);
      await expectLater(db.beginAiRequest('chat', 'A second pending message.'),
          throwsStateError);
      await db.finishAiRequest(request, 'A real mocked provider response.');
      await db.finishAiRequest(request, 'Must not replace the first reply.');
      final feedback = await db.beginAiRequest('chat', 'Please summarize.',
          purpose: 'feedback');
      await db.finishAiRequest(feedback, 'A requested feedback summary.');
      final cancelled = await db.beginAiRequest('chat', 'Cancel this.');
      await db.setAiRequestState(cancelled, 'cancelled');
      await db.finishAiRequest(
          cancelled, 'Late provider output must not be saved.');
      db.close();
      db = AppDatabase(path: '${dir.path}/db.sqlite');
      final messages = await db.getAiMessages('chat');
      expect(messages, hasLength(5));
      expect(messages.first['content'], 'My original learner message.');
      expect(
          messages.where(
              (m) => m['role'] == 'assistant' && m['purpose'] == 'feedback'),
          hasLength(1));
      expect(
          messages.any(
              (m) => m['content'] == 'Late provider output must not be saved.'),
          isFalse);
      expect((await db.getAiConversations()).single['scenario_id'],
          'job_interview');
      expect(await db.getAiConversations(search: 'original learner'),
          hasLength(1));
      expect(
          await db.getAiConversations(search: 'no matching content'), isEmpty);
    } finally {
      db.close();
      dir.deleteSync(recursive: true);
    }
  });
}

class _AbortTransport implements CancellableAiTransport {
  final started = Completer<void>();
  bool aborted = false;
  @override
  Future<AiHttpResponse> post(Uri uri, Map<String, String> headers,
          Map<String, Object?> body, Duration timeout) =>
      throw StateError('The cancellable path must be used.');
  @override
  Future<AiHttpResponse> postCancellable(
      Uri uri,
      Map<String, String> headers,
      Map<String, Object?> body,
      Duration timeout,
      AiCancellation cancellation) async {
    started.complete();
    await cancellation.cancelled;
    aborted = true;
    throw const SocketException('cancelled by fixture');
  }
}
