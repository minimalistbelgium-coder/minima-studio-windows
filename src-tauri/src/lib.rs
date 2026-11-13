//! Minima Studio pour Windows : la fenêtre affiche l'espace Minima Studio,
//! et ce module lit l'état de Premiere Pro et l'activité clavier/souris pour le chrono.

use serde::Serialize;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, TrayIconBuilder, TrayIconEvent};
use tauri::{Manager, WebviewUrl, WebviewWindowBuilder, WindowEvent};

/// Réaffiche la fenêtre principale (icône de la zone de notification, second lancement).
fn show_main(app: &tauri::AppHandle) {
    if let Some(m) = app.get_webview_window("main") {
        let _ = m.show();
        let _ = m.unminimize();
        let _ = m.set_focus();
    }
}

#[derive(Serialize, Default)]
pub struct PremiereState {
    /// Premiere Pro est lancé
    open: bool,
    /// Premiere Pro est au premier plan
    front: bool,
    /// Titres des fenêtres de Premiere (contiennent le chemin du projet)
    titles: Vec<String>,
    /// Secondes depuis la dernière action clavier/souris
    idle_secs: f64,
}

#[cfg(windows)]
mod win {
    use super::PremiereState;
    use windows::core::PWSTR;
    use windows::Win32::Foundation::{CloseHandle, BOOL, HWND, LPARAM};
    use windows::Win32::System::SystemInformation::GetTickCount;
    use windows::Win32::System::Threading::{
        OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
    };
    use windows::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};
    use windows::Win32::UI::WindowsAndMessaging::{
        EnumWindows, GetForegroundWindow, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId,
        IsWindowVisible,
    };

    fn exe_name(pid: u32) -> Option<String> {
        unsafe {
            let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
            let mut buf = [0u16; 1024];
            let mut size = buf.len() as u32;
            let ok = QueryFullProcessImageNameW(h, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut size).is_ok();
            let _ = CloseHandle(h);
            if !ok {
                return None;
            }
            let path = String::from_utf16_lossy(&buf[..size as usize]);
            path.rsplit('\\').next().map(|s| s.to_lowercase())
        }
    }

    fn is_premiere(pid: u32) -> bool {
        exe_name(pid)
            .map(|n| n.contains("premiere pro") || n == "premiere.exe")
            .unwrap_or(false)
    }

    fn window_pid(hwnd: HWND) -> u32 {
        let mut pid = 0u32;
        unsafe {
            GetWindowThreadProcessId(hwnd, Some(&mut pid));
        }
        pid
    }

    fn window_title(hwnd: HWND) -> String {
        unsafe {
            let len = GetWindowTextLengthW(hwnd);
            if len <= 0 {
                return String::new();
            }
            let mut buf = vec![0u16; len as usize + 1];
            let n = GetWindowTextW(hwnd, &mut buf);
            String::from_utf16_lossy(&buf[..n.max(0) as usize])
        }
    }

    struct Collect {
        titles: Vec<String>,
        found: bool,
    }

    unsafe extern "system" fn enum_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
        let c = &mut *(lparam.0 as *mut Collect);
        if IsWindowVisible(hwnd).as_bool() {
            let pid = window_pid(hwnd);
            if pid != 0 && is_premiere(pid) {
                c.found = true;
                let t = window_title(hwnd);
                if !t.is_empty() {
                    c.titles.push(t);
                }
            }
        }
        BOOL(1)
    }

    pub fn state() -> PremiereState {
        let mut c = Collect { titles: vec![], found: false };
        unsafe {
            let _ = EnumWindows(Some(enum_proc), LPARAM(&mut c as *mut Collect as isize));
        }
        let fg = unsafe { GetForegroundWindow() };
        let front = !fg.is_invalid() && {
            let pid = window_pid(fg);
            pid != 0 && is_premiere(pid)
        };
        let idle_secs = unsafe {
            let mut info = LASTINPUTINFO { cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32, dwTime: 0 };
            if GetLastInputInfo(&mut info).as_bool() {
                GetTickCount().wrapping_sub(info.dwTime) as f64 / 1000.0
            } else {
                0.0
            }
        };
        PremiereState { open: c.found || front, front, titles: c.titles, idle_secs }
    }
}

#[tauri::command]
fn premiere_state() -> PremiereState {
    #[cfg(windows)]
    {
        win::state()
    }
    #[cfg(not(windows))]
    {
        PremiereState::default()
    }
}

/// Ouvre (ou montre) la petite fenêtre du chrono, toujours au-dessus.
#[tauri::command]
fn show_mini(app: tauri::AppHandle) -> Result<(), String> {
    if let Some(w) = app.get_webview_window("mini") {
        let _ = w.show();
        let _ = w.set_focus();
        return Ok(());
    }
    WebviewWindowBuilder::new(&app, "mini", WebviewUrl::App("mini.html".into()))
        .title("Minima Studio · Chrono")
        .inner_size(320.0, 190.0)
        .resizable(false)
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .build()
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// Ferme la petite fenêtre et remet la grande au premier plan.
#[tauri::command]
fn hide_mini(app: tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("mini") {
        let _ = w.close();
    }
    if let Some(m) = app.get_webview_window("main") {
        let _ = m.show();
        let _ = m.unminimize();
        let _ = m.set_focus();
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(m) = app.get_webview_window("main") {
                let _ = m.show();
                let _ = m.unminimize();
                let _ = m.set_focus();
            }
        }))
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec!["--minimized"]),
        ))
        .invoke_handler(tauri::generate_handler![premiere_state, show_mini, hide_mini])
        // Fermer la fenêtre ne quitte pas : l'app reste en fond pour que le chrono Premiere continue.
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                if window.label() == "main" {
                    api.prevent_close();
                    let _ = window.hide();
                }
            }
        })
        .setup(|app| {
            let open = MenuItem::with_id(app, "open", "Ouvrir Minima Studio", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quitter (le chrono s'arrête)", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &quit])?;
            let mut tray = TrayIconBuilder::with_id("main")
                .tooltip("Minima Studio : le chrono Premiere reste actif")
                .menu(&menu)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "open" => show_main(app),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::DoubleClick { button: MouseButton::Left, .. } = event {
                        show_main(tray.app_handle());
                    }
                });
            if let Some(icon) = app.default_window_icon() {
                tray = tray.icon(icon.clone());
            }
            tray.build(app)?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("erreur au lancement de Minima Studio");
}
