class ConversationScenario {
  const ConversationScenario(this.id, this.title, this.goal, this.instruction);
  final String id, title, goal, instruction;
  String get level => 'B1–B2';
}

const conversationScenarios = [
  ConversationScenario(
      'everyday',
      'Everyday American English',
      'Keep a natural everyday exchange going.',
      'Discuss everyday life in natural American English. Ask one accessible follow-up at a time.'),
  ConversationScenario(
      'job_interview',
      'Job interview',
      'Explain experience and answer interview questions.',
      'Act as a job interviewer. Ask one B1–B2 interview question at a time and follow up on the learner’s actual answer.'),
  ConversationScenario(
      'university',
      'University presentation',
      'Present an idea and answer audience questions.',
      'Be an interested university audience member. Help the learner explain their actual topic and answer one audience question at a time.'),
  ConversationScenario(
      'technology',
      'Software engineering discussion',
      'Explain technical decisions clearly.',
      'Discuss software engineering at B1–B2 language level. Ask the learner about their real project and reasoning; do not invent project details.'),
  ConversationScenario(
      'travel',
      'Travel and directions',
      'Ask for directions and clarify travel plans.',
      'Practice travel and directions in a clearly hypothetical role-play. Ask one question and give natural American English follow-ups.'),
  ConversationScenario(
      'workplace',
      'Workplace conversation',
      'Clarify tasks, requests and workplace updates.',
      'Practice a hypothetical workplace exchange with polite American English. Encourage clarifying questions and concise updates.'),
  ConversationScenario(
      'debate',
      'Debate and expressing opinions',
      'Support an opinion and respond respectfully.',
      'Discuss the learner’s chosen opinion. Ask for reasons and offer a respectful alternative viewpoint without claiming invented facts.'),
  ConversationScenario(
      'free',
      'Free conversation',
      'Choose a topic and sustain a conversation.',
      'Follow the learner’s chosen topic naturally with one B1–B2 follow-up at a time.'),
];
ConversationScenario conversationScenario(String id) => conversationScenarios
    .firstWhere((s) => s.id == id, orElse: () => conversationScenarios.first);
