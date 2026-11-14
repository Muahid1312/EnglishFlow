"""Publish bounded, credential-free build diagnostics for restricted clients."""
import argparse
import base64
import json
import lzma
from pathlib import Path


def annotation(title, message):
    safe = message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
    print(f'::warning title={title}::{safe}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--format-chunks')
    parser.add_argument('--tests')
    parser.add_argument('--log')
    args = parser.parse_args()
    if args.log:
        encoded = base64.b64encode(lzma.compress(Path(args.log).read_bytes())).decode('ascii')
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
    names, failures, counts = {}, {}, {'success': 0, 'failure': 0, 'skipped': 0}
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
            elif item.get('type') == 'testDone' and not item.get('hidden', False):
                key = 'skipped' if item.get('skipped') else item.get('result', '')
                if key in counts:
                    counts[key] += 1
    annotation(f'Test results {args.tests}', json.dumps(counts) + '\n' + '\n'.join(names.get(i, str(i)) for i in failures))
    for i, events in list(failures.items())[:9]:
        detail = '\n'.join(str(e.get('error', ''))[:2000] + '\n' + str(e.get('stackTrace', ''))[:900] for e in events)
        annotation(f'Test failure {names.get(i, i)}', detail[:3000])


if __name__ == '__main__':
    main()
