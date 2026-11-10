import 'package:flutter_test/flutter_test.dart';

bool matchesAnswer(String learner, String correct, List<String> alternatives) {
  final a = learner.trim().toLowerCase();
  if (a == correct.trim().toLowerCase()) return true;
  for (final alt in alternatives) {
    if (a == alt.trim().toLowerCase()) return true;
  }
  return false;
}

int wordCount(String body) {
  final t = body.trim();
  if (t.isEmpty) return 0;
  return t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}

void main() {
  group('grammar answer matching', () {
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
