import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiflow/core/database/app_database.dart';
import 'package:lexiflow/core/services/builtin_content_service.dart';
import 'package:lexiflow/core/backup/backup_service.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;late AppDatabase database;late BuiltinCatalog catalog;late BuiltinContentService service;
  setUp(()async{
    directory=Directory.systemTemp.createTempSync('lexiflow-built-in-');database=AppDatabase(path:'${directory.path}/live.sqlite');
    catalog=await BuiltinCatalog.read((path)=>File(path).readAsString());
    service=BuiltinContentService(database,catalog:()async=>catalog);
  });
  tearDown((){database.close();directory.deleteSync(recursive:true);});
  test('bundled catalog has exact level distributions without personal seeding',()async{
    expect(catalog.words,hasLength(1000));expect(catalog.words.where((w)=>w['level']=='B1'),hasLength(500));expect(catalog.words.where((w)=>w['level']=='B2'),hasLength(500));
    expect(catalog.articles,hasLength(100));expect(catalog.articles.where((a)=>a['level']=='B1'),hasLength(50));expect(catalog.articles.where((a)=>a['level']=='B2'),hasLength(50));
    expect(await database.getVocabulary(),isEmpty);expect(await database.getArticles(),isEmpty);
  });
  test('opening and bookmarking never grant completion; progress survives restart',()async{
    final id=catalog.articles.first['id'] as String;await service.openArticle(id);await service.bookmark(id,true);await service.savePosition(id,240);
    expect((await service.states()).single['completed_at'],isNull);
    database.close();database=AppDatabase(path:'${directory.path}/live.sqlite');service=BuiltinContentService(database,catalog:()async=>catalog);
    final restored=await service.openArticle(id);expect(restored['bookmarked'],1);expect(restored['scroll_offset'],240);expect(restored['completed_at'],isNull);expect(await database.getArticles(),isEmpty);
  });
  test('saving built-in word reuses personal card without overwriting reviews or meanings',()async{
    final word=catalog.words.first;final entry=await database.saveVocabulary(word:word['word'] as String,definition:'My original meaning',translation:'یادداشت شخصی');
    final d=await database.db;d.execute("UPDATE vocabulary_reviews SET next_review_at='2030-01-01',review_count=9 WHERE entry_id=?",[entry]);
    final before=d.select('SELECT * FROM vocabulary_reviews WHERE entry_id=?',[entry]).single;
    expect(await service.saveWord(word['id'] as String),entry);await service.saveWord(word['id'] as String);
    expect(await database.getVocabulary(),hasLength(1));expect((await database.getVocabulary()).single['definition'],'My original meaning');
    expect(d.select('SELECT * FROM vocabulary_reviews WHERE entry_id=?',[entry]).single,before);expect(d.select('SELECT * FROM builtin_word_saves'),hasLength(1));
  });
  test('real answer keys grade and immutable submission token prevents duplicate records',()async{
    final article=catalog.articles.first;final id=article['id'] as String;final questions=article['questions'] as List;
    final answers=<String,String>{for(final q in questions)q['id'] as String:(q['choices'] as List)[q['answer'] as int] as String};
    final first=await service.submit(id:id,token:'stable',startedAt:'2026-01-01',answers:answers,readConfirmed:true);
    expect(first['correct'],4);expect(first['total'],4);await service.submit(id:id,token:'stable',startedAt:'2026-01-01',answers:{},readConfirmed:false);
    final d=await database.db;expect(d.select('SELECT * FROM builtin_reading_attempts'),hasLength(1));expect(d.select("SELECT * FROM learning_activities WHERE type='builtin_reading_completed'"),hasLength(1));expect(d.select('SELECT * FROM study_sessions'),isEmpty);
    expect((await service.states()).single['completed_at'],isNotNull);
  });
  test('incomplete answers and unconfirmed reading do not complete an article',()async{
    final id=catalog.articles.first['id'] as String;
    await expectLater(service.submit(id:id,token:'empty',startedAt:'2026-01-01',answers:{},readConfirmed:true),throwsStateError);
    await expectLater(service.submit(id:id,token:'unread',startedAt:'2026-01-01',answers:{},readConfirmed:false),throwsStateError);
    expect((await database.db).select('SELECT * FROM builtin_reading_attempts'),isEmpty);
  });
  test('daily selection is stable, level-specific, and never auto-saves review cards',()async{
    final first=await service.recommendedWords(level:'B2');expect(first,hasLength(10));expect(first.every((w)=>w['level']=='B2'),isTrue);
    await service.saveWord(first.first['id'] as String);final again=await service.recommendedWords(level:'B2');expect(again.map((w)=>w['id']).toList(),first.map((w)=>w['id']).toList());expect(await database.getVocabulary(),hasLength(1));
    final article=await service.nextArticle('B1');expect(article!['level'],'B1');
  });
  test('catalog updates retain stable IDs and original submitted question snapshots',()async{
    final manifest=jsonDecode(await File('assets/content/v1/manifest.json').readAsString()) as Map<String,dynamic>;
    manifest['content_version']='1.0.1';final updated=await BuiltinCatalog.read((path)async=>path.endsWith('manifest.json')?jsonEncode(manifest):File(path).readAsString());
    final word=catalog.words.first;final original=await service.saveWord(word['id'] as String);final newer=BuiltinContentService(database,catalog:()async=>updated);
    expect(await newer.saveWord(word['id'] as String),original);expect(await database.getVocabulary(),hasLength(1));
  });
  test('full backup restores built-in bookmarks and evidence without copying content into personal articles',()async{
    final id=catalog.articles.first['id'] as String;await service.bookmark(id,true);await service.saveWord(catalog.words.first['id'] as String);
    final archive=File('${directory.path}/content.lexiflowbackup');final backup=BackupService(database,directory,availableBytes:()async=>1<<34);await backup.create(archive);await backup.restore(archive);
    database.close();database=AppDatabase(path:'${directory.path}/live.sqlite');service=BuiltinContentService(database,catalog:()async=>catalog);
    expect((await service.states()).single['bookmarked'],1);expect(await database.getArticles(),isEmpty);expect(await database.getVocabulary(),hasLength(1));
  });
}
