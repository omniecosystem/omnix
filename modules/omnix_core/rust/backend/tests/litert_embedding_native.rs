// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
#![cfg(all(feature = "litertlm-embeddings", target_os = "windows"))]

use omnix_core::{embedding::*, litert_embedding::*, CoreError};
use std::path::PathBuf;

fn open() -> Result<LiteRtEmbeddingModel, Box<dyn std::error::Error>> {
    let library = PathBuf::from(std::env::var("OMNIX_EMBEDDING_LIBRARY")?);
    let model = PathBuf::from(std::env::var("OMNIX_EMBEDDING_MODEL")?);
    let tokenizer = PathBuf::from(std::env::var("OMNIX_EMBEDDING_TOKENIZER")?);
    // Operator supplies trusted pinned C-ABI artifacts, no downloads.
    Ok(unsafe {
        LiteRtEmbeddingModel::from_library(
            &library,
            &model,
            &tokenizer,
            LiteRtEmbeddingConvention::LegacyGeckoRetrieval,
        )?
    })
}

fn cosine(a: &[f32], b: &[f32]) -> f32 {
    let dot: f32 = a.iter().zip(b).map(|(a, b)| a * b).sum();
    let norm_a: f32 = a.iter().map(|v| v * v).sum();
    let norm_b: f32 = b.iter().map(|v| v * v).sum();
    dot / (norm_a * norm_b).sqrt()
}

#[test]
#[ignore = "requires trusted OMNIX_EMBEDDING_LIBRARY, MODEL and TOKENIZER"]
fn real_query_document_vectors_reopen_and_semantic_ranking(
) -> Result<(), Box<dyn std::error::Error>> {
    let mut model = open()?;
    assert_eq!(
        model.generate_embedding("  ", EmbeddingTask::RetrievalQuery),
        Err(CoreError::InvalidRequest)
    );
    let profile = model.profile().clone();
    let question = "How do I reset my Wi-Fi router?";
    let query = model.generate_embedding(question, EmbeddingTask::RetrievalQuery)?;
    let repeated = model.generate_embedding(question, EmbeddingTask::RetrievalQuery)?;
    let document=model.generate_embedding("To reset your Wi-Fi router, hold its reset button for ten seconds, then reconnect to the network.",EmbeddingTask::RetrievalDocument)?;
    let unrelated = model.generate_embedding(
        "Bananas and strawberries can be blended with yogurt to make a fruit smoothie.",
        EmbeddingTask::RetrievalDocument,
    )?;
    assert_eq!(query.len(), profile.dimension);
    assert!(cosine(&query, &repeated) > 0.9999);
    let relevant_score = cosine(&query, &document);
    let unrelated_score = cosine(&query, &unrelated);
    println!("dimension={}, input_width={}, relevant={relevant_score:.4}, unrelated={unrelated_score:.4}",profile.dimension,model.input_sequence_length());
    assert!(
        relevant_score > unrelated_score + 0.05,
        "semantic ranking failed"
    );
    let as_document = model.generate_embedding(question, EmbeddingTask::RetrievalDocument)?;
    assert!(
        query
            .iter()
            .zip(&as_document)
            .any(|(a, b)| (a - b).abs() > 0.00001),
        "task convention was ignored"
    );
    assert_eq!(
        model.generate_embedding(
            &"router ".repeat(model.input_sequence_length() + 1),
            EmbeddingTask::RetrievalQuery
        ),
        Err(CoreError::InvalidRequest)
    );
    drop(model);
    let mut reopened = open()?;
    assert_eq!(reopened.profile(), &profile);
    let after = reopened.generate_embedding(question, EmbeddingTask::RetrievalQuery)?;
    assert!(cosine(&query, &after) > 0.9999);
    Ok(())
}
