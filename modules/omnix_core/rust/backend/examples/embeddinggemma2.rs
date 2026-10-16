// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
use omnix_core::{embedding::*, litertlm_embedding::LiteRtLmEmbeddingModel};
use std::path::Path;
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.len() != 3 {
        return Err(
            "Usage: embeddinggemma2 <trusted-v0.18-library> <text-model.litertlm> <query>".into(),
        );
    }
    let mut model =
        unsafe { LiteRtLmEmbeddingModel::from_library(Path::new(&args[0]), Path::new(&args[1]))? };
    let vector = model.generate_embedding(&args[2], EmbeddingTask::RetrievalQuery)?;
    println!("Profile: {}", model.profile().id);
    println!(
        "Dimension: {}; norm: {:.6}",
        vector.len(),
        vector.iter().map(|x| x * x).sum::<f32>().sqrt()
    );
    Ok(())
}
