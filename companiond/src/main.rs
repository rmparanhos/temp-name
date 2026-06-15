// On Windows, in release, hide the black console window that would open with it.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

//! CHRIS daemon (Tauri).
//!
//! - Shows the blob (a transparent window) and a tray icon.
//! - Listens on the IPC pipe. When an approval request arrives:
//!     1. the blob switches to "alert";
//!     2. the popup opens with the details;
//!     3. it waits for the click (Allow/Deny) or the timeout (-> Deny);
//!     4. it sends the decision back to the hook.

use std::collections::HashSet;
use std::sync::mpsc::{self, Sender};
use std::sync::Mutex;
use std::time::Duration;

use chris_core::{Decision, DecisionMsg, Msg};
use chris_transport_ipc as transport;
use tauri::{
    menu::{Menu, MenuItem},
    tray::TrayIconBuilder,
    AppHandle, Emitter, Manager, PhysicalPosition, State, WindowEvent,
};

/// Same timeout as the hook (deny if nobody answers in time).
const TIMEOUT_SECS: u64 = 120;

/// Shared state: the "channel" used to deliver the decision for the current request.
#[derive(Default)]
struct AppState {
    /// (id of the current request, sender that wakes whoever is waiting)
    current: Mutex<Option<(u32, Sender<Decision>)>>,
}

/// Command invoked by the popup buttons (via JS).
#[tauri::command]
fn decide(state: State<AppState>, id: u32, allow: bool) {
    if let Some((cur_id, tx)) = state.current.lock().unwrap().as_ref() {
        if *cur_id == id {
            let _ = tx.send(if allow { Decision::Allow } else { Decision::Deny });
        }
    }
}

/// Sends "Defer" for the current request: CHRIS steps aside so the agent's own
/// native prompt takes over (the popup's "Terminal" button). The request stays
/// open in the CLI.
#[tauri::command]
fn defer(state: State<AppState>, id: u32) {
    if let Some((cur_id, tx)) = state.current.lock().unwrap().as_ref() {
        if *cur_id == id {
            let _ = tx.send(Decision::Defer);
        }
    }
}

/// Opens a URL in the default browser (called by the PR popup's "Open" button).
#[tauri::command]
fn open_url(url: String) {
    #[cfg(target_os = "windows")]
    let _ = std::process::Command::new("cmd").args(["/C", "start", "", &url]).spawn();
    #[cfg(target_os = "macos")]
    let _ = std::process::Command::new("open").arg(&url).spawn();
    #[cfg(target_os = "linux")]
    let _ = std::process::Command::new("xdg-open").arg(&url).spawn();
}

/// Approves a PR (the PR popup's "Approve" button).
#[tauri::command]
fn approve_pr(owner: String, repo: String, number: u64) -> Result<(), String> {
    let token = chris_github::discover_token().ok_or("no GitHub token")?;
    chris_github::approve_pr(&token, &owner, &repo, number).map_err(|e| format!("{e:?}"))
}

/// Closes the PR popup and returns the blob to idle (the "Approve"/"Dismiss" buttons).
#[tauri::command]
fn hide_pr(app: AppHandle) {
    if let Some(w) = app.get_webview_window("pr") {
        let _ = w.hide();
    }
    let _ = app.emit_to("blob", "blob-state", serde_json::json!({"state":"idle","count":0}));
}

/// Sticks the `label` window (popup/pr) next to the blob: by default just above it,
/// horizontally centered. If it doesn't fit above, it goes below.
/// This is what makes the notification "travel together" with the blob.
fn position_near_blob(app: &AppHandle, label: &str) {
    let (Some(blob), Some(win)) = (app.get_webview_window("blob"), app.get_webview_window(label))
    else {
        return;
    };
    if let (Ok(bpos), Ok(bsize), Ok(wsize)) =
        (blob.outer_position(), blob.outer_size(), win.outer_size())
    {
        let gap: i32 = 10;
        let x = bpos.x + (bsize.width as i32 - wsize.width as i32) / 2;
        let mut y = bpos.y - wsize.height as i32 - gap; // above the blob
        if y < 0 {
            y = bpos.y + bsize.height as i32 + gap; // doesn't fit above -> go below
        }
        let _ = win.set_position(PhysicalPosition::new(x, y));
    }
}

