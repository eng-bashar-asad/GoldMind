fn main() {
    // Listing the commands makes Tauri check each one against the capabilities: the calculator
    // page gets all four, the GoldMind pages only change_code (capabilities/goldmind.json).
    tauri_build::try_build(
        tauri_build::Attributes::new().app_manifest(
            tauri_build::AppManifest::new().commands(&["get_code", "set_code", "open_app", "change_code"]),
        ),
    )
    .expect("failed to run tauri-build");
}
