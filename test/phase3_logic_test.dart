import 'package:flutter_test/flutter_test.dart';

/// Deterministic MC grading (mirrors app logic).
bool gradeMultipleChoice(String? learner, String? correct) {
  if (learner == null || correct == null) return false;
  return learner.trim().toLowerCase() == correct.trim().toLowerCase();
}

void main() {
  group('comprehension grading', () {
    test('exact match', () {
      expect(gradeMultipleChoice('B', 'B'), isTrue);
    });
    test('case insensitive', () {
      expect(gradeMultipleChoice('b', 'B'), isTrue);
    });
    test('mismatch', () {
      expect(gradeMultipleChoice('A', 'C'), isFalse);
    });
    test('null safe', () {
      expect(gradeMultipleChoice(null, 'A'), isFalse);
    });
  });
}
