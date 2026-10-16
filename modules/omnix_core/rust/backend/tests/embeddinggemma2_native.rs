// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
#![cfg(all(feature = "litertlm-embedding-engine", target_os = "windows"))]
use omnix_core::{embedding::*, litertlm_embedding::LiteRtLmEmbeddingModel, CoreError};
use std::path::PathBuf;
fn open() -> Result<LiteRtLmEmbeddingModel, Box<dyn std::error::Error>> {
    let library = PathBuf::from(std::env::var("OMNIX_EMBEDDING2_LIBRARY")?);
    let model = PathBuf::from(std::env::var("OMNIX_EMBEDDING2_MODEL")?);
    Ok(unsafe { LiteRtLmEmbeddingModel::from_library(&library, &model)? })
}
fn cosine(a: &[f32], b: &[f32]) -> f32 {
    a.iter().zip(b).map(|(a, b)| a * b).sum::<f32>()
        / (a.iter().map(|v| v * v).sum::<f32>() * b.iter().map(|v| v * v).sum::<f32>()).sqrt()
}
#[test]
#[ignore = "requires verified v0.18 runtime and EmbeddingGemma 2 text bundle"]
fn admitted_native_encoder_rejects_contention_and_recovers(
) -> Result<(), Box<dyn std::error::Error>> {
    use omnix_core::execution::ExecutionAdmission;
    use std::{sync::atomic::AtomicBool, time::Duration};
    let gate = ExecutionAdmission::new(1, 0)?;
    let mut model = AdmittedEmbeddingModel::load(gate.clone(), Duration::ZERO, || {
        assert_eq!(gate.snapshot().unwrap().active, 1);
        open().map_err(|error| CoreError::BackendFailure(error.to_string()))
    })?;
    let profile = model.profile().clone();
    let permit = gate.acquire(&AtomicBool::new(false), Duration::ZERO)?;
    assert!(
        matches!(model.generate_embedding("router reset", EmbeddingTask::RetrievalQuery), Err(CoreError::BackendFailure(code)) if code == "execution-busy")
    );
    drop(permit);
    let vector = model.generate_embedding("router reset", EmbeddingTask::RetrievalQuery)?;
    validate_final(&vector, profile.dimension)?;
    assert_eq!(model.profile(), &profile);
    assert_eq!(gate.snapshot()?.active, 0);
    Ok(())
}
#[test]
#[ignore = "requires verified v0.18 runtime and EmbeddingGemma 2 text bundle"]
fn multilingual_ranking_normalization_tasks_and_reopen() -> Result<(), Box<dyn std::error::Error>> {
    let mut model = open()?;
    let profile = model.profile().clone();
    let question = "How do I reset my router?";
    let query = model.generate_embedding(question, EmbeddingTask::RetrievalQuery)?;
    let repeated = model.generate_embedding(question, EmbeddingTask::RetrievalQuery)?;
    let relevant = model.generate_embedding(
        "Hold the router reset button for ten seconds and wait for its light to turn blue.",
        EmbeddingTask::RetrievalDocument,
    )?;
    let unrelated = model.generate_embedding(
        "Mix bananas, strawberries and yogurt to make a fruit smoothie.",
        EmbeddingTask::RetrievalDocument,
    )?;
    let french = model.generate_embedding(
        "Comment réinitialiser mon routeur Wi-Fi ?",
        EmbeddingTask::RetrievalQuery,
    )?;
    for vector in [&query, &relevant, &unrelated, &french] {
        validate_final(vector, 768)?;
        assert!((vector.iter().map(|v| v * v).sum::<f32>().sqrt() - 1.0).abs() < 0.001);
    }
    println!(
        "English: relevant {:.4}, unrelated {:.4}; French: relevant {:.4}, unrelated {:.4}",
        cosine(&query, &relevant),
        cosine(&query, &unrelated),
        cosine(&french, &relevant),
        cosine(&french, &unrelated)
    );
    assert!(cosine(&query, &relevant) > cosine(&query, &unrelated) + 0.05);
    assert!(cosine(&french, &relevant) > cosine(&french, &unrelated) + 0.05);
    assert!(cosine(&query, &repeated) > 0.9999);
    let document = model.generate_embedding(question, EmbeddingTask::RetrievalDocument)?;
    assert!(cosine(&query, &document) < 0.9999);
    assert_eq!(
        model.generate_embedding(" ", EmbeddingTask::RetrievalQuery),
        Err(CoreError::InvalidRequest)
    );
    assert!(model
        .generate_embedding(&"router ".repeat(9000), EmbeddingTask::RetrievalQuery)
        .is_err());
    drop(model);
    let mut model = open()?;
    assert_eq!(model.profile(), &profile);
    assert!(
        cosine(
            &query,
            &model.generate_embedding(question, EmbeddingTask::RetrievalQuery)?
        ) > 0.9999
    );
    Ok(())
}
