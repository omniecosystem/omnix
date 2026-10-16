// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Durable conversation snapshots; independent of Flutter and model runtimes.
//!
//! Hosts must choose a private database location. SQLite is not encrypted here.
//! Snapshot schema belongs to the conversation codec; database schema is separate.

use rusqlite::{params, Connection, OpenFlags, OptionalExtension, TransactionBehavior};
use serde_json::Value;
use std::{path::Path, time::Duration};

const APPLICATION_ID: i64 = 0x4f4d5354;
const SCHEMA_VERSION: i64 = 1;

/// A serialized SQLite connection to an Omnix-owned conversation database.
pub struct ConversationStore(Connection);

impl ConversationStore {
    /// Opens a dedicated database and migrates only recognized schemas.
    pub fn open(path: &Path) -> Result<Self, String> {
        if !path.is_absolute() || path.file_name().is_none() {
            return Err("Storage requires an absolute database file path".into());
        }
        // Create with owner-only permissions on Unix, rather than chmod a host's
        // pre-existing file. The host must secure the containing directory too.
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            match std::fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(path)
            {
                Ok(_) => (),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => (),
                Err(_) => return Err("Could not create private conversation database".into()),
            }
        }
        let mut connection = Connection::open_with_flags(
            path,
            OpenFlags::SQLITE_OPEN_READ_WRITE
                | OpenFlags::SQLITE_OPEN_CREATE
                | OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )
        .map_err(|_| "Could not open conversation database")?;
        connection
            .busy_timeout(Duration::from_secs(5))
            .map_err(db_error)?;
        let transaction = connection
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        let app: i64 = transaction
            .pragma_query_value(None, "application_id", |row| row.get(0))
            .map_err(db_error)?;
        let version: i64 = transaction
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .map_err(db_error)?;
        match (app, version) {
            (0, 0) => {
                let tables: i64 = transaction
                    .query_row(
                        "SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
                        [],
                        |row| row.get(0),
                    )
                    .map_err(db_error)?;
                if tables != 0 {
                    return Err(
                        "Database belongs to another application; no migration performed".into(),
                    );
                }
                transaction
                    .execute_batch(
                        "CREATE TABLE conversations (
                    id TEXT PRIMARY KEY NOT NULL,
                    record TEXT NOT NULL,
                    snapshot TEXT NOT NULL,
                    updated_ms INTEGER NOT NULL
                ); CREATE INDEX conversations_updated ON conversations(updated_ms DESC, id);",
                    )
                    .map_err(db_error)?;
                transaction
                    .pragma_update(None, "application_id", APPLICATION_ID)
                    .map_err(db_error)?;
                transaction
                    .pragma_update(None, "user_version", SCHEMA_VERSION)
                    .map_err(db_error)?;
            }
            (APPLICATION_ID, SCHEMA_VERSION) => {
                // Fail closed if a recognized database is structurally incomplete.
                transaction
                    .prepare("SELECT id, record, snapshot, updated_ms FROM conversations LIMIT 0")
                    .map_err(db_error)?;
            }
            _ => {
                return Err(
                    "Unsupported conversation database schema; no migration performed".into(),
                )
            }
        }
        transaction.commit().map_err(db_error)?;
        connection
            .pragma_update(None, "journal_mode", "WAL")
            .map_err(db_error)?;
        connection
            .pragma_update(None, "synchronous", "FULL")
            .map_err(db_error)?;
        Ok(Self(connection))
    }

    /// Returns metadata only, newest update first, with stable ID tie-breaking.
    pub fn records(&self) -> Result<Vec<String>, String> {
        let mut statement = self
            .0
            .prepare("SELECT record FROM conversations ORDER BY updated_ms DESC, id")
            .map_err(db_error)?;
        let records = statement
            .query_map([], |row| row.get(0))
            .map_err(db_error)?
            .collect::<Result<Vec<String>, _>>()
            .map_err(db_error);
        records
    }

    /// Reads a complete snapshot without altering model context.
    pub fn read(&self, id: &str) -> Result<Option<String>, String> {
        self.0
            .query_row(
                "SELECT snapshot FROM conversations WHERE id = ?1",
                [id],
                |row| row.get(0),
            )
            .optional()
            .map_err(db_error)
    }

    /// Atomically replaces metadata and the entire ordered message history.
    pub fn write(&mut self, snapshot: &str) -> Result<(), String> {
        let value: Value =
            serde_json::from_str(snapshot).map_err(|_| "Invalid conversation JSON")?;
        if value["schemaVersion"].as_u64() != Some(1) || !value["messages"].is_array() {
            return Err("Unsupported conversation snapshot".into());
        }
        let record = value
            .get("record")
            .filter(|v| v.is_object())
            .ok_or("Missing conversation record")?;
        let id = record["id"]
            .as_str()
            .filter(|id| !id.trim().is_empty())
            .ok_or("Missing conversation ID")?;
        let timestamp = record["updatedAt"]
            .as_str()
            .ok_or("Missing update timestamp")?;
        let updated = chrono::DateTime::parse_from_rfc3339(timestamp)
            .map_err(|_| "Invalid update timestamp")?
            .timestamp_millis();
        let transaction = self
            .0
            .transaction_with_behavior(TransactionBehavior::Immediate)
            .map_err(db_error)?;
        transaction.execute("INSERT INTO conversations(id, record, snapshot, updated_ms) VALUES (?1, ?2, ?3, ?4)
            ON CONFLICT(id) DO UPDATE SET record=excluded.record, snapshot=excluded.snapshot, updated_ms=excluded.updated_ms",
            params![id, record.to_string(), snapshot, updated]).map_err(db_error)?;
        transaction.commit().map_err(db_error)
    }

    /// Deletes one snapshot atomically; absent IDs are harmless.
    pub fn delete(&mut self, id: &str) -> Result<(), String> {
        self.0
            .execute("DELETE FROM conversations WHERE id = ?1", [id])
            .map_err(db_error)?;
        Ok(())
    }

    /// Closes the connection, reporting errors rather than silently losing ownership.
    pub fn close(self) -> Result<(), String> {
        self.0.close().map_err(|(_, error)| db_error(error))
    }
}

