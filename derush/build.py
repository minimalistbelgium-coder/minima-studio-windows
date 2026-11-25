"""Construit le moteur autonome (Python + numpy + ffmpeg embarqués) pour la plateforme courante.
Sortie : dist/minima-derush/ (dossier) contenant l'exécutable et ffmpeg."""
import os, sys, shutil, subprocess, platform
import imageio_ffmpeg

here = os.path.dirname(os.path.abspath(__file__))
os.chdir(here)
shutil.rmtree('build', ignore_errors=True); shutil.rmtree('dist', ignore_errors=True)
subprocess.run([sys.executable, '-m', 'PyInstaller', '--noconfirm', '--clean', '--onedir', '--name', 'minima-derush',
                '--console', '--collect-submodules', 'minima_derush', 'minima-derush.py'], check=True)
out = os.path.join('dist', 'minima-derush')
ff = imageio_ffmpeg.get_ffmpeg_exe()
dst = os.path.join(out, 'ffmpeg.exe' if os.name == 'nt' else 'ffmpeg')
shutil.copy2(ff, dst)
os.chmod(dst, 0o755)
exe = os.path.join(out, 'minima-derush.exe' if os.name == 'nt' else 'minima-derush')
r = subprocess.run([exe, 'version'], capture_output=True, text=True)
print(r.stdout, r.stderr)
assert '"result"' in r.stdout, 'le moteur ne démarre pas'
print('OK', platform.machine(), out)
