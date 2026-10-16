// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::Path;

use qdrant_edge::{
    Condition, Distance, EdgeConfigBuilder, EdgeShard, EdgeVectorParamsBuilder, FieldCondition,
    Filter, NamedQuery, Payload, PointId, PointInsertOperations, PointOperations,
    PointStructPersisted, QueryEnum, QueryRequestBuilder, RetrieveRequestBuilder, ScoringQuery,
    UpdateOperation, VectorInternal, VectorStructInternal, VectorStructPersisted,
    WithPayloadInterface,
};
use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

const HEADER: &str = "omnix-vector-profile.json";
const LOCK: &str = ".omnix-vector-lock";

/// Identity of an embedding space; dimensions alone do not establish compatibility.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct VectorProfile {
    pub id: String,
    pub dimension: usize,
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Header {
    format: u32,
    metric: String,
    profile: VectorProfile,
}

/// An owned result; no engine pointers or borrowed payloads escape Storage.
#[derive(Debug, Serialize)]
pub struct VectorHit {
    pub id: u64,
    pub score: f32,
    pub metadata: Map<String, Value>,
}

/// Native cosine vector storage. Embedding execution belongs to Core/Knowledge.
/// Explicit `flush` is required for durable writes. No engine is selected by default.
pub struct QdrantStore {
    shard: EdgeShard,
    profile: VectorProfile,
    vector_name: String,
    // Declared last: the shard is dropped before the exclusive directory lease.
    _lease: File,
}

