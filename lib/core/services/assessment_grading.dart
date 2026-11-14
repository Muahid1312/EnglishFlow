import '../utils/answer_utils.dart';

class AssessmentGrade {
  const AssessmentGrade(this.correct, this.objectiveCount, this.hasWriting);
  final int correct,objectiveCount;
  final bool hasWriting;
  double? get score=>objectiveCount==0?null:correct/objectiveCount;
  bool passes(double threshold)=>score!=null && score!>=threshold;
}

/// Keys grade objective responses; self-assessed writing never enters the
/// denominator. An incomplete or unkeyed assessment cannot yield a result.
AssessmentGrade gradeAssessment(List<Map<String,dynamic>> questions,
    Map<String,dynamic> answers,{required bool writingReviewed}) {
  if(questions.isEmpty)throw StateError('This assessment has no questions.');
  var correct=0,objectiveCount=0;var hasWriting=false;
  for(final question in questions){
    final answer=answers[question['id']]?.toString()??'';
    if(answer.trim().isEmpty)throw StateError('Answer every question before submitting.');
    if(['short','writing'].contains(question['question_type'])){hasWriting=true;continue;}
    final key=question['correct_answer'] as String?;
    if(key==null||key.trim().isEmpty)throw StateError('An objective answer key is missing.');
    objectiveCount++;
    if(matchesAnswer(answer,key))correct++;
  }
  if(hasWriting&&!writingReviewed)throw StateError('Review writing against the rubric before submitting.');
  return AssessmentGrade(correct,objectiveCount,hasWriting);
}
