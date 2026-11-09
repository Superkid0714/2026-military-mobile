"""Extend the private corpus to all seven manuals, retaining original vectors."""
import argparse
import concurrent.futures
import hashlib
import json
import re
import shutil
import sqlite3
import time
import zipfile
from pathlib import Path

import numpy as np
import onnxruntime as ort
from tokenizers import Tokenizer
from build_manual_page_images import render_document, sha


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--base',required=True,type=Path)
    p.add_argument('--intake',required=True,type=Path)
    p.add_argument('--inputs',required=True,type=Path)
    p.add_argument('--ocr',required=True,type=Path)
    p.add_argument('--output',required=True,type=Path)
    p.add_argument('--tokenizer',type=Path,default=Path('models/local/distiluse-int8/tokenizer.json'))
    a=p.parse_args()
    if not a.output.resolve().is_relative_to(Path('private').resolve()):raise ValueError('Private output required')
    a.output.mkdir(parents=True,exist_ok=True)
    stage=a.output/'bundle.building';stage.mkdir(exist_ok=False)
    previews=a.output/'new-previews';previews.mkdir(exist_ok=True)
    m=json.loads((a.base/'manifest.json').read_text())
    for name,spec in m['files'].items():
        if sha(a.base/name)!=spec['sha256']:raise ValueError('Base integrity mismatch')
        shutil.copyfile(a.base/name,stage/name)
    db=sqlite3.connect(stage/'corpus.sqlite')
    raw=sqlite3.connect(f'file:{a.intake.resolve()}?mode=ro',uri=True)
    specs={s['id']:s for s in json.loads(a.inputs.read_text())}
    documents=raw.execute("SELECT id,file,kind,sha256,pages FROM documents WHERE kind IN ('manual','catalog') ORDER BY id").fetchall()
    if len(documents)!=7 or any(d[0] in ['D01','D02'] for d in documents):raise ValueError('Exactly seven manuals; exclude operations/history')
    for doc_id,file,kind,source_sha,pages in documents:
        if sha(specs[doc_id]['path'])!=source_sha:raise ValueError('Changed original PDF')
        db.execute('INSERT OR IGNORE INTO documents VALUES(?,?,?,?,?)',(doc_id,file,source_sha,kind,pages))
    recovered={r['page']:r for r in (json.loads(line) for line in a.ocr.read_text().splitlines())}
    ocr_report=json.loads((a.ocr.parent/'report.json').read_text())
    wire=next(d for d in documents if d[0]=='D07')
    if ocr_report['sourceSha256']!=wire[3] or len(recovered)!=wire[4]:raise ValueError('OCR/source mismatch')
    db.execute("ALTER TABLE pages ADD COLUMN text_method TEXT NOT NULL DEFAULT 'pdf'")
    db.execute('ALTER TABLE pages ADD COLUMN ocr_confidence REAL')
    encoder=Tokenizer.from_file(str(a.tokenizer));encoder.enable_truncation(max_length=128);encoder.enable_padding(length=128)
    splitter=Tokenizer.from_file(str(a.tokenizer));splitter.no_truncation()
    ort.disable_telemetry_events();options=ort.SessionOptions();options.intra_op_num_threads=2
    session=ort.InferenceSession(str(stage/'model.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
    pending=[];new_chunks=0;searchable_ocr=0
    def flush():
        nonlocal new_chunks
        if not pending:return
        encoded=encoder.encode_batch([r[3] for r in pending]);vectors=session.run(None,{'input_ids':np.array([x.ids for x in encoded],dtype=np.int64),'attention_mask':np.array([x.attention_mask for x in encoded],dtype=np.int64)})[0]
        for row,vector in zip(pending,vectors):
            if vector.shape!=(512,) or not np.isfinite(vector).all():raise ValueError('Invalid vector')
            db.execute('INSERT INTO chunks(page_id,char_start,char_end,vector) VALUES(?,?,?,?)',(*row[:3],vector.astype('<f4').tobytes()));new_chunks+=1
        pending.clear()
    for doc_id,file,kind,source_sha,pages in documents:
        for number in range(1,pages+1):
            page_id=f'{doc_id}-P{number:05}'
            if db.execute('SELECT 1 FROM pages WHERE id=?',(page_id,)).fetchone():continue
            if doc_id=='D07':
                row=recovered[number]
                # Use OCR for finding a diagram, not as verified pin/color values.
                lines=[line for line in row['lines'] if line['confidence']>=.45 and
                       (re.search(r'[가-힣]',line['text']) or re.search(r'[A-Za-z]{2}|(?=[A-Za-z0-9]*[A-Za-z])(?=[A-Za-z0-9]*[0-9])[A-Za-z0-9]{3,}',line['text'])) and
                       line['text'].replace(' ','') not in ['변경근거','적용근거','적용차대번호']]
                text='\n'.join(line['text'] for line in lines)
                confidence=sum(line['confidence'] for line in lines)/len(lines) if lines else 0
                index=''.join(text.lower().split()).replace('_','').replace('-','') if len(text)>=8 else ''
                if index:searchable_ocr+=1
                method='ocr'
            else:
                text=raw.execute('SELECT text FROM pages WHERE doc_id=? AND page=?',(doc_id,number)).fetchone()[0]
                index='';method='pdf';confidence=None
            printed=text.splitlines()[0][:80] if text.strip() else '원본 페이지'
            db.execute('INSERT INTO pages VALUES(?,?,?,?,?,?,?,?)',(page_id,doc_id,number,f'PDF {number}쪽 · {printed}',text,index,method,confidence))
            if doc_id=='D07' and index:
                tokens=splitter.encode(text,add_special_tokens=False)
                for at in range(0,len(tokens.ids),96):
                    end=min(at+112,len(tokens.ids));start_char,end_char=tokens.offsets[at][0],tokens.offsets[end-1][1]
                    pending.append((page_id,start_char,end_char,text[start_char:end_char]))
                    if len(pending)>=16:flush()
                    if end==len(tokens.ids):break
        db.commit()
    flush();db.commit()
    jobs=[]
    for doc_id,file,kind,source_sha,pages in documents:
        missing=db.execute('SELECT p.id,p.page FROM pages p LEFT JOIN page_images i ON i.page_id=p.id WHERE p.doc_id=? AND i.page_id IS NULL ORDER BY p.page',(doc_id,)).fetchall()
        if missing:jobs.append((doc_id,specs[doc_id]['path'],missing,str(previews),1600,70))
    with concurrent.futures.ProcessPoolExecutor(max_workers=4) as pool:
        for future in concurrent.futures.as_completed([pool.submit(render_document,j) for j in jobs]):
            doc_id,rows=future.result()
            with db:
                for page_id,width,height,size in rows:
                    db.execute('INSERT INTO page_images VALUES(?,?,?,?)',(page_id,width,height,(previews/f'{page_id}.jpg').read_bytes()))
            print(json.dumps({'renderedDocument':doc_id,'addedImages':len(rows)}),flush=True)
    count=db.execute('SELECT count(*) FROM pages').fetchone()[0];images=db.execute('SELECT count(*) FROM page_images').fetchone()[0];chunks=db.execute('SELECT count(*) FROM chunks').fetchone()[0];searchable=db.execute("SELECT count(*) FROM pages WHERE search_text!=''").fetchone()[0]
    if count!=5728 or images!=count:raise ValueError('Incomplete manual coverage')
    meta={'pageCount':str(count),'chunkCount':str(chunks),'documentCount':'7','imagePageCount':str(images),'searchablePageCount':str(searchable),'ocrDocument':'D07','ocrSearchablePages':str(searchable_ocr),'sourcePolicy':'manuals-only-excluding-D01-D02'}
    db.executemany('INSERT OR REPLACE INTO metadata VALUES(?,?)',meta.items());db.commit()
    if db.execute('PRAGMA integrity_check').fetchone()[0]!='ok' or db.execute('PRAGMA foreign_key_check').fetchall():raise ValueError('Corpus integrity failed')
    db.close();raw.close()
    if (stage/'corpus.sqlite').stat().st_size>1024*1024*1024:raise ValueError('Corpus budget exceeded')
    m['corpus'].update(meta);m['corpus']['excludedDocuments']=2;m['files']['corpus.sqlite']={'bytes':(stage/'corpus.sqlite').stat().st_size,'sha256':sha(stage/'corpus.sqlite')}
    (stage/'manifest.json').write_text(json.dumps(m,indent=2))
    archive=a.output/'all-seven-manuals.building.mrag'
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=3) as z:
        for name in [*m['files'],'manifest.json']:z.write(stage/name,name)
    stage.rename(a.output/'bundle');archive.rename(a.output/'all-seven-manuals.mrag')
    report={'status':'passed',**meta,'newChunks':new_chunks,'ocrEngine':ocr_report['engine'],'manuals':[d[0] for d in documents]};(a.output/'build-report.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)


if __name__=='__main__':main()
