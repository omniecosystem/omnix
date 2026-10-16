// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
#![cfg(all(feature = "litertlm-embedding-engine", target_os = "windows"))]
use omnix_core::{embedding::*, litertlm_embedding::LiteRtLmEmbeddingModel};
use std::path::PathBuf;

fn wav() -> Vec<u8> {
    let samples = 16000u32;
    let size = samples * 2;
    let mut bytes = Vec::new();
    bytes.extend(b"RIFF");
    bytes.extend((36 + size).to_le_bytes());
    bytes.extend(b"WAVEfmt ");
    bytes.extend(16u32.to_le_bytes());
    bytes.extend(1u16.to_le_bytes());
    bytes.extend(1u16.to_le_bytes());
    bytes.extend(16000u32.to_le_bytes());
    bytes.extend(32000u32.to_le_bytes());
    bytes.extend(2u16.to_le_bytes());
    bytes.extend(16u16.to_le_bytes());
    bytes.extend(b"data");
    bytes.extend(size.to_le_bytes());
    for n in 0..samples {
        let value = ((n as f32 * 440.0 * std::f32::consts::TAU / 16000.0).sin() * 3000.0) as i16;
        bytes.extend(value.to_le_bytes());
    }
    bytes
}

#[test]
#[ignore = "requires verified full bundle, v0.18 CPU runtime and a test image"]
fn native_text_image_audio_mixed_and_frame_sequence() -> Result<(), Box<dyn std::error::Error>> {
    let library = PathBuf::from(std::env::var("OMNIX_EMBEDDING2_LIBRARY")?);
    let model_path = PathBuf::from(std::env::var("OMNIX_EMBEDDING2_FULL_MODEL")?);
    let image = std::fs::read(std::env::var("OMNIX_EMBEDDING2_IMAGE")?)?;
    let audio = wav();
    let mut model =
        unsafe { LiteRtLmEmbeddingModel::from_library_multimodal(&library, &model_path)? };
    let profile = model.profile().clone();
    for parts in [
        vec![EmbeddingInput::Text("A logo".into())],
        vec![EmbeddingInput::Image(image.clone())],
        vec![EmbeddingInput::Audio(audio.clone())],
        vec![
            EmbeddingInput::Text("A logo with a tone".into()),
            EmbeddingInput::Image(image.clone()),
            EmbeddingInput::Audio(audio),
        ],
        vec![
            EmbeddingInput::Image(image.clone()),
            EmbeddingInput::Image(image.clone()),
        ],
    ] {
        let vector =
            model.generate_multimodal_embedding(&parts, EmbeddingTask::RetrievalDocument)?;
        validate_final(&vector, 768)?;
        assert!((vector.iter().map(|v| v * v).sum::<f32>().sqrt() - 1.0).abs() < 0.001);
        assert_eq!(model.profile(), &profile);
    }
    assert!(model
        .generate_multimodal_embedding(&[], EmbeddingTask::RetrievalQuery)
        .is_err());
    drop(model);
    let mut text_only = unsafe { LiteRtLmEmbeddingModel::from_library(&library, &model_path)? };
    assert_ne!(text_only.profile(), &profile);
    assert!(text_only
        .generate_multimodal_embedding(
            &[EmbeddingInput::Image(image)],
            EmbeddingTask::RetrievalDocument
        )
        .is_err());
    Ok(())
}
