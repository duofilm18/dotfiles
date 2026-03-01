use serde::Serialize;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

/// WSL state files via UNC path
const WSL_TMP_DIR: &str = r"\\wsl$\Ubuntu\tmp";
const STATE_FILE_PREFIX: &str = "claude-led-state-";
const ACTIVITY_FILE_PREFIX: &str = "claude-activity-";
const STALE_TIMEOUT_SEC: u64 = 60;

#[derive(Debug, Serialize, Clone)]
pub struct Project {
    pub name: String,
    pub state: String,
}

fn state_sort_order(state: &str) -> u8 {
    match state {
        "WAITING" => 0,
        "RUNNING" => 1,
        "IDLE" => 2,
        "COMPLETED" => 3,
        "STALE" => 4,
        _ => 99,
    }
}

/// Known states (used to validate file content)
fn is_valid_state(s: &str) -> bool {
    matches!(s, "RUNNING" | "WAITING" | "COMPLETED" | "IDLE" | "STALE")
}

/// Scan WSL tmp for claude-led-state-* files, return sorted project list.
fn read_projects() -> Vec<Project> {
    let tmp_dir = PathBuf::from(WSL_TMP_DIR);
    let entries = match fs::read_dir(&tmp_dir) {
        Ok(e) => e,
        Err(_) => return Vec::new(),
    };

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    let mut results: Vec<Project> = Vec::new();

    for entry in entries.flatten() {
        let file_name = entry.file_name();
        let name_str = file_name.to_string_lossy();

        if !name_str.starts_with(STATE_FILE_PREFIX) {
            continue;
        }

        let project = &name_str[STATE_FILE_PREFIX.len()..];
        if project.is_empty() {
            continue;
        }

        // Read state from file (first line, uppercase)
        let state_path = entry.path();
        let mut state = match fs::read_to_string(&state_path) {
            Ok(content) => {
                let s = content.lines().next().unwrap_or("").trim().to_uppercase();
                if is_valid_state(&s) { s } else { "IDLE".to_string() }
            }
            Err(_) => continue,
        };

        // Check staleness via activity file
        let activity_path = tmp_dir.join(format!("{}{}", ACTIVITY_FILE_PREFIX, project));
        let stale = match fs::read_to_string(&activity_path) {
            Ok(content) => match content.trim().parse::<u64>() {
                Ok(ts) => now.saturating_sub(ts) > STALE_TIMEOUT_SEC,
                Err(_) => true,
            },
            Err(_) => true,
        };

        if stale && state != "COMPLETED" && state != "IDLE" {
            state = "STALE".to_string();
        }

        results.push(Project {
            name: project.to_string(),
            state,
        });
    }

    // Sort: state priority, then alphabetical
    results.sort_by(|a, b| {
        state_sort_order(&a.state)
            .cmp(&state_sort_order(&b.state))
            .then_with(|| a.name.cmp(&b.name))
    });

    results
}

#[tauri::command]
fn get_projects() -> Vec<Project> {
    read_projects()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![get_projects])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
