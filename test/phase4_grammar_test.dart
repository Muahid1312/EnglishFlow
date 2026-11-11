import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/utils/answer_utils.dart';

// Exercise the production matcher rather than a duplicate implementation.

int wordCount(String body) {
  final t = body.trim();
  if (t.isEmpty) return 0;
  return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}

void main() {
  group('grammar answer matching', () {
    test('missing or empty answers never earn credit', () {
      expect(matchesAnswer('', ''), isFalse);
      expect(matchesAnswer(' ', null), isFalse);
    });
    test('exact', () {
      expect(matchesAnswer('has gone', 'has gone', []), isTrue);
    });
    test('alternative accepted', () {
      expect(
          matchesAnswer(
              "I've never eaten", 'have never eaten', ["I've never eaten"]),
          isTrue);
    });
    test('wrong rejected', () {
      expect(matchesAnswer('went', 'has gone', []), isFalse);
    });
  });

  group('word count', () {
    test('empty', () => expect(wordCount('  '), 0));
    test('simple', () => expect(wordCount('one two three'), 3));
  });
}
