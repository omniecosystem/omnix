use omnix_knowledge::*;
use std::cell::Cell;

fn profile(id: &str) -> EmbeddingProfile {
    EmbeddingProfile {
        id: id.into(),
        dimension: 2,
    }
}
fn record(id: &str, public: bool) -> Record {
    Record {
        id: id.into(),
        document_id: "document-1".into(),
        content: "A document passage".into(),
        source: Source {
            title: "Source title".into(),
            location: Some("page:2".into()),
        },
        public,
    }
}
fn options(scope: AccessScope) -> SearchOptions {
    SearchOptions {
        top_k: 1,
        threshold: 0.0,
        scope,
    }
}

// In-memory contract double; persistence is tested by the Qdrant adapter tests.
#[derive(Default)]
struct MemoryStore {
    rows: Vec<(Record, Vec<f32>)>,
    flushed: bool,
    violate_filter: bool,
    fail_search: bool,
}
impl Store for MemoryStore {
    fn profile(&self) -> Result<EmbeddingProfile, KnowledgeError> {
        Ok(profile("weights-v1"))
    }
    fn upsert(&mut self, record: Record, vector: Vec<f32>) -> Result<(), KnowledgeError> {
        self.rows.retain(|(old, _)| old.id != record.id);
        self.rows.push((record, vector));
        self.flushed = false;
        Ok(())
    }
    fn search(&self, vector: &[f32], options: SearchOptions) -> Result<Vec<Match>, KnowledgeError> {
        if self.fail_search {
            return Err(KnowledgeError::Backend("search unavailable".into()));
        }
        let mut hits: Vec<_> = self
            .rows
            .iter()
            .filter(|(row, _)| {
                self.violate_filter || options.scope == AccessScope::LocalAll || row.public
            })
            .map(|(row, stored)| {
                let dot: f32 = vector.iter().zip(stored).map(|(a, b)| a * b).sum();
                let magnitude = |v: &[f32]| v.iter().map(|x| x * x).sum::<f32>().sqrt();
                Match {
                    record: row.clone(),
                    similarity: dot / (magnitude(vector) * magnitude(stored)),
                }
            })
            .filter(|hit| hit.similarity >= options.threshold)
            .collect();
        hits.sort_by(|a, b| b.similarity.total_cmp(&a.similarity));
        hits.truncate(options.top_k);
        Ok(hits)
    }
    fn remove(&mut self, id: &str) -> Result<(), KnowledgeError> {
        self.rows.retain(|(row, _)| row.id != id);
        self.flushed = false;
        Ok(())
    }
    fn flush(&mut self) -> Result<(), KnowledgeError> {
        self.flushed = true;
        Ok(())
    }
}

struct TestEmbedder {
    document_calls: Cell<usize>,
    query_calls: Cell<usize>,
    switch_on_embed: bool,
}
impl TestEmbedder {
    fn new() -> Self {
        Self {
            document_calls: Cell::new(0),
            query_calls: Cell::new(0),
            switch_on_embed: false,
        }
    }
}
impl Embedder for TestEmbedder {
    fn profile(&self) -> Result<EmbeddingProfile, KnowledgeError> {
        Ok(profile(
            if self.switch_on_embed && self.document_calls.get() > 0 {
                "weights-v2"
            } else {
                "weights-v1"
            },
        ))
    }
    fn embed_document(&self, _: &str) -> Result<Vec<f32>, KnowledgeError> {
        self.document_calls.set(self.document_calls.get() + 1);
        Ok(vec![1.0, 0.0])
    }
    fn embed_query(&self, _: &str) -> Result<Vec<f32>, KnowledgeError> {
        self.query_calls.set(self.query_calls.get() + 1);
        Ok(vec![1.0, 0.0])
    }
}

#[test]
fn text_operations_use_distinct_tasks_and_preserve_provenance() {
    let mut index = KnowledgeIndex::open(MemoryStore::default(), profile("weights-v1")).unwrap();
    let embedder = TestEmbedder::new();
    index.add_text(record("chunk-a", true), &embedder).unwrap();
    let hits = index
        .search_text("a question", &embedder, options(AccessScope::PublicOnly))
        .unwrap();
    assert_eq!(embedder.document_calls.get(), 1);
    assert_eq!(embedder.query_calls.get(), 1);
    assert_eq!(hits[0].record, record("chunk-a", true));
    assert_eq!(hits[0].similarity, 1.0);
    // The embedder remains usable: the index does not own or close it.
    drop(index);
    assert_eq!(embedder.profile().unwrap(), profile("weights-v1"));
}

#[test]
fn equal_dimensions_do_not_allow_another_embedding_space() {
    assert!(matches!(
        KnowledgeIndex::open(MemoryStore::default(), profile("weights-v2")),
        Err(KnowledgeError::IncompatibleProfile)
    ));
}

#[test]
fn provider_switch_is_rejected_before_storage_mutation() {
    let mut index = KnowledgeIndex::open(MemoryStore::default(), profile("weights-v1")).unwrap();
    let embedder = TestEmbedder {
        switch_on_embed: true,
        ..TestEmbedder::new()
    };
    assert_eq!(
        index.add_text(record("chunk-a", true), &embedder),
        Err(KnowledgeError::IncompatibleProfile)
    );
    assert!(index
        .search_vector(&[1.0, 0.0], options(AccessScope::LocalAll))
        .unwrap()
        .is_empty());
}

