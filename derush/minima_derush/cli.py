"""Ligne de commande appelée par Minima Studio.

  minima-derush scan <dossier>
  minima-derush run <config.json>          -> écrit <nom>.xml à côté des rushes (le plan reste dans le dossier de l'app)
  minima-derush finalize <projet.prproj> <nom>.minima.json
"""
import sys, json, traceback, os
from . import __version__
from .progress import emit
from .scan import scan
from .engine import analyse, write
from .finalize import finalize
from . import media


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    try:
        if not argv or argv[0] in ('-h', '--help'):
            print(__doc__); return 0
        cmd = argv[0]
        if cmd == 'version':
            emit('result', version=__version__); return 0
        if cmd == 'scan':
            res = scan(argv[1])
            for m in res['mics']:
                try:
                    from .engine import mic_activity
                    m['activity'] = mic_activity(media.load_audio(m['path']))
                    m['use'] = m['activity']['active']
                except Exception as e:
                    m['error'] = str(e); m['use'] = False
            # micros très courts (essais, prises ratées) : décochés par défaut
            durs = [len(media.load_audio(m['path'])) for m in res['mics'] if 'error' not in m]
            longest = max(durs) if durs else 0
            for m in res['mics']:
                if 'error' in m:
                    continue
                n = len(media.load_audio(m['path']))
                m['duration'] = round(n / media.SR, 1)
                if n < 0.1 * longest:
                    m['use'] = False
                m['folder'] = os.path.basename(os.path.dirname(m['path']))
            from . import preview
            emit('step', step='preview', msg='Aperçus des micros et des caméras')
            try:
                preview.mic_clips([m for m in res['mics'] if 'error' not in m])
            except Exception as e:
                emit('warning', msg=f'Extraits audio indisponibles : {e}')
            try:
                preview.cam_thumbs(res['cams'])
            except Exception as e:
                emit('warning', msg=f'Images des caméras indisponibles : {e}')
            emit('result', **res); return 0
        if cmd == 'run':
            cfg = json.load(open(argv[1], encoding='utf-8'))
            plan = analyse(cfg)
            xml, pj = write(plan, cfg.get('out_dir') or cfg.get('root'))
            emit('result', xml=xml, plan=pj, stats=plan['stats']); return 0
        if cmd == 'finalize':
            r = finalize(argv[1], argv[2])
            emit('result', **r); return 0
        emit('error', msg=f'commande inconnue : {cmd}'); return 2
    except Exception as e:
        emit('error', msg=str(e), detail=traceback.format_exc()[-2000:])
        return 1


if __name__ == '__main__':
    sys.exit(main())
