"""Validate the bundled library; --partial checks honest in-progress batches."""
import argparse,collections,json,re,sys,unicodedata
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def words(text):return re.findall(r"\b[\w]+(?:['’-][\w]+)*\b",text)
def normalized(text):return ' '.join(unicodedata.normalize('NFKC',text).casefold().split())
def validate(partial=False):
 errors=[]
 def check(ok,msg):
  if not ok:errors.append(msg)
 def read(path):
  try:return json.loads((ROOT/path).read_bytes().decode('utf-8',errors='strict'))
  except (ValueError,OSError) as e:errors.append(f'{path}: {e}');return {}
 manifest=read('assets/content/v1/manifest.json');check(manifest.get('schema_version')==1,'Unsupported manifest schema');check(bool(re.fullmatch(r'\d+\.\d+\.\d+',str(manifest.get('content_version','')))),'Invalid content version')
 vocab=[];articles=[]
 for key,field,out in [('vocabulary_files','entries',vocab),('article_files','articles',articles)]:
  paths=manifest.get(key,[]);check(len(paths)==len(set(paths)),f'Duplicate paths: {key}')
  for path in paths:
   check(bool(re.fullmatch(r'assets/content/v1/[a-z0-9_]+\.json',path)),f'Unsafe path {path}')
   data=read(path);check(data.get('version')==1,f'Bad batch version: {path}');out.extend(data.get(field,[]))
 ids=set();word_set=set()
 for row in vocab:
  key=row.get('id','');check(bool(re.fullmatch(r'v_[a-z0-9]+(?:-[a-z0-9]+)*',key)),f'Invalid word ID: {key}');check(key not in ids,f'Duplicate ID: {key}');ids.add(key)
  for f in ['word','level','part_of_speech','definition','translation','example','collocation','category']:check(isinstance(row.get(f),str) and bool(row[f].strip()),f'{key}: missing {f}')
  name=normalized(row.get('word',''));check(name not in word_set,f'Duplicate word: {name}');word_set.add(name)
  check(row.get('level') in ['B1','B2'],f'{key}: invalid level')
  check(bool(re.search(r'[\u0600-\u06ff]',row.get('translation',''))),f'{key}: missing Dari/Persian script')
  check(len(words(row.get('definition','')))>=3,f'{key}: incomplete definition')
  check(len(words(row.get('example','')))>=6,f'{key}: incomplete example')
  check(bool(re.search(r'\b'+re.escape(row.get('word',''))+r'\b',row.get('example',''),re.I)),f'{key}: example does not teach the exact expression')
 titles=set();article_ids=set();paragraphs={};bodies=set()
 vocabulary={r['id']:r for r in vocab}
 for row in articles:
  key=row.get('id','');check(bool(re.fullmatch(r'a_[a-z0-9]+(?:-[a-z0-9]+)*',key)),f'Invalid article ID: {key}');check(key not in article_ids,f'Duplicate article ID: {key}');article_ids.add(key)
  for f in ['title','body','category','level']:check(isinstance(row.get(f),str) and bool(row[f].strip()),f'{key}: missing {f}')
  title=normalized(row.get('title',''));check(title not in titles,f'Duplicate title: {title}');titles.add(title)
  body=row.get('body','');level=row.get('level');n=len(words(body));low,high=(250,400) if level=='B1' else (350,550);check(level in ['B1','B2'],f'{key}: invalid level');check(low<=n<=high,f'{key}: {n} words; expected {low}–{high}')
  check(row.get('reading_minutes')==__import__('math').ceil(n/180),f'{key}: inaccurate reading time')
  check(normalized(body) not in bodies,f'{key}: duplicate body');bodies.add(normalized(body))
  for paragraph in body.split('\n\n'):
   p=normalized(paragraph)
   if len(words(p))>=30:check(p not in paragraphs,f'{key}: repeated paragraph from {paragraphs.get(p)}');paragraphs[p]=key
  links=row.get('vocabulary',[]);check(6<=len(links)<=8 and len(set(links))==len(links),f'{key}: need 6–8 distinct vocabulary links')
  for link in links:
   check(link in vocabulary,f'{key}: broken word link {link}')
   if link in vocabulary:check(bool(re.search(r'\b'+re.escape(vocabulary[link]['word'])+r'\b',body,re.I)),f'{key}: linked word {link} absent from article')
  qs=row.get('questions',[]);check(len(qs)==4,f'{key}: needs exactly four questions');check({q.get('type') for q in qs}=={'main_idea','detail','inference','vocabulary'},f'{key}: missing question types');check(len({q.get('id') for q in qs})==len(qs),f'{key}: duplicate question IDs')
  for q in qs:
   label=f'{key}/{q.get("id")}';check(bool(re.fullmatch(r'q[1-4]',str(q.get('id','')))),f'{label}: invalid question ID');choices=q.get('choices',[]);check(bool(q.get('prompt')) and bool(q.get('explanation')),f'{label}: incomplete question');check(len(choices)==4 and len(set(choices))==4 and all(isinstance(c,str) and c.strip() for c in choices),f'{label}: need four distinct options');check(type(q.get('answer')) is int and 0<=q['answer']<len(choices),f'{label}: invalid answer reference')
  for ref in row.get('references',[]):check(bool(ref.get('title')) and str(ref.get('url','')).startswith('https://'),f'{key}: malformed background reference')
 for row in vocab+articles:check(not re.search(r'\b(?:TODO|TBD|placeholder|lorem ipsum)\b',json.dumps(row),re.I),f'{row.get("id")}: placeholder content')
 levels=collections.Counter(r.get('level') for r in vocab);article_levels=collections.Counter(r.get('level') for r in articles)
 if not partial:
  check(len(vocab)==1000,f'Expected 1,000 vocabulary entries; found {len(vocab)}');check(levels=={'B1':500,'B2':500},f'Vocabulary distribution: {dict(levels)}');check(len(articles)==100,f'Expected 100 articles; found {len(articles)}');check(article_levels=={'B1':50,'B2':50},f'Article distribution: {dict(article_levels)}')
 report=dict(mode='partial' if partial else 'complete',vocabulary=len(vocab),vocabulary_levels=dict(levels),articles=len(articles),article_levels=dict(article_levels),questions=sum(len(r.get('questions',[])) for r in articles),errors=errors)
 print(json.dumps(report,ensure_ascii=False,indent=2));return len(errors)==0
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--partial',action='store_true');a=p.parse_args();sys.exit(0 if validate(a.partial) else 1)
