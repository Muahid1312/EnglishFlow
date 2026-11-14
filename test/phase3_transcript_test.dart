import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/audio_player_controller.dart';
import 'package:lexiflow/core/services/transcript_parser.dart';
import 'package:lexiflow/features/listening_speaking/listening/synchronized_transcript.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const srt='1\n00:00:01,000 --> 00:00:02,500\nHello there.\n\n2\n00:00:03,000 --> 00:00:05,000\nA second line.';
  test('SRT timestamps, gaps and exclusive end boundaries are deterministic',(){
    final parsed=parseTranscript('\uFEFF$srt');
    expect(parsed.format,'srt');expect(parsed.cues,hasLength(2));
    expect(parsed.activeIndex(999),-1);expect(parsed.activeIndex(1000),0);
    expect(parsed.activeIndex(2499),0);expect(parsed.activeIndex(2500),-1);
    expect(parsed.activeIndex(3000),1);expect(parsed.activeIndex(5000),-1);
    expect(parsed.cues[1].startMs,3000);
  });
  test('WebVTT supports cue identifiers, settings, metadata and real text',(){
    final parsed=parseTranscript('WEBVTT\nKind: captions\n\nNOTE ignored metadata\nnot speech\n\nintro\n00:01.000 --> 00:02.000 align:start\n<v Speaker>Hello &amp; welcome.</v>');
    expect(parsed.format,'vtt');expect(parsed.cues.single.text,'Hello & welcome.');
    expect(parsed.cues.single.startMs,1000);
  });
  test('plain TXT never invents synchronization',(){
    final plain=parseTranscript('A plain transcript without time codes.');
    expect(plain.synchronized,isFalse);expect(plain.cues,isEmpty);
    expect(parseTranscript('A literal --> arrow.',format:'plain').synchronized,isFalse);
  });
  for(final text in [
    '1\n00:00:02,000 --> 00:00:01,000\nBackwards',
    '1\n00:00:01,000 --> 00:00:03,000\nFirst\n\n2\n00:00:02,000 --> 00:00:04,000\nOverlap',
    '1\n00:99:00,000 --> 01:00:00,000\nBad minutes',
    '1\n00:00:01 --> 00:00:02\nMissing milliseconds',
    '1\n00:00:01,000 --> 00:00:02,000',
  ]) {
    test('malformed or unordered cue is rejected: ${text.split('\n').first}',()=>expect(()=>parseTranscript(text),throwsFormatException));
  }
  test('transcript size is bounded before parsing',()=>expect(()=>parseTranscript('x'*1000001),throwsFormatException));
  test('A–B range uses absolute media positions and rejects invalid ranges',(){
    final loop=AudioLoopRange(1000,3000,5000);
    expect(loop.shouldRepeat(2999),isFalse);expect(loop.shouldRepeat(3000),isTrue);
    for(final values in [[-1,1000],[1000,1000],[2000,1000],[1000,6000]]) {
      expect(()=>AudioLoopRange(values[0],values[1],5000),throwsArgumentError);
    }
  });
  test('speed, loop, transcript and visibility preference survive restart',() async {
    final dir=Directory.systemTemp.createTempSync('lexiflow-phase3-listening-');
    var db=AppDatabase(path:'${dir.path}/db.sqlite');
    try {
      await db.insertListeningLesson({'id':'l','title':'Real lesson','audio_path':'missing.mp3','duration_ms':10000});
      await db.saveListeningPreferences('l',speed:1.25,startMs:1000,endMs:4000,autoScroll:false,transcript:srt,transcriptFormat:'srt');
      await expectLater(db.saveListeningPreferences('l',speed:2),throwsArgumentError);
      await expectLater(db.saveListeningPreferences('l',startMs:5000,endMs:4000),throwsArgumentError);
      db.close();db=AppDatabase(path:'${dir.path}/db.sqlite');
      final row=(await db.getListeningLesson('l'))!;
      expect(row['playback_speed'],1.25);expect(row['loop_start_ms'],1000);expect(row['loop_end_ms'],4000);
      expect(row['transcript_auto_scroll'],0);expect(row['transcript_format'],'srt');expect(row['transcript'],srt);
      await db.saveListeningPreferences('l',clearLoop:true);
      expect((await db.getListeningLesson('l'))!['loop_start_ms'],isNull);
    } finally {db.close();dir.deleteSync(recursive:true);}
  });
  testWidgets('tap seeks to a real cue and only timed cues highlight',(tester) async {
    final positions=StreamController<Duration>.broadcast();
    Duration? sought;
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:SynchronizedTranscript(
      transcript:parseTranscript(srt),positions:positions.stream,autoScroll:true,
      seek:(position) async {sought=position;}))));
    positions.add(const Duration(milliseconds:1500));await tester.pumpAndSettle();
    final tiles=tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles[0].selected,isTrue);expect(tiles[1].selected,isFalse);
    await tester.tap(find.text('A second line.'));expect(sought,const Duration(seconds:3));
    positions.add(const Duration(milliseconds:2700));await tester.pumpAndSettle();
    expect(tester.widgetList<ListTile>(find.byType(ListTile)).every((t)=>!t.selected),isTrue);
    await tester.pumpWidget(const SizedBox());await positions.close();
  });
}
