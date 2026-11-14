"""Authoring helpers: serialize individually written content; never invent text."""
import json,re,math
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]/'assets/content/v1'
def slug(text):return re.sub(r'[^a-z0-9]+','-',text.lower()).strip('-')
def vocabulary(level,topic,batch,text):
 rows=[]
 for line in text.strip().splitlines():
  fields=line.split('|')
  if len(fields)!=6:raise ValueError(line)
  word,pos,definition,translation,example,collocation=[f.strip() for f in fields]
  rows.append(dict(id='v_'+slug(word),word=word,level=level,part_of_speech=pos,definition=definition,translation=translation,example=example,collocation=collocation,category=topic))
 path=ROOT/f'vocabulary_{level.lower()}_{batch:02}.json'
 path.write_text(json.dumps(dict(version=1,entries=rows),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 refresh()
 return rows
def article(level,category,title,body,words,questions,references=None):
 return dict(id='a_'+slug(title),title=title,level=level,category=category,reading_minutes=math.ceil(len(re.findall(r"\b[\w]+(?:['’-][\w]+)*\b",body))/180),body=body.strip(),vocabulary=['v_'+slug(w) for w in words],questions=[dict(id=f'q{i+1}',type=q[0],prompt=q[1],choices=q[2].split('|'),answer=q[3],explanation=q[4]) for i,q in enumerate(questions)],references=references or [])
def articles(level,batch,rows):
 path=ROOT/f'articles_{level.lower()}_{batch:02}.json'
 path.write_text(json.dumps(dict(version=1,articles=rows),ensure_ascii=False,indent=2)+'\n',encoding='utf-8');refresh()
def refresh():
 manifest=dict(schema_version=1,content_version='1.0.0',level_note='B1/B2 are curriculum targets, not officially validated word-level CEFR classifications.',vocabulary_files=['assets/content/v1/'+p.name for p in sorted(ROOT.glob('vocabulary_*.json'))],article_files=['assets/content/v1/'+p.name for p in sorted(ROOT.glob('articles_*.json'))])
 (ROOT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':refresh()
