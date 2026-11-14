"""Verify that the actual APK includes the entire validated offline catalogue."""
import json
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as apk:
    def read(path):
        return json.loads(apk.read('assets/flutter_assets/' + path).decode('utf-8'))
    manifest = read('assets/content/v1/manifest.json')
    vocabulary = [row for path in manifest['vocabulary_files'] for row in read(path)['entries']]
    articles = [row for path in manifest['article_files'] for row in read(path)['articles']]
    for rows, total, per_level in [(vocabulary, 1000, 500), (articles, 100, 50)]:
        assert len(rows) == total, 'Incomplete content in actual APK'
        assert len({row['id'] for row in rows}) == total, 'Duplicate content in APK'
        for level in ['B1', 'B2']:
            assert sum(row['level'] == level for row in rows) == per_level
    assert sum(len(row['questions']) for row in articles) == 400
    print(json.dumps({'content_version': manifest['content_version'], 'vocabulary': len(vocabulary), 'articles': len(articles), 'questions': 400, 'offline_assets_verified': True}, indent=2))
