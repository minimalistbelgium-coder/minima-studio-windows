# Minima Studio pour Windows

App Windows (Tauri) : l'espace Minima Studio + le chrono automatique dans Premiere Pro.

Télécharger : https://github.com/minimalistbelgium-coder/minima-studio-windows/releases/latest/download/MinimaStudio-Setup.exe

## Publier une nouvelle version
1. Changer `version` dans `src-tauri/tauri.conf.json` et `src-tauri/Cargo.toml`.
2. Pousser un tag `vX.Y.Z` : GitHub compile et publie l'installeur.
3. Les PC reçoivent « Nouvelle version » dans la carte du chrono.
