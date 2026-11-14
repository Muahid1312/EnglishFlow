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
    expect(catalog.words.length,1000);expect(catalog.words.where((w)=>w['level']=='B1').length,500);expect(catalog.words.where((w)=>w['level']=='B2').length,500);
    expect(catalog.articles.length,100);expect(catalog.articles.where((a)=>a['level']=='B1').length,50);expect(catalog.articles.where((a)=>a['level']=='B2').length,50);
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
    final article=catalog.articles.first;final questions=article['questions'] as List;
    await service.submit(id:article['id'] as String,token:'before-update',startedAt:'2026-01-01',answers:{for(final q in questions)q['id'] as String:(q['choices'] as List)[q['answer'] as int] as String},readConfirmed:true);
    final manifest=jsonDecode(await File('assets/content/v1/manifest.json').readAsString()) as Map<String,dynamic>;
    manifest['content_version']='1.0.1';final updated=await BuiltinCatalog.read((path)async{
      if(path.endsWith('manifest.json'))return jsonEncode(manifest);
      final data=jsonDecode(await File(path).readAsString()) as Map<String,dynamic>;
      if(data.containsKey('articles'))for(final row in data['articles'] as List){if(row['id']==article['id'])(row['questions'] as List).first['prompt']='Updated prompt';}
      return jsonEncode(data);
    });
    final word=catalog.words.first;final original=await service.saveWord(word['id'] as String);final newer=BuiltinContentService(database,catalog:()async=>updated);
    expect(await newer.saveWord(word['id'] as String),original);expect(await database.getVocabulary(),hasLength(1));
    expect(((updated.article(article['id'] as String)['questions'] as List).first as Map)['prompt'],'Updated prompt');
    final attempt=(await newer.history(article['id'] as String)).single;
    expect((jsonDecode(attempt['questions_json'] as String) as List).first['prompt'],(questions.first as Map)['prompt']);expect(attempt['content_version'],'1.0.0');
  });
  test('daily selection follows the local date and unread recommendations skip real completions',()async{
    var now=DateTime(2026,11,14,10);service=BuiltinContentService(database,catalog:()async=>catalog,now:()=>now);
    final today=await service.recommendedWords(level:'B1');await service.saveWord(today.first['id'] as String);
    now=now.add(const Duration(days:1));final tomorrow=await service.recommendedWords(level:'B1');
    expect(tomorrow.any((w)=>w['id']==today.first['id']),isFalse);expect((await database.db).select('SELECT * FROM builtin_daily_words'),hasLength(2));
    final first=(await service.nextArticle('B1'))!;final questions=first['questions'] as List;
    await service.submit(id:first['id'] as String,token:'read-first',startedAt:now.toIso8601String(),answers:{for(final q in questions)q['id'] as String:(q['choices'] as List)[q['answer'] as int] as String},readConfirmed:true);
    expect((await service.nextArticle('B1'))!['id'],isNot(first['id']));
  });
  test('schema 10 installation upgrades additively with personal reviews unchanged',()async{
    final legacy=AppDatabase.schemaTemplate(10);final path='${directory.path}/legacy.sqlite';
    try{final d=await legacy.db;d.execute("INSERT INTO vocabulary_entries(id,word,normalized_word,definition) VALUES('old','preserve','preserve','Keep my meaning')");d.execute("INSERT INTO vocabulary_reviews(id,entry_id,next_review_at,review_count) VALUES('old-review','old','2030-01-01',9)");await legacy.snapshot(path);}finally{legacy.close();}
    final upgraded=AppDatabase(path:path);try{
      final d=await upgraded.db;expect(d.select('PRAGMA user_version').single['user_version'],11);expect(d.select('SELECT * FROM builtin_article_state'),isEmpty);
      expect((await upgraded.getVocabulary()).single['definition'],'Keep my meaning');expect(d.select('SELECT next_review_at,review_count FROM vocabulary_reviews').single,{'next_review_at':'2030-01-01','review_count':9});expect(d.select('PRAGMA foreign_key_check'),isEmpty);
    }finally{upgraded.close();}
  });
  test('full backup restores built-in bookmarks and evidence without copying content into personal articles',()async{
    final id=catalog.articles.first['id'] as String;await service.bookmark(id,true);await service.saveWord(catalog.words.first['id'] as String);
    final archive=File('${directory.path}/content.lexiflowbackup');final backup=BackupService(database,directory,availableBytes:()async=>1<<34);await backup.create(archive);await backup.restore(archive);
    database.close();database=AppDatabase(path:'${directory.path}/live.sqlite');service=BuiltinContentService(database,catalog:()async=>catalog);
    expect((await service.states()).single['bookmarked'],1);expect(await database.getArticles(),isEmpty);expect(await database.getVocabulary(),hasLength(1));
  });
}