impl QdrantStore {
    pub fn open(path: &Path, profile: VectorProfile) -> Result<Self, String> {
        if !path.is_absolute() || profile.id.trim().is_empty() || profile.dimension == 0 {
            return Err("An absolute directory and nonempty embedding profile are required".into());
        }
        if path.exists()
            && std::fs::symlink_metadata(path)
                .map_err(error)?
                .file_type()
                .is_symlink()
        {
            return Err("A vector-store directory must not be a symbolic link".into());
        }
        std::fs::create_dir_all(path).map_err(error)?;
        for name in [HEADER, LOCK, "shard"] {
            if let Ok(metadata) = std::fs::symlink_metadata(path.join(name)) {
                if metadata.file_type().is_symlink() {
                    return Err("Vector-store state must not contain symbolic links".into());
                }
            }
        }
        if !path.join(HEADER).exists() {
            for entry in std::fs::read_dir(path).map_err(error)? {
                if entry.map_err(error)?.file_name() != LOCK {
                    return Err("Refusing to adopt a nonempty unowned vector directory".into());
                }
            }
        }
        let mut options = OpenOptions::new();
        options.read(true).write(true).create(true).truncate(false);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let lease = options.open(path.join(LOCK)).map_err(error)?;
        lease.try_lock().map_err(error)?;
        let header_path = path.join(HEADER);
        let existing = header_path.exists();
        let vector_name;
        if existing {
            let header: Header =
                serde_json::from_reader(File::open(&header_path).map_err(error)?).map_err(error)?;
            if !matches!(header.format, 1 | 2)
                || header.metric != "cosine"
                || header.profile != profile
            {
                return Err("Vector-store format, metric or embedding profile mismatch".into());
            }
            // Preserve the vector name in existing stores. New stores keep the
            // logical identity in the header, never in an engine filename.
            vector_name = if header.format == 1 {
                profile.id.clone()
            } else {
                "embedding".into()
            };
        } else {
            vector_name = "embedding".into();
            let mut header_file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&header_path)
                .map_err(error)?;
            let header = Header {
                format: 2,
                metric: "cosine".into(),
                profile: profile.clone(),
            };
            header_file
                .write_all(&serde_json::to_vec(&header).map_err(error)?)
                .map_err(error)?;
            header_file.sync_all().map_err(error)?;
        }
        let config = EdgeConfigBuilder::new()
            .vector(
                vector_name.clone(),
                EdgeVectorParamsBuilder::new(profile.dimension, Distance::Cosine).build(),
            )
            .build();
        let shard_path = path.join("shard");
        if !existing {
            std::fs::create_dir(&shard_path).map_err(error)?;
        }
        // Windows canonicalization preserves the extended-length prefix. Pass it
        // through to the engine, including its atomic temporary-file writes.
        let shard_path = std::fs::canonicalize(&shard_path).map_err(error)?;
        let shard = if existing {
            EdgeShard::load(&shard_path, Some(config))
        } else {
            EdgeShard::new(&shard_path, config)
        }
        .map_err(error)?;
        Ok(Self {
            shard,
            profile,
            vector_name,
            _lease: lease,
        })
    }

    fn validate(&self, vector: &[f32]) -> Result<(), String> {
        if vector.len() != self.profile.dimension || vector.iter().any(|value| !value.is_finite()) {
            return Err("Vector dimension mismatch or non-finite component".into());
        }
        if vector.iter().all(|value| *value == 0.0) {
            return Err("A cosine vector must have nonzero magnitude".into());
        }
        Ok(())
    }

    pub fn upsert(
        &self,
        id: u64,
        vector: Vec<f32>,
        metadata: Map<String, Value>,
    ) -> Result<(), String> {
        self.validate(&vector)?;
        let point = PointStructPersisted {
            id: PointId::NumId(id),
            vector: VectorStructPersisted::from(VectorStructInternal::Named(
                [(self.vector_name.clone(), VectorInternal::from(vector))]
                    .into_iter()
                    .collect(),
            )),
            payload: Some(Payload::from(metadata)),
        };
        self.shard
            .update(UpdateOperation::PointOperation(
                PointOperations::UpsertPoints(PointInsertOperations::PointsList(vec![point])),
            ))
            .map_err(error)
    }

    pub fn search(&self, vector: Vec<f32>, limit: usize) -> Result<Vec<VectorHit>, String> {
        self.search_inner(vector, limit, None, None)
    }

    /// Match one top-level string metadata field before ranking vectors.
    pub fn search_filtered(
        &self,
        vector: Vec<f32>,
        limit: usize,
        field: &str,
        value: &str,
    ) -> Result<Vec<VectorHit>, String> {
        self.search_with_options(vector, limit, Some((field, value)), None)
    }

    /// Apply metadata and score restrictions inside the engine before top-k.
    pub fn search_with_options(
        &self,
        vector: Vec<f32>,
        limit: usize,
        metadata_filter: Option<(&str, &str)>,
        threshold: Option<f32>,
    ) -> Result<Vec<VectorHit>, String> {
        let Some((field, value)) = metadata_filter else {
            return self.search_inner(vector, limit, None, threshold);
        };
        if field.trim().is_empty()
            || field.contains('.')
            || field.contains('[')
            || field.contains(']')
        {
            return Err("Metadata filtering requires a top-level field name".into());
        }
        let filter = Filter {
            must: Some(vec![Condition::Field(FieldCondition::new_match(
                field
                    .parse()
                    .map_err(|_| "Invalid metadata field name".to_string())?,
                value.to_owned().into(),
            ))]),
            ..Default::default()
        };
        self.search_inner(vector, limit, Some(filter), threshold)
    }

    fn search_inner(
        &self,
        vector: Vec<f32>,
        limit: usize,
        filter: Option<Filter>,
        threshold: Option<f32>,
    ) -> Result<Vec<VectorHit>, String> {
        self.validate(&vector)?;
        if limit == 0 || limit > 1000 {
            return Err("Search limit must be between 1 and 1000".into());
        }
        let mut request = QueryRequestBuilder::new(limit)
            .query(ScoringQuery::Vector(QueryEnum::Nearest(NamedQuery {
                using: Some(self.vector_name.clone()),
                query: vector.into(),
            })))
            .with_payload(WithPayloadInterface::Bool(true));
        if let Some(filter) = filter {
            request = request.filter(filter);
        }
        if let Some(threshold) = threshold {
            if !threshold.is_finite() || !(-1.0..=1.0).contains(&threshold) {
                return Err("Invalid cosine threshold".into());
            }
            request = request.score_threshold(threshold);
        }
        self.shard
            .query(request.build())
            .map_err(error)?
            .into_iter()
            .map(|point| {
                let PointId::NumId(id) = point.id else {
                    return Err("Unexpected external point ID".into());
                };
                Ok(VectorHit {
                    id,
                    score: point.score,
                    metadata: point.payload.unwrap_or_default().0,
                })
            })
            .collect()
    }

    /// Read owned metadata without requiring an embedding query.
    pub fn read_metadata(&self, id: u64) -> Result<Option<Map<String, Value>>, String> {
        let points = self
            .shard
            .retrieve(
                RetrieveRequestBuilder::new(vec![PointId::NumId(id)])
                    .with_payload(WithPayloadInterface::Bool(true))
                    .build(),
            )
            .map_err(error)?;
        Ok(points
            .into_iter()
            .next()
            .map(|point| point.payload.unwrap_or_default().0))
    }

    pub fn delete(&self, id: u64) -> Result<(), String> {
        self.shard
            .update(UpdateOperation::PointOperation(
                PointOperations::DeletePoints {
                    ids: vec![PointId::NumId(id)],
                },
            ))
            .map_err(error)
    }

    pub fn flush(&self) -> Result<(), String> {
        self.shard.flush().map_err(error)
    }

    /// Removes points while retaining the immutable embedding profile.
    pub fn clear(&self) -> Result<(), String> {
        self.shard
            .update(UpdateOperation::PointOperation(
                PointOperations::DeletePointsByFilter(Filter::default()),
            ))
            .map_err(error)
    }
}