#[test]
fn public_filter_is_applied_before_top_k() {
    let mut index = KnowledgeIndex::open(MemoryStore::default(), profile("weights-v1")).unwrap();
    index
        .add_vector(record("private", false), vec![1.0, 0.0])
        .unwrap();
    index
        .add_vector(record("public", true), vec![0.8, 0.6])
        .unwrap();
    let hits = index
        .search_vector(&[1.0, 0.0], options(AccessScope::PublicOnly))
        .unwrap();
    assert_eq!(hits[0].record.id, "public");
    let local = index
        .search_vector(&[1.0, 0.0], options(AccessScope::LocalAll))
        .unwrap();
    assert_eq!(local[0].record.id, "private");
}

#[test]
fn backend_access_violation_fails_closed() {
    let store = MemoryStore {
        violate_filter: true,
        ..MemoryStore::default()
    };
    let mut index = KnowledgeIndex::open(store, profile("weights-v1")).unwrap();
    index
        .add_vector(record("private", false), vec![1.0, 0.0])
        .unwrap();
    assert_eq!(
        index.search_vector(&[1.0, 0.0], options(AccessScope::PublicOnly)),
        Err(KnowledgeError::InvalidStoreResult)
    );
}

#[test]
fn invalid_vectors_and_limits_are_rejected() {
    let mut index = KnowledgeIndex::open(MemoryStore::default(), profile("weights-v1")).unwrap();
    for vector in [
        vec![1.0],
        vec![0.0, 0.0],
        vec![f32::NAN, 1.0],
        vec![1.0, f32::INFINITY],
    ] {
        assert!(index
            .add_vector(record("bad", true), vector.clone())
            .is_err());
        assert!(index
            .search_vector(&vector, options(AccessScope::LocalAll))
            .is_err());
    }
    for bad in [
        SearchOptions {
            top_k: 0,
            ..options(AccessScope::LocalAll)
        },
        SearchOptions {
            top_k: 101,
            ..options(AccessScope::LocalAll)
        },
        SearchOptions {
            threshold: f32::NAN,
            ..options(AccessScope::LocalAll)
        },
    ] {
        assert!(index.search_vector(&[1.0, 0.0], bad).is_err());
    }
}

#[test]
fn vector_only_upsert_replaces_stable_id_and_remove_is_idempotent() {
    let mut index = KnowledgeIndex::open(MemoryStore::default(), profile("weights-v1")).unwrap();
    index
        .add_vector(record("same-id", true), vec![1.0, 0.0])
        .unwrap();
    let mut replacement = record("same-id", true);
    replacement.content = "Updated passage".into();
    index
        .add_vector(replacement.clone(), vec![1.0, 0.0])
        .unwrap();
    assert_eq!(
        index
            .search_vector(&[1.0, 0.0], options(AccessScope::LocalAll))
            .unwrap()[0]
            .record,
        replacement
    );
    index.remove("same-id").unwrap();
    index.remove("same-id").unwrap();
    index.flush().unwrap();
    assert!(index
        .search_vector(&[1.0, 0.0], options(AccessScope::LocalAll))
        .unwrap()
        .is_empty());
}

#[test]
fn backend_failure_is_not_reported_as_empty_search() {
    let store = MemoryStore {
        fail_search: true,
        ..MemoryStore::default()
    };
    let index = KnowledgeIndex::open(store, profile("weights-v1")).unwrap();
    assert!(matches!(
        index.search_vector(&[1.0, 0.0], options(AccessScope::LocalAll)),
        Err(KnowledgeError::Backend(_))
    ));
}

#[test]
fn document_ingestion_embeds_each_chunk_and_preserves_source() {
    let mut index = KnowledgeIndex::open(MemoryStore::default(), profile("weights-v1")).unwrap();
    let embedder = TestEmbedder::new();
    let mut document = record("imported", true);
    document.content = "one two three four five six seven eight".into();
    let count = index
        .add_text_document(
            document,
            &embedder,
            text::TextChunkOptions {
                characters: 12,
                overlap: 2,
            },
        )
        .unwrap();
    assert!(count > 1);
    assert_eq!(embedder.document_calls.get(), count);
    let hits = index
        .search_vector(
            &[1.0, 0.0],
            SearchOptions {
                top_k: 100,
                ..options(AccessScope::PublicOnly)
            },
        )
        .unwrap();
    assert_eq!(hits.len(), count);
    assert!(hits
        .iter()
        .all(|hit| hit.record.document_id == "document-1"
            && hit.record.source.title == "Source title"));
}

#[test]
fn document_profile_failure_does_not_write_any_chunks() {
    let mut index = KnowledgeIndex::open(MemoryStore::default(), profile("weights-v1")).unwrap();
    let embedder = TestEmbedder {
        switch_on_embed: true,
        ..TestEmbedder::new()
    };
    assert_eq!(
        index.add_text_document(
            record("imported", true),
            &embedder,
            text::TextChunkOptions::default()
        ),
        Err(KnowledgeError::IncompatibleProfile)
    );
    assert!(index
        .search_vector(&[1.0, 0.0], options(AccessScope::LocalAll))
        .unwrap()
        .is_empty());
}
