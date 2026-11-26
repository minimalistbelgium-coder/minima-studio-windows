//! Mise à jour en un clic : télécharge l'installeur de la dernière version publiée sur GitHub,
//! ferme l'app, l'installe sans fenêtre (/S) puis relance Minima Studio.

#[cfg(windows)]
use std::os::windows::process::CommandExt;

const PREFIX: &str = "https://github.com/minimalistbelgium-coder/minima-studio-windows/releases/download/";

#[tauri::command]
pub fn install_update(url: String) -> Result<(), String> {
    if !url.starts_with(PREFIX) || url.contains('\'') || url.contains('"') || url.contains(' ') {
        return Err("Adresse de mise à jour refusée".into());
    }
    #[cfg(windows)]
    {
        let exe = std::env::current_exe().map_err(|e| e.to_string())?;
        let exe = exe.to_string_lossy().replace('\'', "''");
        let pid = std::process::id();
        let script = format!(
            "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; \
             $f = Join-Path $env:TEMP 'MinimaStudio-Setup.exe'; \
             try {{ Invoke-WebRequest -UseBasicParsing -Uri '{url}' -OutFile $f }} catch {{ exit 1 }}; \
             Stop-Process -Id {pid} -Force -ErrorAction SilentlyContinue; \
             Start-Sleep -Seconds 2; \
             Start-Process -FilePath $f -ArgumentList '/S' -Wait; \
             Start-Process -FilePath '{exe}'"
        );
        std::process::Command::new("powershell")
            .args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-Command", &script])
            .creation_flags(0x0800_0000 | 0x0000_0008) // sans fenêtre, détaché de l'app
            .spawn()
            .map_err(|e| e.to_string())?;
        Ok(())
    }
    #[cfg(not(windows))]
    {
        let _ = url;
        Err("Mise à jour automatique réservée à Windows".into())
    }
}
