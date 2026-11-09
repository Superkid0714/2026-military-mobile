"""Attach source-verified, offline page previews to an existing private RAG bundle."""
import argparse
import concurrent.futures
import hashlib
import json
import shutil
import sqlite3
import time
import zipfile
from pathlib import Path


def sha(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def render_document(job):
    # PDFium documents stay within one worker process; no unsafe shared handles.
    import pypdfium2 as pdfium
    doc_id, path, pages, folder, edge, quality = job
    out = Path(folder)
    doc = pdfium.PdfDocument(path)
    results = []
    for page_id, number in pages:
        page = doc[number - 1]
        width, height = page.get_size()
        bitmap = page.render(scale=edge / max(width, height))
        image = bitmap.to_pil().convert('RGB')
        target = out / f'{page_id}.jpg'
        image.save(target, format='JPEG', quality=quality, optimize=True)
        if target.stat().st_size > 2 * 1024 * 1024:
            raise ValueError('Page preview too large')
        results.append((page_id, image.width, image.height, target.stat().st_size))
        image.close()
        bitmap.close()
        page.close()
    doc.close()
    return doc_id, results


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--base', required=True, type=Path)
    p.add_argument('--inputs', required=True, type=Path)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--workers', type=int, default=4)
    p.add_argument('--long-edge', type=int, default=1600)
    p.add_argument('--quality', type=int, default=70)
    a = p.parse_args()
    if not a.output.resolve().is_relative_to(Path('private').resolve()):
        raise ValueError('Source-derived output must stay private')
    if not 1 <= a.workers <= 4 or not 1200 <= a.long_edge <= 1800 or not 60 <= a.quality <= 85:
        raise ValueError('Invalid rendering budget')
    a.output.mkdir(parents=True, exist_ok=True)
    stage = a.output / 'bundle.building'
    stage.mkdir(exist_ok=False)
    previews = a.output / 'previews'
    previews.mkdir(exist_ok=True)
    manifest = json.loads((a.base / 'manifest.json').read_text())
    if manifest['version'] != 2:
        raise ValueError('A full version-2 corpus is required')
    for name, spec in manifest['files'].items():
        if sha(a.base / name) != spec['sha256']:
            raise ValueError(f'Base integrity mismatch: {name}')
        shutil.copyfile(a.base / name, stage / name)
    db = sqlite3.connect(stage / 'corpus.sqlite')
    db.execute('CREATE TABLE page_images(page_id TEXT PRIMARY KEY REFERENCES pages(id), width INTEGER NOT NULL, height INTEGER NOT NULL, jpeg BLOB NOT NULL)')
    inputs = {s['id']: s for s in json.loads(a.inputs.read_text())}
    jobs = []
    for doc_id, source_sha in db.execute('SELECT id,sha256 FROM documents ORDER BY id'):
        source = Path(inputs[doc_id]['path'])
        if sha(source) != source_sha:
            raise ValueError(f'Source document changed: {doc_id}')
        pages = db.execute('SELECT id,page FROM pages WHERE doc_id=? ORDER BY page', (doc_id,)).fetchall()
        jobs.append((doc_id, str(source), pages, str(previews), a.long_edge, a.quality))
    count = total = 0
    started = time.monotonic()
    with concurrent.futures.ProcessPoolExecutor(max_workers=a.workers) as pool:
        pending = [pool.submit(render_document, job) for job in jobs]
        for future in concurrent.futures.as_completed(pending):
            doc_id, rows = future.result()
            with db:
                for page_id, width, height, size in rows:
                    file = previews / f'{page_id}.jpg'
                    db.execute('INSERT INTO page_images VALUES(?,?,?,?)', (page_id, width, height, file.read_bytes()))
                    count += 1
                    total += size
            print(json.dumps({'document': doc_id, 'imagePages': count, 'imageMiB': round(total / 1024**2, 1), 'seconds': round(time.monotonic()-started, 1)}), flush=True)
    expected = db.execute('SELECT count(*) FROM pages').fetchone()[0]
    if count != expected:
        raise ValueError('Incomplete image coverage')
    db.executemany('INSERT INTO metadata VALUES(?,?)', [('imageFormat', 'jpeg-pages-v1'), ('imagePageCount', str(count)), ('imageLongEdge', str(a.long_edge))])
    db.commit()
    if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok' or db.execute('PRAGMA foreign_key_check').fetchall():
        raise ValueError('Image corpus integrity failure')
    db.close()
    if (stage / 'corpus.sqlite').stat().st_size > 1024 * 1024 * 1024:
        raise ValueError('Image corpus exceeds supported budget')
    manifest['corpus'].update({'imageFormat': 'jpeg-pages-v1', 'imagePageCount': str(count), 'imageLongEdge': str(a.long_edge)})
    manifest['files']['corpus.sqlite'] = {'bytes': (stage/'corpus.sqlite').stat().st_size, 'sha256': sha(stage/'corpus.sqlite')}
    (stage/'manifest.json').write_text(json.dumps(manifest, indent=2))
    building = a.output/'manual-corpus-images.building.mrag'
    with zipfile.ZipFile(building, 'w', zipfile.ZIP_DEFLATED, compresslevel=3) as z:
        for name in [*manifest['files'], 'manifest.json']:
            z.write(stage/name, name)
    if building.stat().st_size > 1280 * 1024 * 1024:
        raise ValueError('Bundle too large')
    stage.rename(a.output/'bundle')
    building.rename(a.output/'manual-corpus-images.mrag')
    (a.output/'image-build-report.json').write_text(json.dumps({'status':'passed','pages':count,'imageBytes':total,'seconds':round(time.monotonic()-started,1)},indent=2))
    print(json.dumps({'status': 'passed', 'imagePages': count, 'seconds': round(time.monotonic()-started, 1)}), flush=True)


if __name__ == '__main__':
    main()
