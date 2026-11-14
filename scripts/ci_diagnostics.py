"""Publish bounded, credential-free build diagnostics for restricted clients."""
import argparse
import base64
import json
import lzma
from pathlib import Path


def annotation(title, message):
    title = title.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A').replace(',', '%2C').replace(':', '%3A')
    safe = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print(f'::warning title={title}::{safe}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--format-chunks')
    parser.add_argument('--tests')
    parser.add_argument('--log')
    args = parser.parse_args()
    if args.log:
        data = Path(args.log).read_bytes()
        if args.log.endswith('tests.log'):
            events = []
            for line in data.decode(errors='replace').splitlines():
                try:
                    decoded = json.loads(line)
                except ValueError:
                    continue
                events.extend(e for e in (decoded if isinstance(decoded, list) else [decoded]) if isinstance(e, dict))
            failed = {e.get('testID') for e in events if e.get('type') == 'error'}
            events = [e for e in events if e.get('testID') in failed or (e.get('type') == 'testStart' and e.get('test', {}).get('id') in failed)]
            data = '\n'.join(json.dumps(e, ensure_ascii=False) for e in events).encode('utf-8')
        encoded = base64.b64encode(lzma.compress(data)).decode('ascii')
        chunks = [encoded[i:i + 3000] for i in range(0, len(encoded), 3000)]
        for i, chunk in enumerate(chunks[:10]):
            annotation(f'CI log {args.log} {i + 1:03} of {len(chunks):03}', chunk)
        return
    if args.format_chunks:
        path = Path('format.patch')
        if not path.is_file() or not path.stat().st_size:
            return
        encoded = base64.b64encode(lzma.compress(path.read_bytes())).decode('ascii')
        chunks = [encoded[i:i + 3000] for i in range(0, len(encoded), 3000)]
        start, end = map(int, args.format_chunks.split(':'))
        for i in range(start, min(end, len(chunks))):
            annotation(f'Dart format patch {i + 1:03} of {len(chunks):03}', chunks[i])
        return
    finished = set()
    names, failures, printed, counts = {}, {}, {}, {'success': 0, 'failure': 0, 'skipped': 0}
    for line in Path(args.tests).read_text(errors='replace').splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        # Flutter also emits daemon-protocol arrays around Dart test events.
        for item in event if isinstance(event, list) else [event]:
            if not isinstance(item, dict):
                continue
            if item.get('type') == 'testStart':
                test = item.get('test', {})
                names[test.get('id')] = test.get('name', 'Unnamed test')
            elif item.get('type') == 'error':
                failures.setdefault(item.get('testID'), []).append(item)
            elif item.get('type') == 'print':
                printed.setdefault(item.get('testID'), []).append(str(item.get('message', '')))
            elif item.get('type') == 'testDone' and not item.get('hidden', False):
                finished.add(item.get('testID'))
                key = 'skipped' if item.get('skipped') else item.get('result', '')
                if key == 'error':
                    key = 'failure'
                if key in counts:
                    counts[key] += 1
    pending = [name for i, name in names.items() if i not in finished and not name.startswith('loading ')]
    annotation(f'Test results {args.tests}', json.dumps(counts) + ('\nStill running: ' + '; '.join(pending) if pending else '') + '\n' + '\n'.join(names.get(i, str(i)) for i in failures))
    for i, events in list(failures.items())[:9]:
        output = '\n'.join(printed.get(i, []))
        marker = output.find('EXCEPTION CAUGHT')
        if marker >= 0:
            output = output[marker:]
        detail = output[:2300] + '\n' + '\n'.join(str(e.get('error', ''))[:400] + '\n' + str(e.get('stackTrace', ''))[:300] for e in events)
        annotation(f'Test failure {names.get(i, i)}', detail[:3000])


if __name__ == '__main__':
    main()
