// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
use omnix_core::{embedding::*, litert_embedding::*};
use std::path::PathBuf;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() != 5 {
        return Err(
            "Usage: litert_embedding <trusted-runtime> <model.tflite> <tokenizer.model> <gemma|gecko-legacy> <text>"
                .into(),
        );
    }
    let convention = match args[3].as_str() {
        "gemma" => LiteRtEmbeddingConvention::GemmaRetrieval,
        "gecko-legacy" => LiteRtEmbeddingConvention::LegacyGeckoRetrieval,
        _ => return Err("Choose an explicit embedding convention: gemma or gecko-legacy".into()),
    };
    // This maintainer example requires the pinned trusted native distribution.
    let mut model = unsafe {
        LiteRtEmbeddingModel::from_library(
            &PathBuf::from(&args[0]),
            &PathBuf::from(&args[1]),
            &PathBuf::from(&args[2]),
            convention,
        )?
    };
    let vector = model.generate_embedding(&args[4], EmbeddingTask::RetrievalQuery)?;
    println!("Profile: {}", model.profile().id);
    println!(
        "Dimension: {}; input width: {}",
        vector.len(),
        model.input_sequence_length()
    );
    println!("First four values: {:?}", &vector[..vector.len().min(4)]);
    Ok(())
}
