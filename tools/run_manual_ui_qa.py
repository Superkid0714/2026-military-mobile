"""Exercise the ordinary Android RAG screen and restore the display setting."""
import argparse
import json
import subprocess
import uuid
from pathlib import Path


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--adb', required=True)
    p.add_argument('--serial', required=True)
    p.add_argument('--output', required=True, type=Path)
    p.add_argument('--mode', choices=['manual','analysis','chat','chat-images','books','onboarding','dashboard'], default='manual')
    p.add_argument('--offline', action='store_true')
    a = p.parse_args()
    out = a.output.resolve()
    if not out.is_relative_to(Path('private').resolve()):
        raise ValueError('UI results must stay private')
    out.mkdir(parents=True, exist_ok=True)
    package = 'com.superkid.military.military_maintenance'
    def adb(*words, timeout=30):
        return subprocess.run([a.adb, '-s', a.serial, *words], capture_output=True, check=True, timeout=timeout).stdout
    before = adb('shell', 'settings', 'get', 'global', 'stay_on_while_plugged_in').decode().strip()
    if before not in ['0', '1', '2', '3', '4', '5', '6', '7']:
        raise ValueError('Unknown display setting')
    network = None
    if a.offline:
        network = {k: adb('shell', 'settings', 'get', 'global', k).decode().strip()
                   for k in ['airplane_mode_on', 'wifi_on', 'mobile_data']}
        if not all(v in ['0', '1'] for v in network.values()):
            raise ValueError('Unknown network setting')
        (out/'network-before.json').write_text(json.dumps(network))
    run_id = uuid.uuid4().hex
    try:
        if network is not None:
            adb('shell', 'cmd', 'connectivity', 'airplane-mode', 'enable')
            adb('shell', 'svc', 'wifi', 'disable')
            adb('shell', 'svc', 'data', 'disable')
            (out/'offline-routes.txt').write_bytes(adb('shell', 'ip', 'route', 'show', 'table', 'all'))
        adb('shell', 'svc', 'power', 'stayon', 'usb')
        adb('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
        log = adb('shell', 'am', 'instrument', '-w', '-e', 'qaRunId', run_id, '-e', 'mode', a.mode,
                  f'{package}.test/{package}.ManualUiInstrumentation', timeout=300)
        (out/'instrumentation.log').write_bytes(log)
        report = json.loads(adb('exec-out', 'run-as', package, 'cat', 'files/manual-ui-result.json'))
        if report.get('qaRunId') != run_id:
            raise RuntimeError('Stale UI result')
        (out/'result.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))
        if report['status'] == 'passed' or report.get('windowPackage') == package:
            (out/'source-dialog.png').write_bytes(adb('exec-out', 'run-as', package, 'cat', 'files/manual-ui-source.png'))
        if report['status']=='passed' and a.mode in ['analysis','chat','chat-images']:
            (out/('chat-reply.png' if a.mode in ['chat','chat-images'] else 'ai-history.png')).write_bytes(adb('exec-out', 'run-as', package, 'cat', 'files/manual-ui-ml.png'))
        if report.get('mascotLoadingVisible'):
            for filename in ['manual-ui-loading.png','manual-ui-loading-next.png']:
                (out/filename).write_bytes(adb('exec-out', 'run-as', package, 'cat', 'files/'+filename))
    finally:
        adb('shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', before)
        after = adb('shell', 'settings', 'get', 'global', 'stay_on_while_plugged_in').decode().strip()
        (out/'display-settings.json').write_text(json.dumps({'before': before, 'after': after}))
        if network is not None:
            adb('shell', 'cmd', 'connectivity', 'airplane-mode', 'enable' if network['airplane_mode_on']=='1' else 'disable')
            adb('shell', 'svc', 'wifi', 'enable' if network['wifi_on']=='1' else 'disable')
            adb('shell', 'svc', 'data', 'enable' if network['mobile_data']=='1' else 'disable')
            restored = {k: adb('shell', 'settings', 'get', 'global', k).decode().strip() for k in network}
            (out/'network-after.json').write_text(json.dumps(restored))
            if restored != network:
                raise RuntimeError('Network settings did not restore')
        if before != after:
            raise RuntimeError('Display setting did not restore')
    print(json.dumps(report, ensure_ascii=False))
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
