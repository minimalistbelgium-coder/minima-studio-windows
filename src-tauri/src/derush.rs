//! Dérush : lance le moteur hors ligne livré avec l'app (dossier `derush/` des ressources)
//! et renvoie sa progression ligne par ligne à la page (événement `derush-line`).

use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use tauri::{Emitter, Manager};

#[cfg(windows)]
use std::os::windows::process::CommandExt;
#[cfg(windows)]
const NO_WINDOW: u32 = 0x0800_0000;

fn engine_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let res = app.path().resource_dir().map_err(|e| e.to_string())?;
    for d in [res.join("derush").join("minima-derush"), res.join("derush")] {
        let exe = d.join(if cfg!(windows) { "minima-derush.exe" } else { "minima-derush" });
        if exe.exists() {
            return Ok(d);
        }
    }
    Err("Moteur de dérush introuvable dans l'installation.".into())
}

#[derive(Clone, serde::Serialize)]
struct Line {
    id: String,
    line: Option<String>,
    done: bool,
    code: Option<i32>,
}

/// Lance `minima-derush <args…>`. Si `config` est fourni, il est écrit dans un fichier temporaire
/// passé en dernier argument (commande `run`). Les lignes JSON du moteur arrivent dans `derush-line`.
#[tauri::command]
pub fn derush_exec(app: tauri::AppHandle, id: String, args: Vec<String>, config: Option<String>) -> Result<(), String> {
    let dir = engine_dir(&app)?;
    let exe = dir.join(if cfg!(windows) { "minima-derush.exe" } else { "minima-derush" });
    let ffmpeg = dir.join(if cfg!(windows) { "ffmpeg.exe" } else { "ffmpeg" });
    let mut args = args;
    if let Some(cfg) = config {
        let p = std::env::temp_dir().join(format!("minima-derush-{}.json", id));
        let mut f = std::fs::File::create(&p).map_err(|e| e.to_string())?;
        f.write_all(cfg.as_bytes()).map_err(|e| e.to_string())?;
        args.push(p.to_string_lossy().into_owned());
    }
    let mut cmd = Command::new(&exe);
    cmd.args(&args)
        .env("MINIMA_FFMPEG", &ffmpeg)
        .env("PYTHONIOENCODING", "utf-8")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(windows)]
    cmd.creation_flags(NO_WINDOW);
    let mut child = cmd.spawn().map_err(|e| format!("Impossible de lancer le moteur : {e}"))?;
    let out = child.stdout.take().unwrap();
    std::thread::spawn(move || {
        for l in BufReader::new(out).lines().map_while(Result::ok) {
            let _ = app.emit("derush-line", Line { id: id.clone(), line: Some(l), done: false, code: None });
        }
        let code = child.wait().ok().and_then(|s| s.code());
        let _ = app.emit("derush-line", Line { id, line: None, done: true, code });
    });
    Ok(())
}

/// Ouvre un fichier (le XML du dérush) avec Premiere Pro, en prenant la version la plus récente installée.
#[tauri::command]
pub fn open_in_premiere(path: String) -> Result<String, String> {
    #[cfg(windows)]
    {
        let base = PathBuf::from(r"C:\Program Files\Adobe");
        let mut found: Vec<PathBuf> = std::fs::read_dir(&base)
            .map_err(|e| e.to_string())?
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| p.file_name().map(|n| n.to_string_lossy().starts_with("Adobe Premiere Pro")).unwrap_or(false))
            .map(|p| p.join("Adobe Premiere Pro.exe"))
            .filter(|p| p.exists())
            .collect();
        found.sort();
        let exe = found.pop().ok_or("Premiere Pro introuvable dans C:\\Program Files\\Adobe.")?;
        Command::new(&exe).arg(&path).spawn().map_err(|e| e.to_string())?;
        return Ok(exe.to_string_lossy().into_owned());
    }
    #[cfg(not(windows))]
    {
        Command::new("open").arg(&path).spawn().map_err(|e| e.to_string())?;
        Ok("open".into())
    }
}

/// Aperçu (extrait audio .m4a ou image .jpg) préparé par le moteur, renvoyé en data URL.
/// Limité au dossier d'aperçus du moteur.
#[tauri::command]
pub fn derush_preview(path: String) -> Result<String, String> {
    let p = PathBuf::from(&path);
    let ok = p.components().any(|c| c.as_os_str() == ".minima-derush")
        && p.parent().and_then(|d| d.file_name()).map(|n| n == "previews").unwrap_or(false);
    if !ok {
        return Err("Aperçu refusé.".into());
    }
    let mime = match p.extension().and_then(|e| e.to_str()).unwrap_or("") {
        "jpg" | "jpeg" => "image/jpeg",
        "m4a" => "audio/mp4",
        "mp3" => "audio/mpeg",
        _ => return Err("Type d'aperçu inconnu.".into()),
    };
    let bytes = std::fs::read(&p).map_err(|e| e.to_string())?;
    Ok(format!("data:{};base64,{}", mime, b64(&bytes)))
}

fn b64(data: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut s = String::with_capacity(data.len() * 4 / 3 + 4);
    for ch in data.chunks(3) {
        let n = (ch[0] as u32) << 16 | (*ch.get(1).unwrap_or(&0) as u32) << 8 | *ch.get(2).unwrap_or(&0) as u32;
        s.push(T[(n >> 18 & 63) as usize] as char);
        s.push(T[(n >> 12 & 63) as usize] as char);
        s.push(if ch.len() > 1 { T[(n >> 6 & 63) as usize] as char } else { '=' });
        s.push(if ch.len() > 2 { T[(n & 63) as usize] as char } else { '=' });
    }
    s
}
