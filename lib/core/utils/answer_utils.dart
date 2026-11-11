/// Deterministic grading shared by grammar exercises and assessments.
bool matchesAnswer(String learner, String? correct,
    [List<String> alternatives = const []]) {
  final answer = learner.trim().toLowerCase();
  if (answer.isEmpty) return false;
  final accepted = [if (correct != null) correct, ...alternatives];
  return accepted.any((candidate) => candidate.trim().toLowerCase() == answer);
}
