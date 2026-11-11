import 'dart:async';
import 'dart:convert';

import 'package:lexiflow/core/services/ai_teacher_service.dart';
import 'package:lexiflow/core/services/shadowing_controller.dart';

class MockAiTransport implements AiTransport {
  int calls = 0;
  Uri? uri;
  Map<String, String>? headers;
  Map<String, Object?>? body;
  Object? failure;
  AiHttpResponse response = AiHttpResponse(
      200,
      jsonEncode({
        'choices': [
          {
            'message': {'content': 'Helpful B1–B2 feedback.'}
          }
        ]
      }));
  Completer<AiHttpResponse>? waiting;
  @override
  Future<AiHttpResponse> post(Uri uri, Map<String, String> headers,
      Map<String, Object?> body, Duration timeout) async {
    calls++;
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    if (failure != null) throw failure!;
    if (waiting != null) return waiting!.future;
    return response;
  }
}

class MockPracticePlayer implements PracticePlayer {
  @override
  Duration? duration = const Duration(seconds: 30);
  @override
  bool playing = false;
  bool disposed = false;
  String? path;
  int start = 0, end = 0;
  final changes = StreamController<bool>.broadcast();
  final problems = StreamController<String>.broadcast();
  @override
  Stream<bool> get playingChanges => changes.stream;
  @override
  Stream<String> get errors => problems.stream;
  @override
  Future<void> load(String path) async {
    this.path = path;
  }

  @override
  Future<void> segment(int startMs, int endMs) async {
    start = startMs;
    end = endMs;
  }

  @override
  Future<void> play() async {
    playing = true;
    changes.add(true);
  }

  @override
  Future<void> stop() async {
    playing = false;
    changes.add(false);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await changes.close();
    await problems.close();
  }
}
