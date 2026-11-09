"""Offline PDF intake. All source-derived data stays in private/, never in assets."""
import argparse
import hashlib
import json
import logging
import re
import sqlite3
from pathlib import Path

import pdfplumber
import pypdfium2 as pdfium


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--inputs', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    out = args.output.resolve()
    if not out.is_relative_to(Path('private').resolve()):
        raise ValueError('Source-derived data must remain under private/')
    out.mkdir(parents=True, exist_ok=True)
    logging.disable(logging.WARNING)
    specs = json.loads(args.inputs.read_text())
    if not specs or any(not re.fullmatch(r'[A-Za-z0-9_-]{1,80}', s['id']) or
                        s['kind'] not in ['operations', 'maintenance_records', 'manual', 'catalog'] for s in specs):
        raise ValueError('Invalid document IDs or source categories')
    if len({s['id'] for s in specs}) != len(specs):
        raise ValueError('Duplicate document IDs')
    (out / 'manifest.json').write_text(json.dumps({'complete': False, 'status': 'extracting'}))
    db = sqlite3.connect(out / 'pages.sqlite')
    db.executescript('''
      CREATE TABLE IF NOT EXISTS documents(id TEXT PRIMARY KEY, file TEXT, kind TEXT, sha256 TEXT, pages INTEGER);
      CREATE TABLE IF NOT EXISTS pages(doc_id TEXT, page INTEGER, text TEXT, hangul INTEGER, chars INTEGER,
        PRIMARY KEY(doc_id,page));
      CREATE VIRTUAL TABLE IF NOT EXISTS page_search USING fts5(doc_id UNINDEXED,page UNINDEXED,text,tokenize='trigram');
    ''')
    reports = []
    for spec in specs:
        path = Path(spec['path'])
        with path.open('rb') as f:
            sha = hashlib.file_digest(f, 'sha256').hexdigest()
        doc = pdfium.PdfDocument(str(path))
        counts = {'id': spec['id'], 'file': path.name, 'kind': spec['kind'],
                  'sha256': sha, 'bytes': path.stat().st_size, 'pages': len(doc),
                  'emptyPages': [], 'sparsePages': [], 'encodingSuspectPages': [],
                  'hangulPages': 0, 'characters': 0}
        # A complete document is replaced atomically; interrupted extraction can be rerun.
        with db:
            db.execute('DELETE FROM pages WHERE doc_id=?', (spec['id'],))
            db.execute('DELETE FROM page_search WHERE doc_id=?', (spec['id'],))
            for i in range(len(doc)):
                page = doc[i]
                tp = page.get_textpage()
                text = tp.get_text_bounded().replace('\r\n', '\n').replace('\r', '\n')
                tp.close()
                page.close()
                hangul = sum('\uac00' <= c <= '\ud7a3' for c in text)
                chars = len(text.strip())
                # Missing ToUnicode maps can turn Korean into unrelated CJK symbols.
                # Quarantine suspicious pages; never guess a character substitution.
                unusual = sum('\u2e80' <= c <= '\ua4cf' for c in text)
                suspect = hangul == 0 and unusual >= 4 and unusual / max(chars, 1) > .08
                if suspect:
                    counts['encodingSuspectPages'].append(i + 1)
                counts['characters'] += chars
                counts['hangulPages'] += hangul > 0
                if not chars:
                    counts['emptyPages'].append(i + 1)
                elif chars < 80:
                    counts['sparsePages'].append(i + 1)
                db.execute('INSERT INTO pages VALUES(?,?,?,?,?)', (spec['id'], i+1, text, hangul, chars))
                # Operational identifiers/history are never treated as manual instructions.
                if spec['kind'] in ['manual', 'catalog'] and chars and not suspect:
                    db.execute('INSERT INTO page_search VALUES(?,?,?)', (spec['id'], i+1, text))
            counts['documentSearchQuarantined'] = len(counts['encodingSuspectPages']) > len(doc) * .2
            if counts['documentSearchQuarantined']:
                db.execute('DELETE FROM page_search WHERE doc_id=?', (spec['id'],))
            db.execute('INSERT OR REPLACE INTO documents VALUES(?,?,?,?,?)',
                       (spec['id'], path.name, spec['kind'], sha, len(doc)))
        doc.close()
        if spec['kind'] in ['operations', 'maintenance_records']:
            tables = []
            with pdfplumber.open(path) as pdf:
                for i, page in enumerate(pdf.pages, 1):
                    tables.append({'page': i, 'tables': page.extract_tables()})
            (out / f"{spec['id']}-tables.json").write_text(json.dumps(tables, ensure_ascii=False))
            counts['tables'] = sum(len(t['tables']) for t in tables)
        reports.append(counts)
        (out / 'manifest.json').write_text(json.dumps({'complete': len(reports) == len(specs),
            'extractor': 'pdfium-bounded-text; original page numbering is 1-based',
            'ocrPerformed': False, 'tableSemanticsVerified': False, 'documents': reports},
            ensure_ascii=False, indent=2))
        print(json.dumps({k: counts[k] for k in ['id', 'pages', 'hangulPages', 'characters']}, ensure_ascii=False), flush=True)
    assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    db.close()


if __name__ == '__main__':
    main()
