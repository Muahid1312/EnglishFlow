import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/backup/backup_service.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/listening_downloads.dart';

class FakeAudioTransport implements AudioTransport {
  FakeAudioTransport(this.handler);
  final AudioConnection Function(Uri,Map<String,String>) handler;
  final List<Map<String,String>> requests=[];
  @override AudioConnection open(Uri uri,Map<String,String> headers) {
    requests.add(Map.of(headers)); return handler(uri,headers);
  }
}
AudioConnection reply(List<int> bytes,{int status=200,Map<String,String> headers=const {},Stream<List<int>>? body,void Function()? cancel}) => AudioConnection(Future.value(AudioResponse(status,{
  'content-type':'audio/mpeg','content-length':'${bytes.length}',...headers,
},body ?? Stream.fromIterable([bytes]))),cancel ?? (){});
Future<void> until(bool Function() check) async {
  for(var i=0;i<200;i++) { if(check())return; await Future<void>.delayed(const Duration(milliseconds:5)); }
  fail('Transfer did not reach the expected real state.');
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root,documents;
  late AppDatabase db;
  late ListeningCatalog catalog;
  late Map<String,dynamic> lesson;
  late List<int> audio;
  late FakeAudioTransport transport;
  late ListeningDownloads downloads;
  var freeBytes=1<<34;
  ListeningDownloads manager() => ListeningDownloads(db,catalog:()async=>catalog,
    documents:()async=>documents,availableBytes:()async=>freeBytes,transport:transport,observeLifecycle:false);
  setUp(()async{
    root=Directory.systemTemp.createTempSync('lexiflow-download-test-');documents=Directory('${root.path}/documents');
    db=AppDatabase(path:'${root.path}/data.sqlite');
    catalog=ListeningCatalog.parse(await File('assets/listening/catalog_v1.json').readAsString());
    lesson=catalog.lessons.first;audio=await File('listening_catalog/media/${lesson['file']}').readAsBytes();freeBytes=1<<34;
    transport=FakeAudioTransport((uri,headers)=>reply(audio,headers:{'accept-ranges':'bytes','etag':'"stable"'}));
    downloads=manager();await downloads.initialize();
  });
  tearDown(()async{await downloads.suspend();downloads.dispose();db.close();root.deleteSync(recursive:true);});
  String getId()=>lesson['id'] as String;
  test('catalogue permissions and shipped metadata reference actual original recordings',()async{
    expect(catalog.lessons,hasLength(4));
    for(final item in catalog.lessons){
      final file=File('listening_catalog/media/${item['file']}');
      expect(await file.length(),item['bytes']);expect((await sha256.bind(file.openRead()).first).toString(),item['sha256']);
      expect(item['speaker'],contains('synthetic'));expect(await audioExtension(file),'.mp3');
    }
    final invalid=jsonDecode(await File('assets/listening/catalog_v1.json').readAsString()) as Map<String,dynamic>;
    (invalid['lessons'] as List).first['download_allowed']=false;
    expect(()=>ListeningCatalog.parse(jsonEncode(invalid)),throwsFormatException);
    expect(await db.getListeningLessons(),isEmpty);
  });
  test('successful download verifies audio before registering one offline lesson and keyed exercises',()async{
    await downloads.enqueue(getId());await downloads.waitUntilIdle();
    expect(downloads.jobs[getId()]!['status'],'downloaded');
    final saved=(await db.getListeningLessons()).single;
    expect(File(saved['audio_path'] as String).existsSync(),isTrue);
    expect(await File(saved['audio_path'] as String).length(),audio.length);
    expect(saved['transcript'],lesson['transcript']);expect(await db.getQuestions(saved['id'] as String),hasLength(4));
    expect((await db.db).select('SELECT * FROM study_sessions'),isEmpty);
    expect(transport.requests,hasLength(1));
  });
  test('concurrent taps and subsequent saves never create duplicate transfers or lesson records',()async{
    await Future.wait(List.generate(8,(_)=>downloads.enqueue(getId())));await downloads.waitUntilIdle();
    await downloads.enqueue(getId());await downloads.waitUntilIdle();
    expect(transport.requests,hasLength(1));expect(await db.getListeningLessons(),hasLength(1));
  });
  test('multiple queued lessons download sequentially and create distinct offline lessons',()async{
    final payloads=<String,List<int>>{};final order=<String>[];
    for(final row in catalog.lessons.take(2)){payloads[row['audio_url'] as String]=await File('listening_catalog/media/${row['file']}').readAsBytes();}
    transport=FakeAudioTransport((uri,headers){order.add(uri.toString());return reply(payloads[uri.toString()]!);});
    downloads.dispose();downloads=manager();await downloads.initialize();await downloads.suspend();
    for(final row in catalog.lessons.take(2)){await downloads.enqueue(row['id'] as String);}
    expect(downloads.jobs.values.every((j)=>j['status']=='queued'),isTrue);expect(transport.requests,isEmpty);
    downloads.resumeQueue();await downloads.waitUntilIdle();
    expect(order,catalog.lessons.take(2).map((l)=>l['audio_url']).toList());expect(await db.getListeningLessons(),hasLength(2));
  });
  test('network interruption remains failed with actual bytes and resumes through a validated 206 response',()async{
    final cut=128*1024;
    transport=FakeAudioTransport((uri,headers){
      if(headers['Range']==null){
        return reply(audio,headers:{'accept-ranges':'bytes','etag':'"stable"'},body:()async*{yield audio.sublist(0,cut);throw const SocketException('fixture interruption');}());
      }
      expect(headers['Range'],'bytes=$cut-');expect(headers['If-Range'],'"stable"');
      return reply(audio.sublist(cut),status:206,headers:{'accept-ranges':'bytes','etag':'"stable"','content-range':'bytes $cut-${audio.length-1}/${audio.length}'});
    });
    downloads.dispose();downloads=manager();await downloads.enqueue(getId());await downloads.waitUntilIdle();
    expect(downloads.jobs[getId()]!['status'],'failed');expect(downloads.jobs[getId()]!['bytes_received'],cut);
    expect(await db.getListeningLessons(),isEmpty);
    await downloads.enqueue(getId());await downloads.waitUntilIdle();expect(downloads.jobs[getId()]!['status'],'downloaded');expect(transport.requests,hasLength(2));
  });
  test('a server ignoring Range restarts the file without appending duplicate bytes',()async{
    var first=true;
    transport=FakeAudioTransport((uri,headers){if(first){first=false;return reply(audio,headers:{'accept-ranges':'bytes'},body:()async*{yield audio.sublist(0,128*1024);throw const SocketException('fixture');}());}return reply(audio);});
    downloads.dispose();downloads=manager();await downloads.enqueue(getId());await downloads.waitUntilIdle();
    await downloads.enqueue(getId());await downloads.waitUntilIdle();
    expect(transport.requests.last['Range'],isNotNull);expect(downloads.jobs[getId()]!['status'],'downloaded');
  });
  test('HTML disguised as audio fails verification and is never marked downloaded',()async{
    final html=List<int>.filled(audio.length,32);html.setRange(0,13,utf8.encode('<html>error!!!'));
    transport=FakeAudioTransport((uri,headers)=>reply(html,headers:{'accept-ranges':'bytes'}));
    downloads.dispose();downloads=manager();await downloads.enqueue(getId());await downloads.waitUntilIdle();
    expect(downloads.jobs[getId()]!['status'],'failed');expect(downloads.jobs[getId()]!['bytes_received'],0);expect(await db.getListeningLessons(),isEmpty);
  });
  test('content size and checksum mismatch discard temporary data',()async{
    final corrupt=List<int>.from(audio);corrupt[corrupt.length-10]^=1;
    transport=FakeAudioTransport((uri,headers)=>reply(corrupt,headers:{'accept-ranges':'bytes'}));
    downloads.dispose();downloads=manager();await downloads.enqueue(getId());await downloads.waitUntilIdle();
    expect(downloads.jobs[getId()]!['status'],'failed');expect(downloads.jobs[getId()]!['supports_resume'],0);expect(await db.getListeningLessons(),isEmpty);
    transport=FakeAudioTransport((uri,headers)=>reply(audio,headers:{'content-length':'${audio.length+1}'}));
    downloads.dispose();downloads=manager();await downloads.enqueue(getId());await downloads.waitUntilIdle();expect(downloads.jobs[getId()]!['status'],'failed');
  });
  test('insufficient storage fails before a network request or a personal lesson is created',()async{
    freeBytes=0;await downloads.enqueue(getId());await downloads.waitUntilIdle();
    expect(downloads.jobs[getId()]!['status'],'failed');expect(downloads.jobs[getId()]!['error'],contains('storage'));expect(transport.requests,isEmpty);expect(await db.getListeningLessons(),isEmpty);
  });
  test('pause keeps a verified byte prefix only when ranges are supported, and cancellation removes it',()async{
    final body=StreamController<List<int>>();
    transport=FakeAudioTransport((uri,headers)=>reply(audio,headers:{'accept-ranges':'bytes'},body:body.stream,cancel:(){if(!body.isClosed)unawaited(body.close());}));
    downloads.dispose();downloads=manager();await downloads.enqueue(getId());
    await until(()=>downloads.jobs[getId()]?['supports_resume']==1);
    body.add(audio.sublist(0,128*1024));await until(()=>(downloads.jobs[getId()]?['bytes_received'] as int? ?? 0)>0);
    await downloads.pause(getId());await downloads.waitUntilIdle();
    expect(downloads.jobs[getId()]!['status'],'paused');expect(await downloads.storageBytes(),128*1024);
    await downloads.cancel(getId());expect(downloads.jobs[getId()]!['status'],'available');expect(await downloads.storageBytes(),0);expect(await db.getListeningLessons(),isEmpty);
  });
  test('queued cancellation and unsafe destinations do not start transfers',()async{
    await downloads.suspend();await downloads.enqueue(getId());expect(downloads.jobs[getId()]!['status'],'queued');
    await downloads.cancel(getId());downloads.resumeQueue();await downloads.waitUntilIdle();expect(transport.requests,isEmpty);
    for(final uri in ['http://raw.githubusercontent.com/a','file:///etc/passwd','https://localhost/a','https://raw.githubusercontent.com:444/a','https://user:password@raw.githubusercontent.com/a']){expect(()=>checkedMediaUri(uri),throwsA(isA<AudioDownloadFailure>()));}
  });
  test('redirects outside the authorized HTTPS host are rejected',()async{
    transport=FakeAudioTransport((uri,headers)=>reply([],status:302,headers:{'location':'https://example.org/audio.mp3'}));
    downloads.dispose();downloads=manager();await downloads.enqueue(getId());await downloads.waitUntilIdle();expect(downloads.jobs[getId()]!['status'],'failed');expect(transport.requests,hasLength(1));
  });
  test('resume rejects a mismatched Content-Range before finalizing any file',()async{
    var first=true;transport=FakeAudioTransport((uri,headers){if(first){first=false;return reply(audio,headers:{'accept-ranges':'bytes'},body:()async*{yield audio.sublist(0,128*1024);throw const SocketException('fixture');}());}return reply(audio.sublist(128*1024),status:206,headers:{'content-range':'bytes 0-${audio.length-1}/${audio.length}'});});
    downloads.dispose();downloads=manager();await downloads.enqueue(getId());await downloads.waitUntilIdle();await downloads.enqueue(getId());await downloads.waitUntilIdle();
    expect(downloads.jobs[getId()]!['status'],'failed');expect(await db.getListeningLessons(),isEmpty);
  });
  test('restart retains verified local audio without any network and removal preserves learner evidence',()async{
    await downloads.enqueue(getId());await downloads.waitUntilIdle();final saved=(await db.getListeningLessons()).single;final id=saved['id'] as String;
    await db.updateLessonPosition(id,15000);await db.addBookmark('saved-place',id,12000);
    final question=(await db.getQuestions(id)).first;
    await db.saveAttempt({'id':'answer','question_id':question['id'],'lesson_id':id,'learner_response':question['correct_answer'],'is_correct':1,'self_assessed':0});
    downloads.dispose();db.close();db=AppDatabase(path:'${root.path}/data.sqlite');
    transport=FakeAudioTransport((uri,headers)=>throw StateError('Offline: no network may be used'));
    downloads=manager();await downloads.initialize();expect(downloads.jobs[getId()]!['status'],'downloaded');
    expect(File((await db.getListeningLesson(id))!['audio_path'] as String).isAbsolute,isTrue);
    await downloads.removeAudio(id);expect(File(saved['audio_path'] as String).existsSync(),isFalse);
    expect((await db.getListeningLesson(id))!['last_position_ms'],15000);expect((await db.getListeningLesson(id))!['transcript'],lesson['transcript']);
    expect(await db.getBookmarks(id),hasLength(1));expect(await db.getComprehensionAttempts(id),hasLength(1));expect(await db.getQuestions(id),hasLength(4));expect(downloads.jobs[getId()]!['status'],'available');
  });
  test('redownload reuses the lesson and preserves edited transcripts and existing questions',()async{
    await downloads.enqueue(getId());await downloads.waitUntilIdle();final id=(await db.getListeningLessons()).single['id'] as String;
    await db.updateLessonTranscript(id,'My edited transcript');await db.updateLessonPosition(id,1000);
    await downloads.removeAudio(id);await downloads.enqueue(getId());await downloads.waitUntilIdle();
    expect(await db.getListeningLessons(),hasLength(1));expect((await db.getListeningLesson(id))!['transcript'],'My edited transcript');expect((await db.getListeningLesson(id))!['last_position_ms'],1000);expect(await db.getQuestions(id),hasLength(4));
  });
  test('backup restores verified audio through rewritten media paths, with partial jobs excluded',()async{
    await downloads.enqueue(getId());await downloads.waitUntilIdle();await downloads.suspend();
    final archive=File('${root.path}/audio.lexiflowbackup');final backup=BackupService(db,documents,availableBytes:()async=>1<<34);
    await backup.create(archive);await backup.restore(archive);downloads.dispose();db.close();db=AppDatabase(path:'${root.path}/data.sqlite');downloads=manager();await downloads.initialize();
    expect(downloads.jobs[getId()]!['status'],'downloaded');expect((await db.getListeningLessons()).single['audio_path'],contains('restored-media-'));expect((await db.db).select('PRAGMA foreign_key_check'),isEmpty);
  });
  test('import validates actual audio and copies it privately without moving the chosen file',()async{
    final source=File('${root.path}/picked.mp3')..writeAsBytesSync(audio);final id=await downloads.importFile(source,'Permitted recording');
    final saved=(await db.getListeningLesson(id))!;expect(saved['audio_path'],startsWith(documents.path));expect(source.existsSync(),isTrue);expect(await File(saved['audio_path'] as String).length(),audio.length);
    final bad=File('${root.path}/page.mp3')..writeAsStringSync('<html>${List.filled(200,'error').join()}</html>');await expectLater(downloads.importFile(bad,'Bad page'),throwsA(isA<AudioDownloadFailure>()));expect(await db.getListeningLessons(),hasLength(1));
  });
  test('schema 11 upgrades without seeding downloaded lessons or altering personal records',()async{
    final legacy=AppDatabase.schemaTemplate(11);final path='${root.path}/legacy.sqlite';
    try{await legacy.saveVocabulary(word:'preserve',definition:'My own meaning');await legacy.snapshot(path);}finally{legacy.close();}
    final upgraded=AppDatabase(path:path);try{expect((await upgraded.getVocabulary()).single['definition'],'My own meaning');expect((await upgraded.db).select('SELECT * FROM listening_downloads'),isEmpty);expect((await upgraded.db).select('PRAGMA user_version').single['user_version'],12);}finally{upgraded.close();}
  });
}
