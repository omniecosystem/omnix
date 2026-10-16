#![cfg(feature = "qdrant")]
use omnix_knowledge::{qdrant::QdrantKnowledgeStore, *};

fn profile() -> EmbeddingProfile {
    EmbeddingProfile {
        // Public profiles can contain URL punctuation and Unicode.
        id: "fixture:weights/v1-é".into(),
        dimension: 3,
    }
}
fn record(id: &str, public: bool) -> Record {
    Record {
        id: id.into(),
        document_id: "document-A".into(),
        content: "A useful passage".into(),
        source: Source {
            title: "Document A".into(),
            location: Some("page:4".into()),
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
fn open(path: &std::path::Path) -> KnowledgeIndex<QdrantKnowledgeStore> {
    KnowledgeIndex::open(
        QdrantKnowledgeStore::open(path, profile()).unwrap(),
        profile(),
    )
    .unwrap()
}

#[test]
fn real_storage_reopens_attributed_string_ids_filters_before_ranking_and_deletes() {
    let directory = tempfile::tempdir().unwrap();
    let mut index = open(directory.path());
    let public = record("document-A/chunk-é", true);
    index
        .add_vector(record("private-high-score", false), vec![1.0, 0.0, 0.0])
        .unwrap();
    index
        .add_vector(public.clone(), vec![0.8, 0.6, 0.0])
        .unwrap();
    index.flush().unwrap();
    drop(index);
    let mut index = open(directory.path());
    let hits = index
        .search_vector(&[1.0, 0.0, 0.0], options(AccessScope::PublicOnly))
        .unwrap();
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].record, public);
    assert!((hits[0].similarity - 0.8).abs() < 0.001);
    assert_eq!(
        index
            .search_vector(&[1.0, 0.0, 0.0], options(AccessScope::LocalAll))
            .unwrap()[0]
            .record
            .id,
        "private-high-score"
    );
    assert!(index
        .search_vector(
            &[1.0, 0.0, 0.0],
            SearchOptions {
                threshold: 0.9,
                ..options(AccessScope::PublicOnly)
            }
        )
        .unwrap()
        .is_empty());
    index.remove(&public.id).unwrap();
    index.remove(&public.id).unwrap();
    index.flush().unwrap();
    drop(index);
    assert!(open(directory.path())
        .search_vector(&[1.0, 0.0, 0.0], options(AccessScope::PublicOnly))
        .unwrap()
        .is_empty());
}

#[test]
fn same_id_update_changes_content_and_visibility_durably() {
    let directory = tempfile::tempdir().unwrap();
    let mut index = open(directory.path());
    index
        .add_vector(record("stable-id", true), vec![1.0, 0.0, 0.0])
        .unwrap();
    let mut updated = record("stable-id", false);
    updated.content = "Updated private content".into();
    index
        .add_vector(updated.clone(), vec![1.0, 0.0, 0.0])
        .unwrap();
    index.flush().unwrap();
    drop(index);
    let index = open(directory.path());
    assert!(index
        .search_vector(&[1.0, 0.0, 0.0], options(AccessScope::PublicOnly))
        .unwrap()
        .is_empty());
    assert_eq!(
        index
            .search_vector(&[1.0, 0.0, 0.0], options(AccessScope::LocalAll))
            .unwrap()[0]
            .record,
        updated
    );
}

#[test]
fn wrong_profile_and_foreign_directory_preserve_existing_data() {
    let directory = tempfile::tempdir().unwrap();
    let mut index = open(directory.path());
    index
        .add_vector(record("preserved", true), vec![1.0, 0.0, 0.0])
        .unwrap();
    index.flush().unwrap();
    drop(index);
    let other = EmbeddingProfile {
        id: "different-weights".into(),
        ..profile()
    };
    assert!(QdrantKnowledgeStore::open(directory.path(), other).is_err());
    assert_eq!(
        open(directory.path())
            .search_vector(&[1.0, 0.0, 0.0], options(AccessScope::PublicOnly))
            .unwrap()[0]
            .record
            .id,
        "preserved"
    );
    let foreign = tempfile::tempdir().unwrap();
    std::fs::write(foreign.path().join("existing.txt"), "keep").unwrap();
    assert!(QdrantKnowledgeStore::open(foreign.path(), profile()).is_err());
    assert_eq!(
        std::fs::read_to_string(foreign.path().join("existing.txt")).unwrap(),
        "keep"
    );
}
