import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../utils/id_utils.dart';

class CertificateService {
  CertificateService(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Creates completion + certificate record and writes a PDF. Returns file path.
  Future<String> issue({
    required String learnerName,
    required String targetType,
    required String targetId,
    required String targetTitle,
    required String verificationType,
    double? assessmentScore,
    bool eligible = true,
  }) async {
    if (!eligible) {
      throw StateError('Not eligible for a certificate.');
    }
    final evidence = await _db.certificateEvidence(targetType, targetId);
    if (evidence == null) {
      throw StateError(
          'Persisted lesson completion and required passing assessments are missing.');
    }
    verificationType = evidence['verification_type'] as String;
    assessmentScore = (evidence['score'] as num).toDouble();
    targetTitle = evidence['title'] as String;
    final name = learnerName.trim().isEmpty ? 'Learner' : learnerName.trim();
    final completionId = newId();
    final certId = newId();
    final ref =
        'LF-${DateTime.now().year}-${_uuid.v4().substring(0, 8).toUpperCase()}';
    final now = DateTime.now().toUtc().toIso8601String();

    final completion = <String, Object?>{
      'id': completionId,
      'target_type': targetType,
      'target_id': targetId,
      'target_title': targetTitle,
      'verification_type': verificationType,
      'assessment_score': assessmentScore,
      'completed_at': now,
      'certificate_eligible': 1,
      'certificate_ref': ref,
    };

    final scoreText = '${(assessmentScore * 100).round()}% assessment score';
    final bytes = await render(
        learnerName: name,
        title: targetTitle,
        reference: ref,
        issuedAt: now,
        scoreText: scoreText,
        verificationType: verificationType);

    final dir = await getApplicationDocumentsDirectory();
    final certDir = Directory(p.join(dir.path, 'certificates'));
    if (!await certDir.exists()) await certDir.create(recursive: true);
    final filePath = p.join(certDir.path, '$ref.pdf');
    final file = File(filePath);
    await file.writeAsBytes(bytes);

    try {
      await _db.saveCertificateWithCompletion(completion, {
        'id': certId,
        'completion_id': completionId,
        'learner_name': name,
        'title': targetTitle,
        'ref_number': ref,
        'score_text': scoreText,
        'verification_type': verificationType,
        'issued_at': now,
        'file_path': filePath,
      });
    } catch (_) {
      await file.delete();
      rethrow;
    }

    return filePath;
  }

  /// Recreates a historical PDF solely from its immutable issued record.
  static Future<Uint8List> render(
      {required String learnerName,
      required String title,
      required String reference,
      required String issuedAt,
      required String scoreText,
      required String verificationType}) async {
    final regular = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final bold = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    final italic = await rootBundle.load('assets/fonts/NotoSans-Italic.ttf');
    final arabic =
        await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
    final doc = pw.Document(
        theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
      italic: pw.Font.ttf(italic),
      fontFallback: [pw.Font.ttf(arabic)],
    ));
    final dateStr =
        DateFormat.yMMMMd().format(DateTime.parse(issuedAt).toLocal());

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border:
                  pw.Border.all(color: PdfColor.fromHex('#1A1F36'), width: 2),
            ),
            padding: const pw.EdgeInsets.all(28),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('LEXIFLOW',
                    style: pw.TextStyle(
                        fontSize: 14,
                        letterSpacing: 3,
                        color: PdfColor.fromHex('#6B5B95'))),
                pw.SizedBox(height: 12),
                pw.Text('CERTIFICATE OF COMPLETION',
                    style: pw.TextStyle(
                        fontSize: 26,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#1A1F36'))),
                pw.SizedBox(height: 20),
                pw.Text('This certificate recognizes that',
                    style: const pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 8),
                pw.SizedBox(
                    height: 38,
                    child: pw.FittedBox(
                        fit: pw.BoxFit.scaleDown,
                        child: pw.Text(learnerName,
                            style: pw.TextStyle(
                                fontSize: 22,
                                fontWeight: pw.FontWeight.bold)))),
                pw.SizedBox(height: 8),
                pw.Text('has completed the learning requirements for',
                    style: const pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 8),
                pw.SizedBox(
                    height: 40,
                    child: pw.FittedBox(
                        fit: pw.BoxFit.scaleDown,
                        child: pw.Text(title,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(
                                fontSize: 16,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColor.fromHex('#4A3F6B'))))),
                pw.SizedBox(height: 16),
                pw.Text('within the LexiFlow learning application.',
                    style: const pw.TextStyle(fontSize: 11)),
                ...[
                  pw.SizedBox(height: 10),
                  pw.Text(scoreText, style: const pw.TextStyle(fontSize: 11)),
                ],
                pw.Spacer(),
                pw.Text(
                    'Personal learning achievement — not an accredited qualification.',
                    style: pw.TextStyle(
                        fontSize: 9,
                        color: PdfColor.fromHex('#5C6378'),
                        fontStyle: pw.FontStyle.italic)),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Date: $dateStr',
                        style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('Ref: $reference',
                        style: const pw.TextStyle(fontSize: 10)),
                    pw.Expanded(
                        child: pw.Text(
                            'Verification: ${verificationType == 'lessons_and_assessments' ? 'Self-reported lessons + assessment results' : verificationType}',
                            textAlign: pw.TextAlign.right,
                            style: const pw.TextStyle(fontSize: 8))),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return doc.save();
  }

  static Future<Uint8List> historicalPdf(Map<String, dynamic> record) => render(
      learnerName: record['learner_name'] as String,
      title: record['title'] as String,
      reference: record['ref_number'] as String,
      issuedAt: record['issued_at'] as String,
      scoreText: record['score_text'] as String? ?? '',
      verificationType: record['verification_type'] as String);
}
