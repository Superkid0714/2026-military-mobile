"""Offline recovery of malformed PDF text with a local Apple Vision executable."""
import argparse
import concurrent.futures
import hashlib
import json
import subprocess
import time
from pathlib import Path


def main():
    import pypdfium2 as pdfium
    p = argparse.ArgumentParser()
    p.add_argument('--pdf', required=True, type=Path)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--ocr', required=True, type=Path)
    p.add_argument('--workers', type=int, default=3)
    a = p.parse_args()
    if not a.output.resolve().is_relative_to(Path('private').resolve()) or not 1 <= a.workers <= 3:
        raise ValueError('Use a private output and at most 3 OCR workers')
    a.output.mkdir(parents=True, exist_ok=True)
    images = a.output/'pages'
    images.mkdir(exist_ok=True)
    doc = pdfium.PdfDocument(str(a.pdf))
    results = {}
    jobs = []
    started = time.monotonic()
    for at in range(len(doc)):
        page = doc[at]
        width, height = page.get_size()
        thumb = page.render(scale=600/max(width,height))
        gray = thumb.to_pil().convert('L')
        dark = sum(gray.histogram()[:220])
        gray.close(); thumb.close()
        if dark < 8:
            results[at+1] = {'page':at+1,'text':'','lines':[],'blank':True}
        else:
            target = images/f'{at+1:04}.png'
            bitmap = page.render(scale=2400/max(width,height))
            image = bitmap.to_pil()
            image.save(target)
            image.close(); bitmap.close()
            jobs.append({'page':at+1,'path':str(target.resolve())})
        page.close()
        if (at+1)%100==0:
            print(json.dumps({'rendered':at+1,'ocrPending':len(jobs),'blank':len(results)}),flush=True)
    doc.close()
    def run(shard):
        spec=a.output/f'input-{shard}.json';output=a.output/f'output-{shard}.jsonl'
        spec.write_text(json.dumps(jobs[shard::a.workers]))
        with (a.output/f'worker-{shard}.log').open('w') as log:
            subprocess.run([str(a.ocr),str(spec),str(output)],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=3600)
        return output
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as pool:
        for future in concurrent.futures.as_completed([pool.submit(run,i) for i in range(a.workers)]):
            for line in future.result().read_text().splitlines():
                row=json.loads(line)
                if row['page'] in results: raise ValueError('Duplicate OCR page')
                results[row['page']]=row
            print(json.dumps({'ocrCompleted':sum(not r.get('blank',False) for r in results.values()),'blank':sum(r.get('blank',False) for r in results.values()),'seconds':round(time.monotonic()-started,1)}),flush=True)
    if sorted(results)!=list(range(1,len(results)+1)) or len(results)!=len(jobs)+sum(r.get('blank',False) for r in results.values()):
        raise ValueError('Incomplete OCR')
    output=a.output/'recovered.jsonl'
    output.write_text(''.join(json.dumps(results[n],ensure_ascii=False)+'\n' for n in sorted(results)))
    with a.pdf.open('rb') as f:source_sha=hashlib.file_digest(f,'sha256').hexdigest()
    report={'status':'passed','sourceSha256':source_sha,'pages':len(results),'blankPages':sum(r.get('blank',False) for r in results.values()),'ocrPages':len(jobs),'hangulPages':sum(any('가'<=c<='힣' for c in r['text']) for r in results.values()),'seconds':round(time.monotonic()-started,1),'engine':'Apple Vision accurate ko-KR/en-US; no language correction'}
    (a.output/'report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)


if __name__=='__main__':main()
