//! SQLite-backed checkpoint example with simulated actions.
//! The library itself has no database dependency.
use omnix_workflow::*;
use rusqlite::{params, Connection, OptionalExtension};
use serde_json::json;
use std::sync::atomic::AtomicBool;

struct SqliteJournal(Connection);
impl Journal for SqliteJournal {
    fn load(&mut self, id: &str) -> Result<Option<Progress>, String> {
        let raw: Option<String> = self
            .0
            .query_row(
                "SELECT snapshot FROM workflow_demo WHERE id=?1",
                [id],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| e.to_string())?;
        raw.map(|s| {
            if s.len() > 1_048_576 {
                return Err("Oversized checkpoint".into());
            }
            serde_json::from_str(&s).map_err(|e| e.to_string())
        })
        .transpose()
    }
    fn save(&mut self, progress: &Progress) -> Result<(), String> {
        let serialized = serde_json::to_string(progress).map_err(|e| e.to_string())?;
        self.0.execute("INSERT INTO workflow_demo(id,snapshot) VALUES(?1,?2) ON CONFLICT(id) DO UPDATE SET snapshot=excluded.snapshot", params![progress.id,serialized]).map_err(|e|e.to_string())?;
        Ok(())
    }
}
struct Host;
impl Executor for Host {
    fn execute(&mut self, _: &str, step: &Step, _: &AtomicBool) -> Outcome {
        println!("Executing demo step: {}", step.id);
        if step.id == "handoff" {
            println!("Simulating lost confirmation; no real device action occurs.");
            Outcome::Interrupted
        } else {
            Outcome::Succeeded(json!({"status":"ok"}))
        }
    }
}
fn main() -> Result<(), String> {
    let path = std::env::args()
        .nth(1)
        .ok_or("Supply an absolute path to a NEW dedicated demo SQLite file")?;
    if !std::path::Path::new(&path).is_absolute() {
        return Err("Use an absolute path".into());
    }
    let connection = Connection::open(path).map_err(|e| e.to_string())?;
    let app: i64 = connection
        .pragma_query_value(None, "application_id", |r| r.get(0))
        .map_err(|e| e.to_string())?;
    if app != 0x4f4d5746 {
        let tables: i64 = connection
            .query_row(
                "SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
                [],
                |r| r.get(0),
            )
            .map_err(|e| e.to_string())?;
        if app != 0 || tables != 0 {
            return Err("Not an Omnix Workflow demo database".into());
        }
        connection.execute_batch("CREATE TABLE workflow_demo(id TEXT PRIMARY KEY, snapshot TEXT NOT NULL); PRAGMA application_id=1330468678;").map_err(|e|e.to_string())?;
    }
    let mut workflow = Workflow::open(
        SqliteJournal(connection),
        Progress::new(
            "demo",
            vec![
                Step::new("inspect", "demo", json!({}), RetrySafety::SafeToRepeat),
                Step::new(
                    "handoff",
                    "demo",
                    json!({}),
                    RetrySafety::RequiresReconciliation,
                ),
                Step::new("summarize", "demo", json!({}), RetrySafety::SafeToRepeat),
            ],
        ),
    )?;
    workflow.recover()?;
    if std::env::args().any(|a| a == "--confirm-demo-handoff") {
        workflow.reconcile(
            "handoff",
            Outcome::Succeeded(json!({"demo_confirmation":true})),
        )?;
    }
    loop {
        match workflow.run_next(&mut Host, &AtomicBool::new(false)) {
            Ok(true) => (),
            Ok(false) => break,
            Err(reason) => {
                println!("Blocked: {reason}");
                break;
            }
        }
    }
    println!(
        "{}",
        serde_json::to_string_pretty(workflow.progress()).map_err(|e| e.to_string())?
    );
    Ok(())
}
