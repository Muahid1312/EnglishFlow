class TranscriptCue {
  const TranscriptCue(this.startMs, this.endMs, this.text);
  final int startMs, endMs;
  final String text;
}

class ParsedTranscript {
  const ParsedTranscript(this.text, this.cues, this.format);
  final String text, format;
  final List<TranscriptCue> cues;
  bool get synchronized => cues.isNotEmpty;
  int activeIndex(int milliseconds) {
    var low = 0, high = cues.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final cue = cues[middle];
      if (milliseconds < cue.startMs) {
        high = middle - 1;
      } else if (milliseconds >= cue.endMs) {
        low = middle + 1;
      } else {
        return middle;
      }
    }
    return -1;
  }
}

/// Bounded SRT/WebVTT text parser. It never guesses timestamps for plain text.
/// Cues must be ordered and nonoverlapping; invalid input is rejected rather
/// than silently changing the learner's transcript or inventing synchronization.
ParsedTranscript parseTranscript(String input, {String? format}) {
  if (input.length > 1000000) {
    throw const FormatException(
        'Transcript is too large (maximum 1,000,000 characters).');
  }
  final text = input
      .replaceFirst(RegExp('^\uFEFF'), '')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  final kind = format ??
      (text.trimLeft().startsWith('WEBVTT')
          ? 'vtt'
          : text.contains('-->')
              ? 'srt'
              : 'plain');
  if (kind == 'plain') return ParsedTranscript(text, const [], 'plain');
  if (!['srt', 'vtt'].contains(kind)) {
    throw const FormatException('Use TXT, SRT or WebVTT.');
  }
  var body = text.trim();
  if (kind == 'vtt') {
    if (!RegExp(r'^WEBVTT(?:[ \t].*)?(?:\n|$)').hasMatch(body)) {
      throw const FormatException('Missing WEBVTT header.');
    }
    final header = body.indexOf('\n\n');
    if (header < 0) {
      if (body.contains('-->')) {
        throw const FormatException(
            'WebVTT requires a blank line after the header.');
      }
      return ParsedTranscript(text, const [], 'vtt');
    }
    body = body.substring(header + 2);
  }
  int timestamp(String value) {
    final match =
        RegExp(r'^(?:(\d{2,}):)?(\d{2}):(\d{2})[.,](\d{3})$').firstMatch(value);
    if (match == null) {
      throw const FormatException('Invalid transcript timestamp.');
    }
    final hours = int.parse(match[1] ?? '0'),
        minutes = int.parse(match[2]!),
        seconds = int.parse(match[3]!);
    if (minutes > 59 || seconds > 59 || hours > 99) {
      throw const FormatException('Transcript timestamp is out of range.');
    }
    return ((hours * 60 + minutes) * 60 + seconds) * 1000 +
        int.parse(match[4]!);
  }

  final cues = <TranscriptCue>[];
  for (final block in body.split(RegExp(r'\n[ \t]*\n'))) {
    final lines = block.trim().split('\n');
    if (lines.isEmpty || lines.first.isEmpty) continue;
    if (kind == 'vtt' &&
        RegExp(r'^(NOTE(?:\s|$)|STYLE$|REGION$)').hasMatch(lines.first)) {
      continue;
    }
    final timing = lines.indexWhere((line) => line.contains('-->'));
    if (timing < 0 || timing > 1 || lines.length <= timing + 1) {
      throw const FormatException(
          'A transcript cue is missing timing or text.');
    }
    final match =
        RegExp(r'^\s*(\S+)\s+-->\s+(\S+)(?:\s+.*)?$').firstMatch(lines[timing]);
    if (match == null) {
      throw const FormatException('Invalid transcript timing line.');
    }
    final start = timestamp(match[1]!), end = timestamp(match[2]!);
    if (end <= start || (cues.isNotEmpty && start < cues.last.endMs)) {
      throw const FormatException(
          'Cues must be ordered, nonoverlapping, and have positive durations.');
    }
    final content = lines
        .skip(timing + 1)
        .join('\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
    if (content.isEmpty) {
      throw const FormatException('Transcript cue text is empty.');
    }
    cues.add(TranscriptCue(start, end, content));
    if (cues.length > 5000) {
      throw const FormatException('Too many transcript cues (maximum 5,000).');
    }
  }
  return ParsedTranscript(text, List.unmodifiable(cues), kind);
}
