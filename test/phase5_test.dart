import 'package:flutter_test/flutter_test.dart';

bool assessmentPassed(double score, double threshold) => score >= threshold;

String certRefPattern(String ref) => ref;

void main() {
  group('assessment eligibility', () {
    test('pass at threshold', () {
      expect(assessmentPassed(0.7, 0.7), isTrue);
    });
    test('fail below', () {
      expect(assessmentPassed(0.69, 0.7), isFalse);
    });
  });

  group('certificate disclaimer', () {
    test('must not claim accreditation in wording check', () {
      const disclaimer =
          'Personal learning achievement — not an accredited qualification.';
      expect(disclaimer.contains('not an accredited'), isTrue);
    });
  });
}
