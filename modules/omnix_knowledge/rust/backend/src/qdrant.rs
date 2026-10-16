// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Optional document adapter over native Storage; no inference dependency.
use crate::{AccessScope, EmbeddingProfile, KnowledgeError, Match, Record, SearchOptions, Store};
use omnix_storage::{QdrantStore, VectorProfile};
use serde_json::{Map, Value};
use sha2::{Digest, Sha256};
use std::path::Path;

pub struct QdrantKnowledgeStore {
    store: QdrantStore,
    profile: EmbeddingProfile,
}

impl QdrantKnowledgeStore {
    pub fn open(path: &Path, profile: EmbeddingProfile) -> Result<Self, KnowledgeError> {
        if profile.id.trim().is_empty() || profile.dimension == 0 {
            return Err(KnowledgeError::InvalidInput("invalid embedding profile"));
        }
        // Separate from raw vector shards; never adopt unrelated payload formats.
        let store = QdrantStore::open(
            path,
            VectorProfile {
                // Use a stable namespace with a filesystem-safe identity for
                // compatibility with stores created before format 2.
                id: format!("knowledge-v1-{:x}", Sha256::digest(profile.id.as_bytes())),
                dimension: profile.dimension,
            },
        )
        .map_err(KnowledgeError::Backend)?;
        Ok(Self { store, profile })
    }

    fn checked_id(&self, id: &str) -> Result<u64, KnowledgeError> {
        if id.trim().is_empty() {
            return Err(KnowledgeError::InvalidInput("empty record ID"));
        }
        let point_id = point_id(id);
        if let Some(payload) = self
            .store
            .read_metadata(point_id)
            .map_err(KnowledgeError::Backend)?
        {
            let existing = decode_record(&payload)?;
            if existing.id != id {
                return Err(KnowledgeError::Backend(
                    "record ID collision; no data changed".into(),
                ));
            }
        }
        Ok(point_id)
    }
}

impl Store for QdrantKnowledgeStore {
    fn profile(&self) -> Result<EmbeddingProfile, KnowledgeError> {
        Ok(self.profile.clone())
    }

    fn upsert(&mut self, record: Record, vector: Vec<f32>) -> Result<(), KnowledgeError> {
        crate::validate_record(&record)?;
        let id = self.checked_id(&record.id)?;
        let mut payload = Map::new();
        payload.insert("knowledge_format".into(), Value::from(1));
        payload.insert(
            "visibility".into(),
            Value::from(if record.public { "public" } else { "private" }),
        );
        payload.insert(
            "record".into(),
            serde_json::to_value(record).map_err(|e| KnowledgeError::Backend(e.to_string()))?,
        );
        // Record, access label and embedding are one engine update, no sidecar mapping.
        self.store
            .upsert(id, vector, payload)
            .map_err(KnowledgeError::Backend)
    }

    fn search(&self, vector: &[f32], options: SearchOptions) -> Result<Vec<Match>, KnowledgeError> {
        crate::validate_options(options)?;
        let filter = if options.scope == AccessScope::PublicOnly {
            Some(("visibility", "public"))
        } else {
            None
        };
        self.store
            .search_with_options(
                vector.to_vec(),
                options.top_k,
                filter,
                Some(options.threshold),
            )
            .map_err(KnowledgeError::Backend)?
            .into_iter()
            .map(|hit| {
                let record = decode_record(&hit.metadata)?;
                if point_id(&record.id) != hit.id {
                    return Err(KnowledgeError::InvalidStoreResult);
                }
                Ok(Match {
                    record,
                    similarity: hit.score,
                })
            })
            .collect()
    }

    fn remove(&mut self, id: &str) -> Result<(), KnowledgeError> {
        let id = self.checked_id(id)?;
        self.store.delete(id).map_err(KnowledgeError::Backend)
    }
    fn flush(&mut self) -> Result<(), KnowledgeError> {
        self.store.flush().map_err(KnowledgeError::Backend)
    }
}

fn point_id(id: &str) -> u64 {
    let hash = Sha256::digest(id.as_bytes());
    u64::from_be_bytes(hash[..8].try_into().expect("SHA-256 has eight bytes"))
}

fn decode_record(payload: &Map<String, Value>) -> Result<Record, KnowledgeError> {
    if payload.get("knowledge_format") != Some(&Value::from(1)) {
        return Err(KnowledgeError::InvalidStoreResult);
    }
    let record: Record = serde_json::from_value(
        payload
            .get("record")
            .cloned()
            .ok_or(KnowledgeError::InvalidStoreResult)?,
    )
    .map_err(|_| KnowledgeError::InvalidStoreResult)?;
    crate::validate_record(&record)?;
    let visibility = if record.public { "public" } else { "private" };
    if payload.get("visibility").and_then(Value::as_str) != Some(visibility) {
        return Err(KnowledgeError::InvalidStoreResult);
    }
    Ok(record)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn simulated_collision_blocks_overwrite_and_delete() {
        let directory = tempfile::tempdir().unwrap();
        let profile = EmbeddingProfile {
            id: "test".into(),
            dimension: 2,
        };
        let mut store = QdrantKnowledgeStore::open(directory.path(), profile).unwrap();
        let record = Record {
            id: "other-id".into(),
            document_id: "doc".into(),
            content: "keep".into(),
            source: crate::Source {
                title: "source".into(),
                location: None,
            },
            public: true,
        };
        let payload =
            serde_json::json!({"knowledge_format": 1, "visibility": "public", "record": record})
                .as_object()
                .unwrap()
                .clone();
        let id = point_id("requested-id");
        store
            .store
            .upsert(id, vec![1.0, 0.0], payload.clone())
            .unwrap();
        let mut replacement = record;
        replacement.id = "requested-id".into();
        assert!(store.upsert(replacement, vec![1.0, 0.0]).is_err());
        assert!(store.remove("requested-id").is_err());
        assert_eq!(store.store.read_metadata(id).unwrap(), Some(payload));
    }
}
