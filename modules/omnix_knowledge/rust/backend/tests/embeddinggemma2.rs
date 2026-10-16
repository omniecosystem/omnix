// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
#![cfg(all(
    feature = "qdrant",
    feature = "core-litertlm-embedding-engine",
    target_os = "windows"
))]

use omnix_core::litertlm_embedding::LiteRtLmEmbeddingModel;
use omnix_knowledge::{core::CoreEmbedder, qdrant::QdrantKnowledgeStore, *};
use std::path::PathBuf;

#[test]
#[ignore = "requires verified OMNIX_EMBEDDING2_MODEL and LIBRARY"]
fn native_text_index_reopen_and_attributed_retrieval() -> Result<(), Box<dyn std::error::Error>> {
    let library = PathBuf::from(std::env::var("OMNIX_EMBEDDING2_LIBRARY")?);
    let model = PathBuf::from(std::env::var("OMNIX_EMBEDDING2_MODEL")?);
    let mut model = unsafe { LiteRtLmEmbeddingModel::from_library(&library, &model)? };
    let embedder = CoreEmbedder::new(&mut model);
    let profile = embedder.profile()?;
    let directory = tempfile::tempdir()?;
    let mut index = KnowledgeIndex::open(
        QdrantKnowledgeStore::open(directory.path(), profile.clone())?,
        profile.clone(),
    )?;
    // Synthetic passages, including a fake private credential for access filtering.
    for (id,content,public) in [
        ("router-guide", "To reset your Wi-Fi router, hold its reset button for ten seconds, then reconnect to the network.",true),
        ("recipe", "Bananas and strawberries can be blended with yogurt to make a fruit smoothie.",true),
        ("private-password", "The private Wi-Fi router password is personal-secret.",false),
    ] {
        index.add_text(Record {id:id.into(),document_id:id.into(),content:content.into(),source:Source {title:id.into(),location:Some("page:1".into())},public},&embedder)?;
    }
    index.flush()?;
    drop(index);
    let index = KnowledgeIndex::open(
        QdrantKnowledgeStore::open(directory.path(), profile.clone())?,
        profile.clone(),
    )?;
    let hits = index.search_text(
        "How do I reset my Wi-Fi router?",
        &embedder,
        SearchOptions {
            top_k: 1,
            threshold: 0.0,
            scope: AccessScope::PublicOnly,
        },
    )?;
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].record.id, "router-guide");
    assert_eq!(hits[0].record.source.title, "router-guide");
    println!(
        "Real Core embeddings + reopened Qdrant: {} (score {:.4})",
        hits[0].record.source.title, hits[0].similarity
    );
    // Scope is host policy. A remote caller is never given LocalAll by default.
    assert!(hits.iter().all(|hit| hit.record.public));
    drop(index);
    let incompatible = EmbeddingProfile {
        id: "different-weights-same-dimension".into(),
        dimension: profile.dimension,
    };
    assert!(QdrantKnowledgeStore::open(directory.path(), incompatible).is_err());
    Ok(())
}
