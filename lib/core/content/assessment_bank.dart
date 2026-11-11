import '../database/app_database.dart';

/// Small original offline assessment bank (not accredited CEFR exams).
class AssessmentBank {
  static Future<void> seedIfEmpty(AppDatabase db) async {
    Future<void> add(String id, String title, String category, String desc,
        List<List<Object?>> qs) async {
      await db.insertAssessmentDefinition({
        'id': id,
        'title': title,
        'category': category,
        'description': desc,
        'time_limit_seconds': null,
        'pass_threshold': 0.7,
      });
      var i = 0;
      for (final q in qs) {
        await db.insertAssessmentQuestion({
          'id': '${id}_q$i',
          'assessment_id': id,
          'question_type': q[0],
          'prompt': q[1],
          'choices': q[2],
          'correct_answer': q[3],
          'explanation': q[4],
          'order_index': i++,
        });
      }
    }

    await add('as_grammar_b1', 'Grammar checkpoint (B1)', 'grammar',
        'Practice assessment only — not an official CEFR exam.', [
      [
        'mc',
        'She ___ three countries this year.',
        '["visited","has visited","visits"]',
        'has visited',
        'Unfinished time → present perfect.'
      ],
      [
        'mc',
        'If it rains, we ___ inside.',
        '["stay","will stay","would stay"]',
        'will stay',
        'First conditional.'
      ],
      [
        'mc',
        'The report ___ yesterday.',
        '["sent","was sent","is sent"]',
        'was sent',
        'Past passive.'
      ],
      [
        'mc',
        'You ___ see a doctor. (advice)',
        '["must","should","might"]',
        'should',
        'Should for advice.'
      ],
      [
        'mc',
        'I enjoy ___ podcasts.',
        '["to listen","listening","listen"]',
        'listening',
        'Enjoy + gerund.'
      ],
    ]);

    await add('as_vocab_b1', 'Vocabulary checkpoint (B1)', 'vocabulary',
        'Meaning and usage checks. Not an official exam.', [
      [
        'mc',
        'Choose the best meaning of "reliable".',
        '["expensive","can be trusted","temporary"]',
        'can be trusted',
        'Reliable = trustworthy.'
      ],
      [
        'mc',
        'A synonym of "improve" is:',
        '["worsen","enhance","ignore"]',
        'enhance',
        'Enhance means improve.'
      ],
      [
        'mc',
        '"Deadline" is closest to:',
        '["time limit","vacation","salary"]',
        'time limit',
        'Deadline = latest time allowed.'
      ],
      [
        'mc',
        'Which fits: "Please ___ the form."',
        '["fill out","fill up","fill in on"]',
        'fill out',
        'American English: fill out a form.'
      ],
      [
        'mc',
        '"Occasionally" means:',
        '["never","sometimes","always"]',
        'sometimes',
        'Occasionally = from time to time.'
      ],
    ]);

    await add('as_reading_b1', 'Reading comprehension (short)', 'reading',
        'Read the passage carefully. Practice only.', [
      [
        'mc',
        'Passage: "Maya started coding at 14. By 20 she had shipped two apps." What is true?',
        '["Maya is under 14.","Maya shipped apps before age 20.","Maya never coded."]',
        'Maya shipped apps before age 20.',
        'Past perfect shows earlier completion.'
      ],
      [
        'mc',
        'The main idea is about:',
        '["cooking","Maya\'s early coding progress","sports"]',
        'Maya\'s early coding progress',
        'Topic is coding journey.'
      ],
      [
        'mc',
        '"Shipped" here most likely means:',
        '["sent by boat","released/published","broken"]',
        'released/published',
        'Tech usage of ship.'
      ],
    ]);
  }
}
