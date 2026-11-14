import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/services/assessment_grading.dart';
void main(){
  final questions=<Map<String,dynamic>>[
    {'id':'choice','question_type':'mc','correct_answer':'Yes'},
    {'id':'writing','question_type':'short'},
    {'id':'recall','question_type':'recall','correct_answer':'Word'},
  ];
  test('writing excluded from objective denominator and threshold is inclusive',(){
    final result=gradeAssessment(questions,{'choice':' yes ','writing':'My response','recall':'wrong'},writingReviewed:true);
    expect(result.score,0.5);expect(result.passes(0.5),isTrue);expect(result.passes(0.7),isFalse);expect(result.objectiveCount,2);
  });
  test('missing keys and unanswered questions fail explicitly',(){
    expect(()=>gradeAssessment([{'id':'q','question_type':'grammar'}],{'q':'answer'},writingReviewed:false),throwsStateError);
    expect(()=>gradeAssessment(questions,{'choice':'yes'},writingReviewed:true),throwsStateError);
  });
  test('writing needs review and cannot produce a pass or objective score',(){
    final writing=[{'id':'q','question_type':'short'}];
    expect(()=>gradeAssessment(writing,{'q':'Response'},writingReviewed:false),throwsStateError);
    final result=gradeAssessment(writing,{'q':'Response'},writingReviewed:true);expect(result.score,isNull);expect(result.passes(0),isFalse);
  });
}