fn error(error: impl std::fmt::Display) -> String {
    error.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn profile() -> VectorProfile {
        VectorProfile {
            id: "test-space-v1".into(),
            dimension: 3,
        }
    }

    #[test]
    fn logical_profile_is_not_used_as_a_filename() {
        let dir = tempfile::tempdir().unwrap();
        let profile = VectorProfile {
            id: "embedding:weights/task?version=2".into(),
            dimension: 3,
        };
        let store = QdrantStore::open(dir.path(), profile.clone()).unwrap();
        store.upsert(1, vec![1.0, 0.0, 0.0], Map::new()).unwrap();
        store.flush().unwrap();
        drop(store);
        let store = QdrantStore::open(dir.path(), profile).unwrap();
        assert_eq!(store.search(vec![1.0, 0.0, 0.0], 1).unwrap()[0].id, 1);
    }

    #[test]
    fn long_directory_and_vector_name_survive_reopen() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("application-support-".repeat(5));
        let profile = VectorProfile {
            id: format!("knowledge-v1-{}", "b".repeat(64)),
            dimension: 3,
        };
        let store = QdrantStore::open(&path, profile.clone()).unwrap();
        store.upsert(1, vec![1.0, 0.0, 0.0], Map::new()).unwrap();
        store.flush().unwrap();
        drop(store);
        let store = QdrantStore::open(&path, profile).unwrap();
        assert_eq!(store.search(vec![1.0, 0.0, 0.0], 1).unwrap()[0].id, 1);
    }

    #[cfg(windows)]
    #[test]
    fn reopens_state_left_by_legacy_long_path_failure() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("application-support-".repeat(5));
        let profile = VectorProfile {
            id: format!("knowledge-v1-{}", "b".repeat(64)),
            dimension: 3,
        };
        std::fs::create_dir_all(path.join("shard")).unwrap();
        let header = Header {
            format: 1,
            metric: "cosine".into(),
            profile: profile.clone(),
        };
        std::fs::write(path.join(HEADER), serde_json::to_vec(&header).unwrap()).unwrap();
        let config = EdgeConfigBuilder::new()
            .vector(
                profile.id.clone(),
                EdgeVectorParamsBuilder::new(3, Distance::Cosine).build(),
            )
            .build();
        // Reproduce the previous open implementation, not the fixed adapter.
        assert!(EdgeShard::new(&path.join("shard"), config).is_err());
        let store = QdrantStore::open(&path, profile.clone()).unwrap();
        store.upsert(1, vec![1.0, 0.0, 0.0], Map::new()).unwrap();
        store.flush().unwrap();
        drop(store);
        let store = QdrantStore::open(&path, profile).unwrap();
        assert_eq!(store.search(vec![1.0, 0.0, 0.0], 1).unwrap()[0].id, 1);
    }

    #[test]
    fn durable_vectors_metadata_delete_and_profile_isolation() {
        let dir = tempfile::tempdir().unwrap();
        let store = QdrantStore::open(dir.path(), profile()).unwrap();
        let metadata = serde_json::json!({"source": "fixture"})
            .as_object()
            .unwrap()
            .clone();
        store
            .upsert(1, vec![1.0, 0.0, 0.0], metadata.clone())
            .unwrap();
        store.flush().unwrap();
        assert!(QdrantStore::open(dir.path(), profile()).is_err());
        drop(store);
        let mut other = profile();
        other.id = "different-weights-same-dimension".into();
        assert!(QdrantStore::open(dir.path(), other).is_err());
        let store = QdrantStore::open(dir.path(), profile()).unwrap();
        let result = store.search(vec![1.0, 0.0, 0.0], 1).unwrap();
        assert_eq!(result[0].id, 1);
        assert_eq!(result[0].metadata, metadata);
        store.delete(1).unwrap();
        store.flush().unwrap();
        drop(store);
        let store = QdrantStore::open(dir.path(), profile()).unwrap();
        assert!(store.search(vec![1.0, 0.0, 0.0], 1).unwrap().is_empty());
    }

    #[test]
    fn invalid_vectors_never_reach_the_engine() {
        let dir = tempfile::tempdir().unwrap();
        let store = QdrantStore::open(dir.path(), profile()).unwrap();
        for vector in [
            vec![1.0],
            vec![f32::NAN, 0.0, 1.0],
            vec![f32::INFINITY, 0.0, 1.0],
            vec![0.0; 3],
        ] {
            assert!(store.upsert(1, vector, Map::new()).is_err());
        }
        assert!(store.search(vec![1.0, 0.0, 0.0], 0).is_err());
    }

    #[test]
    fn metadata_filtering_happens_inside_the_engine() {
        let dir = tempfile::tempdir().unwrap();
        let store = QdrantStore::open(dir.path(), profile()).unwrap();
        for (id, group) in [(1, "private"), (2, "shared")] {
            let metadata = serde_json::json!({"group": group})
                .as_object()
                .unwrap()
                .clone();
            store.upsert(id, vec![1.0, 0.0, 0.0], metadata).unwrap();
        }
        let result = store
            .search_filtered(vec![1.0, 0.0, 0.0], 2, "group", "shared")
            .unwrap();
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].id, 2);
        assert!(store
            .search_filtered(vec![1.0, 0.0, 0.0], 2, "group", "missing")
            .unwrap()
            .is_empty());
    }

    #[test]
    fn damaged_or_future_profile_headers_fail_closed() {
        let dir = tempfile::tempdir().unwrap();
        let store = QdrantStore::open(dir.path(), profile()).unwrap();
        store.flush().unwrap();
        drop(store);
        let path = dir.path().join(HEADER);
        let header =
            serde_json::json!({"format": 99, "metric": "cosine", "profile": profile()}).to_string();
        std::fs::write(&path, &header).unwrap();
        assert!(QdrantStore::open(dir.path(), profile()).is_err());
        assert_eq!(std::fs::read_to_string(&path).unwrap(), header);
        std::fs::write(&path, "truncated").unwrap();
        assert!(QdrantStore::open(dir.path(), profile()).is_err());
        assert_eq!(std::fs::read_to_string(path).unwrap(), "truncated");
    }

    #[test]
    fn never_adopts_or_deletes_foreign_data() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("valuable.txt");
        std::fs::write(&file, "keep me").unwrap();
        assert!(QdrantStore::open(dir.path(), profile()).is_err());
        assert_eq!(std::fs::read_to_string(file).unwrap(), "keep me");
        assert!(!dir.path().join(HEADER).exists());
    }
}