fn db_error(error: rusqlite::Error) -> String {
    // Do not expose SQL, paths, or message payloads in host-visible diagnostics.
    match error {
        rusqlite::Error::SqliteFailure(code, _) => {
            format!("Conversation database error: {:?}", code.code)
        }
        _ => "Conversation database operation failed".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn snapshot(id: &str, text: &str) -> String {
        serde_json::json!({"schemaVersion":1,"record":{"id":id,"updatedAt":"2026-10-02T00:00:00Z"},"messages":[{"text":text}]}).to_string()
    }
    #[test]
    fn survives_reopen_updates_and_deletes() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("history.sqlite");
        let mut store = ConversationStore::open(&path).unwrap();
        store.write(&snapshot("a", "first")).unwrap();
        store.write(&snapshot("b", "second")).unwrap();
        store.close().unwrap();
        let mut store = ConversationStore::open(&path).unwrap();
        assert_eq!(store.records().unwrap().len(), 2);
        assert_eq!(store.read("a").unwrap(), Some(snapshot("a", "first")));
        store.write(&snapshot("a", "replacement")).unwrap();
        assert_eq!(store.read("a").unwrap(), Some(snapshot("a", "replacement")));
        assert!(store.write("broken").is_err());
        assert_eq!(store.read("a").unwrap(), Some(snapshot("a", "replacement")));
        store.delete("a").unwrap();
        store.delete("absent").unwrap();
        assert!(store.read("a").unwrap().is_none());
        store.close().unwrap();
    }
    #[test]
    fn failed_transaction_preserves_old_snapshot() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("history.sqlite");
        let mut store = ConversationStore::open(&path).unwrap();
        store.write(&snapshot("a", "old")).unwrap();
        store.0.execute_batch("CREATE TRIGGER reject_update BEFORE UPDATE ON conversations BEGIN SELECT RAISE(ABORT, 'test'); END;").unwrap();
        assert!(store.write(&snapshot("a", "new")).is_err());
        assert_eq!(store.read("a").unwrap(), Some(snapshot("a", "old")));
    }
    #[test]
    fn refuses_foreign_and_future_schemas_without_mutating_them() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("other.sqlite");
        let db = Connection::open(&path).unwrap();
        db.execute_batch(
            "CREATE TABLE foreign_data(value TEXT); INSERT INTO foreign_data VALUES ('safe');",
        )
        .unwrap();
        assert!(ConversationStore::open(&path).is_err());
        assert_eq!(
            db.query_row("SELECT value FROM foreign_data", [], |r| r
                .get::<_, String>(0))
                .unwrap(),
            "safe"
        );
        let path = directory.path().join("future.sqlite");
        ConversationStore::open(&path).unwrap().close().unwrap();
        let db = Connection::open(&path).unwrap();
        db.pragma_update(None, "user_version", 2).unwrap();
        assert!(ConversationStore::open(&path).is_err());
        assert_eq!(
            db.pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))
                .unwrap(),
            2
        );
    }
}
