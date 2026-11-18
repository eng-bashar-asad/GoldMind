// Calculator Pro: shows a working calculator; the secret sequence (checked in src/calc.js)
// calls open_app, which turns the same window into the main program.
// The window is incognito (WebView2 InPrivate): cookies, cache and storage of the program
// are kept in memory only and are gone when the window closes.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::{fs, path::PathBuf};
use tauri::{webview::NewWindowResponse, AppHandle, Manager, Url, WebviewUrl, WebviewWindow, WebviewWindowBuilder};

const APP_URL: &str = "https://eng-bashar-asad.github.io/GoldMind/login-entry-ar.html";

fn code_file(app: &AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir.join("settings.dat"))
}

// "<length>:<sha256 hex>" — the plain sequence never leaves the page.
fn valid_code(v: &str) -> bool {
    match v.split_once(':') {
        Some((n, h)) => {
            n.parse::<u8>().map_or(false, |n| (5..=21).contains(&n))
                && h.len() == 64
                && h.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
        }
        None => false,
    }
}

#[tauri::command]
fn get_code(app: AppHandle) -> Option<String> {
    let v = fs::read_to_string(code_file(&app).ok()?).ok()?;
    let v = v.trim().to_string();
    valid_code(&v).then_some(v)
}

#[tauri::command]
fn set_code(app: AppHandle, value: String) -> Result<(), String> {
    if !valid_code(&value) {
        return Err("invalid".into());
    }
    fs::write(code_file(&app)?, value).map_err(|e| e.to_string())
}

#[tauri::command]
fn open_app(window: WebviewWindow) -> Result<(), String> {
    let url: Url = APP_URL.parse().map_err(|_| "bad url".to_string())?;
    window.set_resizable(true).map_err(|e| e.to_string())?;
    window.set_maximizable(true).map_err(|e| e.to_string())?;
    window.maximize().map_err(|e| e.to_string())?;
    window.navigate(url).map_err(|e| e.to_string())
}

// Pages of the program (print views, reports opened in a new tab) open in a new app window that
// shares this window's session; anything else (WhatsApp, maps, mail) opens in the default browser.
fn is_program_url(url: &Url) -> bool {
    url.scheme() == "https" && url.host_str() == Some("eng-bashar-asad.github.io") && url.path().starts_with("/GoldMind/")
        || url.scheme() == "about"
        || url.scheme() == "blob"
}

fn open_outside(url: &Url) {
    if !matches!(url.scheme(), "http" | "https" | "mailto" | "tel" | "whatsapp") {
        return;
    }
    #[cfg(windows)]
    {
        // FileProtocolHandler hands the URL to the default app without going through a shell
        let _ = std::process::Command::new("rundll32").arg("url.dll,FileProtocolHandler").arg(url.as_str()).spawn();
    }
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
                .title("Calculator Pro")
                .inner_size(420.0, 600.0)
                .min_inner_size(380.0, 540.0)
                .resizable(false)
                .maximizable(false)
                .center()
                .incognito(true)
                .on_new_window(|url, _features| {
                    if is_program_url(&url) {
                        NewWindowResponse::Allow
                    } else {
                        open_outside(&url);
                        NewWindowResponse::Deny
                    }
                })
                .build()?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![get_code, set_code, open_app])
        .run(tauri::generate_context!())
        .expect("error while running application");
}

#[cfg(test)]
mod tests {
    use super::valid_code;
    #[test]
    fn program_urls() {
        let ok = |u: &str| super::is_program_url(&u.parse().unwrap());
        assert!(ok("https://eng-bashar-asad.github.io/GoldMind/invoice-print-ar.html?id=1"));
        assert!(!ok("https://wa.me/963933000960"));
        assert!(!ok("https://eng-bashar-asad.github.io/other/"));
    }

    #[test]
    fn code_format() {
        let h = "a".repeat(64);
        assert!(valid_code(&format!("7:{h}")));
        assert!(!valid_code(&format!("2:{h}")));
        assert!(!valid_code("7:xyz"));
        assert!(!valid_code(&format!("7:{}", "A".repeat(64))));
    }
}
