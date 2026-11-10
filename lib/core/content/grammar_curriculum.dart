import '../database/app_database.dart';
import '../utils/id_utils.dart';

/// Original offline B1–B2 grammar curriculum for LexiFlow.
class GrammarCurriculum {
  static Future<void> seedIfEmpty(AppDatabase db) async {
    if (await db.countGrammarLessons() > 0) return;

    final lessons = <_Lesson>[
      // ——— B1 ———
      _Lesson(
        id: 'g_b1_pp',
        title: 'Present Perfect',
        level: 'B1',
        topic: 'present_perfect',
        objective:
            'Use present perfect to talk about experience and recent results.',
        explanation:
            'Form: have/has + past participle.\nUse for experiences (I have visited Canada), unfinished time (this week), and results that matter now (She has lost her keys).',
        examples:
            '• I have finished the report.\n• Have you ever tried sushi?\n• He has lived here since 2019.',
        mistakes:
            '• I have seen him yesterday. → I saw him yesterday.\n• Do not use present perfect with finished past time markers (yesterday, last year).',
        exercises: [
          _Ex(
              'mc',
              'She ___ to three countries this year.',
              '["went","has gone","goes","is going"]',
              'has gone',
              null,
              'Present perfect fits unfinished time (this year).'),
          _Ex(
              'fill',
              'I ___ (never / eat) Indian food.',
              null,
              'have never eaten',
              '["I\'ve never eaten"]',
              'Place never between have and the past participle.'),
          _Ex(
              'mc',
              'Which sentence is correct?',
              '["I have seen that movie last night.","I saw that movie last night.","I have saw that movie last night."]',
              'I saw that movie last night.',
              null,
              'Last night is a finished past time, so use past simple.'),
          _Ex(
              'fill',
              'They ___ (live) in Boston for five years.',
              null,
              'have lived',
              '["They\'ve lived"]',
              'For + duration with present perfect shows a situation continuing to now.'),
          _Ex(
              'correct',
              'He has went to the store.',
              null,
              'He has gone to the store.',
              '["He\'s gone to the store."]',
              'Past participle of go is gone, not went.'),
        ],
      ),
      _Lesson(
        id: 'g_b1_past_perf',
        title: 'Past Perfect',
        level: 'B1',
        topic: 'past_perfect',
        objective:
            'Show that one past action happened before another past action.',
        explanation:
            'Form: had + past participle.\nUse when you need a clear sequence in the past: earlier action = past perfect; later action = past simple.',
        examples:
            '• When I arrived, the train had left.\n• She had already eaten before the meeting.',
        mistakes:
            '• Do not use past perfect for a single past event with no earlier reference.',
        exercises: [
          _Ex(
              'mc',
              'When we got home, the kids ___ asleep.',
              '["already fell","had already fallen","have already fallen"]',
              'had already fallen',
              null,
              'Falling asleep happened before we got home.'),
          _Ex(
              'fill',
              'I ___ (not / finish) the book before the class started.',
              null,
              'had not finished',
              '["hadn\'t finished"]',
              'Earlier incomplete action before class started.'),
          _Ex(
              'mc',
              'Which is correct?',
              '["After he had eaten, he washed the dishes.","After he has eaten, he washed the dishes."]',
              'After he had eaten, he washed the dishes.',
              null,
              'Both actions are in the past; earlier one uses past perfect.'),
          _Ex('fill', 'They realized they ___ (lose) the tickets.', null,
              'had lost', null, 'Losing happened before realizing.'),
          _Ex(
              'correct',
              'She already left when I had called.',
              null,
              'She had already left when I called.',
              null,
              'Leaving was earlier; calling is the later past simple.'),
        ],
      ),
      _Lesson(
        id: 'g_b1_pp_vs_ps',
        title: 'Present Perfect vs Past Simple',
        level: 'B1',
        topic: 'pp_vs_past_simple',
        objective:
            'Choose the right tense based on time reference and connection to now.',
        explanation:
            'Past simple = finished time (yesterday, in 2018).\nPresent perfect = connection to now (ever, already, this week, no finished time).',
        examples:
            '• I visited Rome in 2019.\n• I have visited Rome (at some point in my life).',
        mistakes: '• Mixing finished time markers with present perfect.',
        exercises: [
          _Ex(
              'mc',
              'I ___ my keys this morning. (It is still morning.)',
              '["lost","have lost","had lost"]',
              'have lost',
              null,
              'This morning is unfinished if it is still morning.'),
          _Ex(
              'mc',
              'I ___ my keys yesterday.',
              '["lost","have lost","had lost"]',
              'lost',
              null,
              'Yesterday is finished past time.'),
          _Ex(
              'fill',
              '___ you ever ___ (be) to New York?',
              null,
              'Have you ever been',
              null,
              'Ever + present perfect for life experience.'),
          _Ex(
              'correct',
              'We have moved here in 2020.',
              null,
              'We moved here in 2020.',
              null,
              'In 2020 is a finished time marker.'),
          _Ex(
              'mc',
              'She ___ three emails so far today.',
              '["wrote","has written","writes"]',
              'has written',
              null,
              'So far connects the action to the present.'),
        ],
      ),
      _Lesson(
        id: 'g_b1_future',
        title: 'Future Forms',
        level: 'B1',
        topic: 'future_forms',
        objective:
            'Use will, going to, and present continuous for future meaning.',
        explanation:
            'will: decisions at the moment, predictions, offers.\ngoing to: plans and evidence-based predictions.\nPresent continuous: fixed arrangements.',
        examples:
            '• I\'ll help you with that.\n• We\'re going to launch next month.\n• I\'m meeting Sara at 3.',
        mistakes:
            '• Using will for a plan already decided (prefer going to / present continuous).',
        exercises: [
          _Ex(
              'mc',
              'Look at those clouds! It ___.',
              '["will rain","is going to rain","rains"]',
              'is going to rain',
              null,
              'Evidence now supports going to.'),
          _Ex('fill', 'I ___ (help) you with the bags. (offer)', null,
              'will help', '["I\'ll help"]', 'Offers often use will.'),
          _Ex(
              'mc',
              'We ___ a table for 7 p.m. (arrangement)',
              '["will book","are booking","book"]',
              'are booking',
              null,
              'Fixed arrangement → present continuous.'),
          _Ex(
              'correct',
              'I will meeting him tomorrow.',
              null,
              'I am meeting him tomorrow.',
              '["I\'m meeting him tomorrow."]',
              'Arrangement needs present continuous, not will + -ing.'),
          _Ex(
              'mc',
              'She has decided: she ___ medicine.',
              '["will study","is going to study","studies"]',
              'is going to study',
              null,
              'Prior decision → going to.'),
        ],
      ),
      _Lesson(
        id: 'g_b1_cond12',
        title: 'First & Second Conditionals',
        level: 'B1',
        topic: 'conditionals_1_2',
        objective: 'Talk about real and unreal present/future conditions.',
        explanation:
            'First: if + present, will + base (real future).\nSecond: if + past, would + base (unreal/hypothetical now).',
        examples:
            '• If it rains, we will stay inside.\n• If I had more time, I would learn Spanish.',
        mistakes: '• If I will go… (do not use will in the if-clause).',
        exercises: [
          _Ex(
              'mc',
              'If she ___ early, we will start on time.',
              '["will arrive","arrives","arrived"]',
              'arrives',
              null,
              'First conditional uses present in the if-clause.'),
          _Ex(
              'fill',
              'If I ___ (be) you, I would accept the offer.',
              null,
              'were',
              '["was"]',
              'Were is preferred in formal second conditional; was is common in speech.'),
          _Ex(
              'mc',
              'If we had a car, we ___ drive there.',
              '["will","would","can"]',
              'would',
              null,
              'Second conditional result clause uses would.'),
          _Ex(
              'correct',
              'If it will be sunny, we go to the park.',
              null,
              'If it is sunny, we will go to the park.',
              null,
              'First conditional structure.'),
          _Ex('fill', 'If he studied harder, he ___ (pass) the exam.', null,
              'would pass', null, 'Hypothetical → would + base.'),
        ],
      ),
      _Lesson(
        id: 'g_b1_passive',
        title: 'Passive Voice',
        level: 'B1',
        topic: 'passive',
        objective: 'Form and use basic passive constructions.',
        explanation:
            'be + past participle. Use when the action or result matters more than the doer.',
        examples: '• The email was sent yesterday.\n• English is spoken here.',
        mistakes: '• Forgetting the correct form of be for the tense.',
        exercises: [
          _Ex(
              'mc',
              'The report ___ yesterday.',
              '["sent","was sent","is sent"]',
              'was sent',
              null,
              'Past passive needs was/were + past participle.'),
          _Ex('fill', 'These phones ___ (make) in Korea.', null, 'are made',
              null, 'Present simple passive.'),
          _Ex(
              'correct',
              'The window broken by the storm.',
              null,
              'The window was broken by the storm.',
              null,
              'Passive needs a form of be.'),
          _Ex(
              'mc',
              'A new bridge ___ next year.',
              '["will build","will be built","is building"]',
              'will be built',
              null,
              'Future passive: will be + past participle.'),
          _Ex('fill', 'The results ___ (announce) tomorrow.', null,
              'will be announced', null, 'Future passive.'),
        ],
      ),
      _Lesson(
        id: 'g_b1_relative',
        title: 'Relative Clauses',
        level: 'B1',
        topic: 'relative_clauses',
        objective: 'Use who, which, that, and where to add information.',
        explanation:
            'who → people; which → things; that → people or things (defining); where → places.',
        examples:
            '• The student who called is waiting.\n• This is the book that I recommended.',
        mistakes: '• The man which… (use who for people).',
        exercises: [
          _Ex('mc', 'The woman ___ lives next door is a doctor.',
              '["which","who","where"]', 'who', null, 'Who refers to people.'),
          _Ex('fill', 'This is the café ___ we met.', null, 'where', null,
              'Where for places.'),
          _Ex(
              'mc',
              'I need a laptop ___ is lightweight.',
              '["who","which","where"]',
              'which',
              null,
              'Which for things (that is also fine).'),
          _Ex(
              'correct',
              'The people which arrived late sat at the back.',
              null,
              'The people who arrived late sat at the back.',
              null,
              'Who for people.'),
          _Ex('fill', 'She works for a company ___ designs apps.', null, 'that',
              '["which"]', 'That/which for defining clauses about things.'),
        ],
      ),
      _Lesson(
        id: 'g_b1_reported',
        title: 'Reported Speech',
        level: 'B1',
        topic: 'reported_speech',
        objective: 'Report statements with appropriate backshift.',
        explanation:
            'When the reporting verb is past (said, told), tenses often shift one step back: present → past, will → would.',
        examples:
            '• "I am tired." → She said she was tired.\n• "I will call." → He said he would call.',
        mistakes: '• Forgetting to change pronouns and time expressions.',
        exercises: [
          _Ex(
              'mc',
              '"I work downtown." → She said she ___ downtown.',
              '["work","worked","works"]',
              'worked',
              null,
              'Present → past after past reporting verb.'),
          _Ex('fill', '"We will arrive at 6." → They said they ___ at 6.', null,
              'would arrive', null, 'Will → would.'),
          _Ex(
              'mc',
              '"I can help." → He said he ___ help.',
              '["can","could","will"]',
              'could',
              null,
              'Can → could in reported speech.'),
          _Ex(
              'correct',
              'She said me that she was busy.',
              null,
              'She told me that she was busy.',
              '["She said that she was busy."]',
              'Tell needs an object; say does not.'),
          _Ex('fill', '"I have finished." → He said he ___.', null,
              'had finished', null, 'Present perfect → past perfect.'),
        ],
      ),
      _Lesson(
        id: 'g_b1_modals',
        title: 'Modal Verbs',
        level: 'B1',
        topic: 'modals',
        objective: 'Express ability, obligation, advice, and possibility.',
        explanation:
            'can/could (ability), must/have to (obligation), should (advice), may/might (possibility). Modals are followed by the base form.',
        examples:
            '• You should rest.\n• She might be late.\n• We have to leave now.',
        mistakes: '• You must to go. (no to after most modals)',
        exercises: [
          _Ex('mc', 'You ___ see a doctor. (advice)', '["must","should","can"]',
              'should', null, 'Should is the usual modal for advice.'),
          _Ex('fill', 'She ___ (might / be) at home.', null, 'might be', null,
              'Modal + base form.'),
          _Ex('correct', 'He can to swim very well.', null,
              'He can swim very well.', null, 'No to after can.'),
          _Ex(
              'mc',
              'Employees ___ wear a badge. (rule)',
              '["should","must","might"]',
              'must',
              null,
              'Must for strong obligation/rules.'),
          _Ex('fill', 'I ___ (have to / leave) early today.', null,
              'have to leave', null, 'Have to + base for external obligation.'),
        ],
      ),
      _Lesson(
        id: 'g_b1_gerund_inf',
        title: 'Gerunds & Infinitives',
        level: 'B1',
        topic: 'gerunds_infinitives',
        objective: 'Choose -ing or to-infinitive after common verbs.',
        explanation:
            'enjoy, avoid, finish + -ing.\nwant, decide, hope + to-infinitive.\nSome verbs allow both with a meaning change (stop, remember).',
        examples:
            '• I enjoy reading.\n• She decided to stay.\n• He stopped smoking (quit). / He stopped to smoke (paused in order to).',
        mistakes: '• I want going… → I want to go…',
        exercises: [
          _Ex(
              'mc',
              'I enjoy ___ podcasts.',
              '["to listen","listening","listen"]',
              'listening',
              null,
              'Enjoy takes a gerund.'),
          _Ex('fill', 'They decided ___ (leave) early.', null, 'to leave', null,
              'Decide + to-infinitive.'),
          _Ex(
              'mc',
              'She avoided ___ the question.',
              '["to answer","answering","answer"]',
              'answering',
              null,
              'Avoid + gerund.'),
          _Ex('correct', 'I hope finding a new job.', null,
              'I hope to find a new job.', null, 'Hope + to-infinitive.'),
          _Ex('fill', 'We finished ___ (write) the report.', null, 'writing',
              null, 'Finish + gerund.'),
        ],
      ),
      // ——— B2 ———
      _Lesson(
        id: 'g_b2_cond3',
        title: 'Third & Mixed Conditionals',
        level: 'B2',
        topic: 'conditionals_3_mixed',
        objective:
            'Talk about unreal past situations and mixed time references.',
        explanation:
            'Third: if + past perfect, would have + past participle (unreal past).\nMixed: past condition + present result, or present condition + past result.',
        examples:
            '• If I had studied, I would have passed.\n• If I had taken that job, I would be in Seattle now.',
        mistakes:
            '• If I would have known… (use had + past participle in the if-clause).',
        exercises: [
          _Ex(
              'mc',
              'If she ___ earlier, she would have caught the bus.',
              '["left","had left","would leave"]',
              'had left',
              null,
              'Third conditional if-clause uses past perfect.'),
          _Ex(
              'fill',
              'If we had left on time, we ___ (arrive) by now.',
              null,
              'would have arrived',
              null,
              'Would have + past participle for the unreal past result.'),
          _Ex(
              'correct',
              'If I would have studied, I would pass.',
              null,
              'If I had studied, I would have passed.',
              null,
              'Correct third conditional forms.'),
          _Ex(
              'mc',
              'If he had accepted the offer, he ___ here now.',
              '["would be","would have been","will be"]',
              'would be',
              null,
              'Mixed: past condition, present result.'),
          _Ex(
              'fill',
              'If I ___ (be) more careful, I wouldn\'t have broken it.',
              null,
              'had been',
              null,
              'Past perfect in the if-clause of a third conditional.'),
        ],
      ),
      _Lesson(
        id: 'g_b2_modal_deduction',
        title: 'Modal Deduction',
        level: 'B2',
        topic: 'modal_deduction',
        objective: 'Express degrees of certainty about present and past.',
        explanation:
            'must = strong certainty; might/may/could = possibility; can\'t = strong impossibility.\nPast: must have / might have / can\'t have + past participle.',
        examples:
            '• She must be at work.\n• He can\'t have forgotten — he wrote it down.',
        mistakes:
            '• Using can for positive deduction about the present (prefer must/might).',
        exercises: [
          _Ex(
              'mc',
              'The lights are on. Someone ___ home.',
              '["must be","can\'t be","should be"]',
              'must be',
              null,
              'Strong evidence → must.'),
          _Ex(
              'fill',
              'He ___ (might / leave) already.',
              null,
              'might have left',
              null,
              'Past possibility: might have + past participle.'),
          _Ex(
              'mc',
              'She ___ be serious — that\'s impossible.',
              '["must","can\'t","might"]',
              'can\'t',
              null,
              'Can\'t for strong negative deduction.'),
          _Ex(
              'correct',
              'They must left early.',
              null,
              'They must have left early.',
              null,
              'Past deduction needs have + past participle.'),
          _Ex('fill', 'You ___ (can\'t / see) her — she is abroad.', null,
              'can\'t have seen', null, 'Impossibility about a past event.'),
        ],
      ),
      _Lesson(
        id: 'g_b2_inversion',
        title: 'Inversion',
        level: 'B2',
        topic: 'inversion',
        objective: 'Use inversion after negative adverbials for emphasis.',
        explanation:
            'After never, rarely, not only, under no circumstances, invert subject and auxiliary: Never have I seen…',
        examples:
            '• Rarely do we get such clear data.\n• Not only did she finish early, but she also helped others.',
        mistakes: '• Never I have seen… (missing inversion).',
        exercises: [
          _Ex(
              'mc',
              'Never ___ such a long delay.',
              '["I experienced","have I experienced","I have experienced"]',
              'have I experienced',
              null,
              'Negative adverbial triggers inversion.'),
          _Ex('fill', 'Rarely ___ (we / see) results this fast.', null,
              'do we see', null, 'Inversion with do for present simple.'),
          _Ex(
              'correct',
              'Not only she passed, but she got the highest score.',
              null,
              'Not only did she pass, but she got the highest score.',
              null,
              'Not only + auxiliary + subject.'),
          _Ex(
              'mc',
              'Under no circumstances ___ the password.',
              '["you should share","should you share","you share"]',
              'should you share',
              null,
              'Formal inversion after under no circumstances.'),
          _Ex('fill', 'Seldom ___ (he / complain).', null, 'does he complain',
              null, 'Seldom + inversion.'),
        ],
      ),
      _Lesson(
        id: 'g_b2_participle',
        title: 'Participle Clauses',
        level: 'B2',
        topic: 'participle_clauses',
        objective: 'Shorten clauses with -ing and -ed participles.',
        explanation:
            'Walking down the street, I saw… (same subject).\nBuilt in 1990, the bridge… (passive meaning).',
        examples:
            '• Feeling tired, she went to bed.\n• Designed for beginners, the course is popular.',
        mistakes: '• Dangling participles with a different subject.',
        exercises: [
          _Ex(
              'mc',
              '___ the email, he called support.',
              '["Reading","Read","Having been read"]',
              'Reading',
              null,
              'Active -ing shows simultaneous/earlier action by the same subject.'),
          _Ex('fill', '___ (build) in 2010, the lab is still modern.', null,
              'Built', null, 'Past participle for passive meaning.'),
          _Ex(
              'correct',
              'Walking home, the rain started.',
              null,
              'Walking home, I noticed the rain started.',
              '["As I was walking home, the rain started."]',
              'Avoid dangling participle; keep the same subject or rewrite.'),
          _Ex(
              'mc',
              '___ her work, she left the office.',
              '["Finished","Finishing","Having finished"]',
              'Having finished',
              null,
              'Having + past participle stresses completion before the next action.'),
          _Ex('fill', '___ (not / know) the answer, he stayed quiet.', null,
              'Not knowing', null, 'Negated participle clause.'),
        ],
      ),
      _Lesson(
        id: 'g_b2_linking',
        title: 'Advanced Linking Expressions',
        level: 'B2',
        topic: 'linking',
        objective: 'Connect ideas with precise academic and formal linkers.',
        explanation:
            'Contrast: however, whereas, nevertheless.\nCause: due to, owing to, since.\nAddition: furthermore, in addition.\nResult: therefore, as a result.',
        examples:
            '• The plan is ambitious; however, it is realistic.\n• Due to the delay, the launch was postponed.',
        mistakes:
            '• Using however as a conjunction without proper punctuation.',
        exercises: [
          _Ex(
              'mc',
              'The data was limited; ___, the team reached a decision.',
              '["however","because","although"]',
              'however',
              null,
              'However links contrasting independent clauses.'),
          _Ex('fill', '___ the heavy traffic, we arrived late.', null, 'Due to',
              '["Owing to"]', 'Due to / owing to + noun phrase.'),
          _Ex(
              'mc',
              'The product is cheaper. ___, quality has improved.',
              '["Therefore","Furthermore","Whereas"]',
              'Furthermore',
              null,
              'Furthermore adds information.'),
          _Ex(
              'correct',
              'However the cost is high, demand remains strong.',
              null,
              'Although the cost is high, demand remains strong.',
              '["The cost is high; however, demand remains strong."]',
              'However is not used like although at the start of a dependent clause.'),
          _Ex('fill', 'Sales rose; ___, hiring increased.', null, 'as a result',
              '["therefore"]', 'Result linker.'),
        ],
      ),
    ];

    var order = 0;
    for (final lesson in lessons) {
      await db.insertGrammarLesson({
        'id': lesson.id,
        'title': lesson.title,
        'cefr_level': lesson.level,
        'topic_key': lesson.topic,
        'objective': lesson.objective,
        'explanation': lesson.explanation,
        'examples': lesson.examples,
        'common_mistakes': lesson.mistakes,
        'order_index': order++,
        'completed': 0,
      });
      var ei = 0;
      for (final e in lesson.exercises) {
        await db.insertGrammarExercise({
          'id': '${lesson.id}_e$ei',
          'lesson_id': lesson.id,
          'question_type': e.type,
          'prompt': e.prompt,
          'choices': e.choices,
          'correct_answer': e.answer,
          'alternatives': e.alternatives,
          'explanation': e.explanation,
          'order_index': ei++,
        });
      }
    }
  }
}

class _Lesson {
  final String id,
      title,
      level,
      topic,
      objective,
      explanation,
      examples,
      mistakes;
  final List<_Ex> exercises;
  _Lesson({
    required this.id,
    required this.title,
    required this.level,
    required this.topic,
    required this.objective,
    required this.explanation,
    required this.examples,
    required this.mistakes,
    required this.exercises,
  });
}

class _Ex {
  final String type, prompt;
  final String? choices, answer, alternatives, explanation;
  _Ex(this.type, this.prompt, this.choices, this.answer, this.alternatives,
      this.explanation);
}