fn main() {
    // Single-instance guard: if a daemon is already listening on the IPC pipe,
    // exit quietly instead of stacking up processes. A stale, hung instance
    // keeps the pipe open, which makes the next launch fail with
    // "couldn't open the IPC pipe" — so we refuse to start a duplicate.
    if transport::connect().is_ok() {
        eprintln!("CHRIS is already running — exiting this instance.");
        return;
    }

    tauri::Builder::default()
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![decide, defer, open_url, approve_pr, hide_pr])
        .setup(|app| {
            setup_tray(app.handle())?;

            // The blob is dragged with the native `data-tauri-drag-region` (smooth,
            // OS-level). While it moves, any visible notification follows it; and if
            // the window is closed (e.g. Alt+F4) we shut the whole app down so no
            // background process is left hanging.
            if let Some(blob) = app.get_webview_window("blob") {
                let h = app.handle().clone();
                blob.on_window_event(move |event| match event {
                    WindowEvent::Moved(_) => {
                        for label in ["popup", "pr"] {
                            if let Some(w) = h.get_webview_window(label) {
                                if w.is_visible().unwrap_or(false) {
                                    position_near_blob(&h, label);
                                }
                            }
                        }
                    }
                    WindowEvent::CloseRequested { .. } => std::process::exit(0),
                    _ => {}
                });
            }

            // start the IPC server (agent approvals) on a background thread
            let handle = app.handle().clone();
            std::thread::spawn(move || ipc_loop(handle));

            // start Pull Request polling on another thread
            let handle = app.handle().clone();
            std::thread::spawn(move || pr_loop(handle));

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("failed to start CHRIS");
}

/// PR notification loop: every minute it looks for PRs that request your review
/// and warns about the new ones. Without a GitHub token it stays disabled.
fn pr_loop(app: AppHandle) {
    let token = match chris_github::discover_token() {
        Some(t) => t,
        None => {
            eprintln!("CHRIS: no GitHub token — PR notifications disabled.");
            return;
        }
    };

    let mut seen: HashSet<u64> = HashSet::new();
    let mut first_pass = true;

    loop {
        if let Ok(prs) = chris_github::fetch_review_requests(&token) {
            // simple counts shown above the companion: PRs awaiting your review
            // and your own open PRs.
            let review = prs.len() as u64;
            let open = chris_github::fetch_open_authored_count(&token).unwrap_or(0);
            let _ = app.emit_to(
                "blob",
                "pr-counts",
                serde_json::json!({ "open": open, "review": review }),
            );

            let fresh = chris_github::only_new(&seen, &prs);
            for p in &prs {
                seen.insert(p.id);
            }
            // on the first pass only record (don't warn about pre-existing ones)
            if !first_pass {
                for p in fresh {
                    notify_pr(&app, &p);
                    std::thread::sleep(Duration::from_secs(8));
                }
            }
            first_pass = false;
        }
        std::thread::sleep(Duration::from_secs(60));
    }
}

/// Makes the blob react to a PR and opens the PR popup with the details.
fn notify_pr(app: &AppHandle, pr: &chris_github::PrItem) {
    let _ = app.emit_to("blob", "blob-state", serde_json::json!({"state":"pr","count":0}));
    let _ = app.emit_to(
        "pr",
        "pr",
        serde_json::json!({
            "owner": pr.owner,
            "repo": pr.repo,
            "number": pr.number,
            "title": pr.title,
            "author": pr.author,
            "url": pr.url,
        }),
    );
    // place it next to the blob and show it WITHOUT stealing focus
    position_near_blob(app, "pr");
    if let Some(win) = app.get_webview_window("pr") {
        let _ = win.show();
    }
}

/// Builds the tray icon and its menu.
fn setup_tray(app: &AppHandle) -> tauri::Result<()> {
    let toggle = MenuItem::with_id(app, "toggle", "Show/hide companion", true, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(app, &[&toggle, &quit])?;

    TrayIconBuilder::new()
        .icon(app.default_window_icon().unwrap().clone())
        .tooltip("CHRIS — idle")
        .menu(&menu)
        .on_menu_event(|app, event| match event.id.as_ref() {
            // Hard exit: bypasses Tauri's graceful shutdown (which can hang while
            // background threads are blocked on IPC accept) and releases the pipe.
            "quit" => std::process::exit(0),
            "toggle" => {
                if let Some(win) = app.get_webview_window("blob") {
                    let visible = win.is_visible().unwrap_or(false);
                    let _ = if visible { win.hide() } else { win.show() };
                }
            }
            _ => {}
        })
        .build(app)?;
    Ok(())
}

/// IPC server loop: accepts connections and handles one request at a time (a queue).
fn ipc_loop(app: AppHandle) {
    let listener = match transport::listen() {
        Ok(l) => l,
        Err(e) => {
            eprintln!("CHRIS: couldn't open the IPC pipe: {e}");
            return;
        }
    };
    loop {
        match transport::accept(&listener) {
            Ok(mut conn) => {
                // read the request
                let req = match transport::read_msg(&mut conn) {
                    Ok(Msg::Request(r)) => r,
                    _ => continue, // unexpected message: ignore
                };
                let decision = handle_request(&app, &req);
                // send the decision back to the hook (ignore if the hook already left)
                let _ = transport::write_msg(
                    &mut conn,
                    &Msg::Decision(DecisionMsg {
                        id: req.id,
                        decision,
                        reason: String::new(),
                    }),
                );
            }
            Err(_) => continue,
        }
    }
}

/// Whether the approval popup should grab keyboard focus when it appears.
/// Off by default so it doesn't interrupt what you're typing; opt in with
/// `CHRIS_FOCUS_POPUP=1` to use the Enter/Esc shortcuts without clicking first.
fn focus_popup() -> bool {
    matches!(
        std::env::var("CHRIS_FOCUS_POPUP").ok().as_deref(),
        Some("1") | Some("true") | Some("yes")
    )
}

/// Shows the request (blob + popup) and waits for the decision (or timeout = Deny).
fn handle_request(app: &AppHandle, req: &chris_core::ApprovalRequest) -> Decision {
    // blob -> alert
    let _ = app.emit_to("blob", "blob-state", serde_json::json!({"state":"alert","count":1}));

    // popup -> show with the details
    let _ = app.emit_to(
        "popup",
        "approval",
        serde_json::json!({
            "id": req.id.0,
            "agent": format!("{:?}", req.agent),
            "tool": req.tool,
            "summary": req.summary,
            "cwd": req.cwd,
            "risk": format!("{:?}", req.risk).to_lowercase(),
        }),
    );
    // place it next to the blob and show it WITHOUT stealing focus, so a popup
    // never interrupts what you're typing. You can still click Allow/Deny.
    // Set CHRIS_FOCUS_POPUP=1 if you'd rather it grab focus so the keyboard
    // shortcuts (Enter = allow, Esc = deny) work without clicking first.
    position_near_blob(app, "popup");
    if let Some(win) = app.get_webview_window("popup") {
        let _ = win.show();
        if focus_popup() {
            let _ = win.set_focus();
        }
    }

    // register the decision channel and wait
    let (tx, rx) = mpsc::channel();
    {
        let state = app.state::<AppState>();
        *state.current.lock().unwrap() = Some((req.id.0, tx));
    }
    let decision = rx
        .recv_timeout(Duration::from_secs(TIMEOUT_SECS))
        .unwrap_or(Decision::Deny);
    {
        let state = app.state::<AppState>();
        *state.current.lock().unwrap() = None;
    }

    // visual feedback, then close the popup. Defer = CHRIS stepped aside, so no
    // approved/denied flash — just go back to idle.
    let visual = match decision {
        Decision::Allow => "approved",
        Decision::Deny => "denied",
        Decision::Defer => "idle",
    };
    let _ = app.emit_to("blob", "blob-state", serde_json::json!({"state":visual,"count":0}));
    if let Some(win) = app.get_webview_window("popup") {
        let _ = win.hide();
    }
    std::thread::sleep(Duration::from_millis(1200));
    let _ = app.emit_to("blob", "blob-state", serde_json::json!({"state":"idle","count":0}));

    decision
}
