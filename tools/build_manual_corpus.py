"""Build an offline, source-linked SQLite RAG corpus. Inputs/outputs stay private."""
import argparse
import hashlib
import json
import shutil
import sqlite3
import time
import zipfile
from pathlib import Path

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer


def sha(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--source', required=True, type=Path)
    p.add_argument('--base', required=True, type=Path)
    p.add_argument('--tokenizer', default='models/local/distiluse-int8/tokenizer.json', type=Path)
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    if not a.output.resolve().is_relative_to(Path('private').resolve()):
        raise ValueError('Corpus output must stay private')
    a.output.mkdir(parents=True, exist_ok=True)
    bundle = a.output / 'bundle'
    bundle.mkdir(exist_ok=True)
    manifest = json.loads((a.base / 'manifest.json').read_text())
    for name in ['model.onnx', 'vocab.txt', 'LICENSE.txt']:
        if sha(a.base / name) != manifest['files'][name]['sha256']:
            raise ValueError('Base model hash mismatch')
        shutil.copyfile(a.base / name, bundle / name)
    source = sqlite3.connect(f'file:{a.source.resolve()}?mode=ro', uri=True)
    quality = json.loads((a.source.parent / 'manifest.json').read_text())
    if not quality['complete']:
        raise ValueError('Incomplete PDF intake')
    allowed = {d['id']: d for d in quality['documents']
               if d['kind'] in ['manual', 'catalog'] and not d.get('documentSearchQuarantined', False)}
    stage = a.output / 'corpus.build.sqlite'
    stage.unlink(missing_ok=True)
    db = sqlite3.connect(stage)
    db.executescript('''
      PRAGMA journal_mode=OFF;
      CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL);
      CREATE TABLE documents(id TEXT PRIMARY KEY,file TEXT,sha256 TEXT,kind TEXT,pages INTEGER);
      CREATE TABLE pages(id TEXT PRIMARY KEY,doc_id TEXT,page INTEGER,location TEXT,text TEXT,search_text TEXT);
      CREATE TABLE chunks(id INTEGER PRIMARY KEY,page_id TEXT,char_start INTEGER,char_end INTEGER,vector BLOB);
      CREATE INDEX chunks_page ON chunks(page_id);
    ''')
    for d in allowed.values():
        db.execute('INSERT INTO documents VALUES(?,?,?,?,?)', (d['id'], d['file'], d['sha256'], d['kind'], d['pages']))
    tokenizer = Tokenizer.from_file(str(a.tokenizer))
    tokenizer.no_truncation()
    encoder = Tokenizer.from_file(str(a.tokenizer))
    encoder.enable_truncation(max_length=128)
    encoder.enable_padding(length=128)
    ort.disable_telemetry_events()
    options = ort.SessionOptions()
    options.intra_op_num_threads = 2
    session = ort.InferenceSession(str(bundle / 'model.onnx'), sess_options=options, providers=['CPUExecutionProvider'])
    pending = []
    count = pages = 0
    started = time.monotonic()

    def flush():
        nonlocal count
        if not pending:
            return
        encoded = encoder.encode_batch([t[3] for t in pending])
        vectors = session.run(None, {'input_ids': np.array([e.ids for e in encoded], dtype=np.int64),
                                    'attention_mask': np.array([e.attention_mask for e in encoded], dtype=np.int64)})[0]
        for item, vector in zip(pending, vectors):
            if vector.shape != (512,) or not np.isfinite(vector).all():
                raise ValueError('Invalid embedding')
            db.execute('INSERT INTO chunks(page_id,char_start,char_end,vector) VALUES(?,?,?,?)',
                       (*item[:3], vector.astype('<f4').tobytes()))
            count += 1
        pending.clear()

    for doc_id, page, text, chars in source.execute('SELECT doc_id,page,text,chars FROM pages ORDER BY doc_id,page'):
        if doc_id not in allowed or chars < 40 or page in allowed[doc_id].get('encodingSuspectPages', []):
            continue
        encoded = tokenizer.encode(text, add_special_tokens=False)
        if len(encoded.ids) < 8:
            continue
        page_id = f'{doc_id}-P{page:05}'
        printed = text.splitlines()[0][:80]
        db.execute('INSERT INTO pages VALUES(?,?,?,?,?,?)', (page_id, doc_id, page, f'PDF {page}쪽 · {printed}', text,
                    ''.join(text.lower().split()).replace('_', '').replace('-', '')))
        pages += 1
        for at in range(0, len(encoded.ids), 96):
            end = min(at + 112, len(encoded.ids))
            start_char, end_char = encoded.offsets[at][0], encoded.offsets[end-1][1]
            pending.append((page_id, start_char, end_char, text[start_char:end_char]))
            if len(pending) >= 16:
                flush()
            if end == len(encoded.ids):
                break
        if pages % 250 == 0:
            db.commit()
            print(json.dumps({'pages': pages, 'chunks': count, 'seconds': round(time.monotonic()-started, 1)}), flush=True)
    flush()
    config = manifest['executionConfig']
    model_hash = sha(bundle / 'model.onnx')
    meta = {'version': '2', 'dimension': '512', 'modelSha256': model_hash, 'executionConfig': config,
            'pageCount': str(pages), 'chunkCount': str(count), 'documentCount': str(len(allowed))}
    db.executemany('INSERT INTO metadata VALUES(?,?)', meta.items())
    db.commit()
    assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    db.close()
    shutil.move(stage, bundle / 'corpus.sqlite')
    (bundle / 'index.json').write_text(json.dumps({'version': 2, 'modelId': 'distiluse-int8-v1', 'dimension': 512,
        'modelSha256': model_hash, 'executionConfig': config, 'corpus': 'corpus.sqlite'}))
    (bundle / 'knowledge.json').write_text(json.dumps({'format': 'maintenance-knowledge', 'version': 1,
        'id': 'MANUAL-CORPUS-V2', 'evidence': [], 'knowledge': {'concepts': [], 'skus': [], 'templates': [], 'pending': []}}))
    manifest.update({'version': 2, 'corpus': {**meta, 'excludedDocuments': len(quality['documents'])-len(allowed)},
        'files': {name: {'bytes': (bundle/name).stat().st_size, 'sha256': sha(bundle/name)}
                  for name in ['model.onnx', 'vocab.txt', 'LICENSE.txt', 'index.json', 'knowledge.json', 'corpus.sqlite']}})
    (bundle / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    archive = a.output / 'manual-corpus-v2.building.mrag'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for name in [*manifest['files'], 'manifest.json']:
            z.write(bundle/name, name)
    archive.replace(a.output / 'manual-corpus-v2.mrag')
    print(json.dumps({'status': 'passed', **meta, 'seconds': round(time.monotonic()-started, 1)}), flush=True)


if __name__ == '__main__':
    main()
