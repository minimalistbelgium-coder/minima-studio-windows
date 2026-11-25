"""Messages de progression lus par Minima Studio : une ligne JSON par événement sur stdout."""
import json, sys, time

_quiet = False

def set_quiet(q):
    global _quiet
    _quiet = q

def emit(kind, **kw):
    kw['type'] = kind
    kw['t'] = round(time.time(), 3)
    sys.stdout.write(json.dumps(kw, ensure_ascii=False) + '\n')
    sys.stdout.flush()

def step(name, pct=None, msg=None):
    emit('step', step=name, pct=pct, msg=msg)

def log(msg):
    emit('log', msg=msg)

def warn(msg):
    emit('warning', msg=msg)
