import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';

class ArticleImportService {
  ArticleImportService(this.db, {Future<String> Function(String)? extractPdf})
      : _extractPdf = extractPdf ?? _nativePdfText;
  final AppDatabase db;
  final Future<String> Function(String) _extractPdf;
  static const channel = MethodChannel('lexiflow/pdf_text');
  static Future<String> _nativePdfText(String path) async =>
      await channel.invokeMethod<String>('extract', {'path': path}) ?? '';

  Future<String> importFile(File file, {String? name}) async {
    final filename = name ?? p.basename(file.path);
    final extension = p.extension(filename).toLowerCase();
    final size = await file.length();
    if (size > (extension == '.txt' ? 10 : 40) * 1024 * 1024) {
      throw const FormatException(
          'File is too large. TXT limit: 10 MB; PDF limit: 40 MB.');
    }
    String body;
    if (extension == '.txt') {
      try {
        body = utf8
            .decode(await file.readAsBytes())
            .replaceFirst(RegExp('^\uFEFF'), '');
      } on FormatException {
        throw const FormatException(
            'Save this TXT file as UTF-8, then import again.');
      }
    } else if (extension == '.pdf') {
      try {
        body = await _extractPdf(file.path);
      } on MissingPluginException {
        throw const FormatException(
            'PDF text extraction is supported on Android. Import a TXT copy on this platform.');
      } on PlatformException {
        throw const FormatException(
            'Could not extract PDF text. It may be protected, corrupt, or too large.');
      }
      if (body.trim().isEmpty) {
        throw const FormatException(
            'This PDF has no extractable text. Scanned PDFs need OCR; import a TXT version instead.');
      }
    } else {
      throw const FormatException(
          'Choose a TXT article or a selectable-text PDF.');
    }
    body = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (body.trim().isEmpty) {
      throw const FormatException('This file has no readable text.');
    }
    if (body.length > 1000000) {
      throw const FormatException(
          'Article text exceeds one million characters. Import a shorter section.');
    }
    return db.saveArticle(p.basenameWithoutExtension(filename), body,
        sourceName: filename);
  }
}

/// Returns the complete source sentence around the exact selection offsets.
String sourceSentence(String text, int start, int end) {
  if (start < 0 || end > text.length || start >= end) return '';
  var left = start;
  var right = end;
  while (left > 0 && !'.!?\n'.contains(text[left - 1])) {
    left--;
  }
  if ('.!?'.contains(text[end - 1])) return text.substring(left, end).trim();
  while (right < text.length && !'.!?\n'.contains(text[right])) {
    right++;
  }
  if (right < text.length && text[right] != '\n') right++;
  return text.substring(left, right).trim();
}
