"""Verify published first-party audio, catalogue rights, metadata and real codecs."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
from urllib.request import Request,urlopen
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--remote',action='store_true');args=p.parse_args()
data=json.loads((ROOT/'assets/listening/catalog_v1.json').read_text(encoding='utf-8'))
assert data['version']==1 and len(data['lessons'])==4
seen=set()
for row in data['lessons']:
 assert row['id'] not in seen;seen.add(row['id'])
 assert row['download_allowed'] is True and row['level'] in ['B1','B2']
 assert 'synthetic' in row['speaker'] and row['provider']=='LexiFlow originals'
 assert re.fullmatch(r'https://raw\.githubusercontent\.com/Muahid1312/EnglishFlow/[a-f0-9]{40}/listening_catalog/media/[a-z0-9-]+\.mp3',row['audio_url'])
 path=ROOT/'listening_catalog/media'/row['file'];content=path.read_bytes()
 assert len(content)==row['bytes'] and hashlib.sha256(content).hexdigest()==row['sha256']
 duration=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=noprint_wrappers=1:nokey=1',str(path)]))
 assert abs(round(duration*1000)-row['duration_ms'])<=1
 subprocess.run(['ffmpeg','-nostdin','-v','error','-i',str(path),'-f','null','-'],check=True)
 for question in row['questions']:assert question['answer'] in question['choices'] and len(set(question['choices']))==3
 if args.remote:
  response=urlopen(row['audio_url'],timeout=30);remote=response.read();assert len(remote)==row['bytes'] and hashlib.sha256(remote).hexdigest()==row['sha256']
  partial=urlopen(Request(row['audio_url'],headers={'Range':'bytes=0-1023','Accept-Encoding':'identity'}),timeout=30)
  assert partial.status==206 and partial.headers['Content-Range']==f"bytes 0-1023/{row['bytes']}" and partial.read()==content[:1024]
print(json.dumps({'original_lessons':len(seen),'bytes':sum(r['bytes'] for r in data['lessons']),'sha256_and_decode':'passed','remote_https_and_ranges':'passed' if args.remote else 'not_run','third_party_downloads':0},indent=2))
