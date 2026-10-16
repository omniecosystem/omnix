//! Dedicated durable workflow snapshots, without depending on Workflow's schema.
use rusqlite::{params, Connection, OptionalExtension, TransactionBehavior};
use std::{fs::File, path::Path, time::Duration};

/// A single-owner workflow database. The owner lock is released on drop/crash.
/// Keep the sidecar lock file: deleting it can allow concurrent owners.
pub struct WorkflowStore {
    connection: Connection,
    _owner: File,
}
impl WorkflowStore {
    pub fn open(path: &Path) -> Result<Self, String> {
        if !path.is_absolute() || path.file_name().is_none() {
            return Err("Workflow storage requires an absolute database path".into());
        }
        let mut options = std::fs::OpenOptions::new();
        options.read(true).write(true).create(true).truncate(false);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        drop(
            options
                .open(path)
                .map_err(|_| "Could not open workflow database")?,
        );
        let path = path
            .canonicalize()
            .map_err(|_| "Could not resolve workflow database")?;
        let mut lock_name = path.as_os_str().to_os_string();
        lock_name.push(".owner");
        let owner = options
            .open(Path::new(&lock_name))
            .map_err(|_| "Could not open workflow owner lock")?;
        owner
            .try_lock()
            .map_err(|_| "Workflow database is already owned or locking is unavailable")?;
        let mut connection =
            Connection::open(path).map_err(|_| "Could not open workflow database")?;
        connection
            .busy_timeout(Duration::from_secs(5))
            .map_err(|e| e.to_string())?;
        let tx = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(|e| e.to_string())?;
        let app: i64 = tx
            .pragma_query_value(None, "application_id", |r| r.get(0))
            .map_err(|e| e.to_string())?;
        let version: i64 = tx
            .pragma_query_value(None, "user_version", |r| r.get(0))
            .map_err(|e| e.to_string())?;
        match (app, version) {
            (0, 0) => {
                let tables: i64 = tx
                    .query_row(
                        "SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
                        [],
                        |r| r.get(0),
                    )
                    .map_err(|e| e.to_string())?;
                if tables != 0 {
                    return Err("Not an Omnix workflow database; no migration performed".into());
                }
                tx.execute_batch("CREATE TABLE workflow_snapshots(id TEXT PRIMARY KEY NOT NULL, snapshot TEXT NOT NULL);").map_err(|e| e.to_string())?;
                tx.pragma_update(None, "application_id", 0x4f4d574a_i64)
                    .map_err(|e| e.to_string())?;
                tx.pragma_update(None, "user_version", 1)
                    .map_err(|e| e.to_string())?;
            }
            (0x4f4d574a, 1) => {
                tx.prepare("SELECT id, snapshot FROM workflow_snapshots LIMIT 0")
                    .map_err(|e| e.to_string())?;
            }
            _ => return Err("Unsupported workflow database; no migration performed".into()),
        }
        tx.commit().map_err(|e| e.to_string())?;
        connection
            .pragma_update(None, "journal_mode", "WAL")
            .map_err(|e| e.to_string())?;
        connection
            .pragma_update(None, "synchronous", "FULL")
            .map_err(|e| e.to_string())?;
        Ok(Self {
            connection,
            _owner: owner,
        })
    }
    pub fn read(&self, id: &str) -> Result<Option<String>, String> {
        let result: Option<String> = self
            .connection
            .query_row(
                "SELECT snapshot FROM workflow_snapshots WHERE id=?1",
                [id],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| e.to_string())?;
        if result.as_ref().is_some_and(|s| s.len() > 1_048_576) {
            return Err("Oversized workflow snapshot".into());
        }
        Ok(result)
    }
    pub fn write(&mut self, id: &str, snapshot: &str) -> Result<(), String> {
        if id.is_empty() || id.len() > 128 || snapshot.len() > 1_048_576 {
            return Err("Invalid workflow snapshot bounds".into());
        }
        let _: serde_json::Value =
            serde_json::from_str(snapshot).map_err(|_| "Invalid workflow JSON")?;
        self.connection.execute("INSERT INTO workflow_snapshots(id,snapshot) VALUES(?1,?2) ON CONFLICT(id) DO UPDATE SET snapshot=excluded.snapshot", params![id,snapshot]).map_err(|e| e.to_string())?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exclusive_owner_and_durable_reopen() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("jobs.sqlite");
        let mut store = WorkflowStore::open(&path).unwrap();
        store.write("one", "{\"result\":null}").unwrap();
        assert!(WorkflowStore::open(&path).is_err());
        drop(store);
        assert_eq!(
            WorkflowStore::open(&path)
                .unwrap()
                .read("one")
                .unwrap()
                .as_deref(),
            Some("{\"result\":null}")
        );
    }
    #[test]
    fn foreign_database_is_not_migrated() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("foreign.sqlite");
        let db = Connection::open(&path).unwrap();
        db.execute_batch("CREATE TABLE precious(value TEXT); INSERT INTO precious VALUES('keep');")
            .unwrap();
        assert!(WorkflowStore::open(&path).is_err());
        assert_eq!(
            db.query_row("SELECT value FROM precious", [], |r| r.get::<_, String>(0))
                .unwrap(),
            "keep"
        );
    }
}
