// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
use omnix_core::{probe_model_format, ModelFormat};
#[test]
fn probes_content_not_extension_and_rejects_unknown_or_truncated() {
    let dir = std::env::temp_dir().join(format!(
        "omnix-probe-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir(&dir).unwrap();
    let file = dir.join("misleading.extension");
    for (header, expected) in [
        (b"GGUF\x03\x00\x00\x00".as_slice(), Some(ModelFormat::Gguf)),
        (b"LITERTLM".as_slice(), Some(ModelFormat::LiteRtLm)),
        (b"GGUF\x02\x00\x00\x00".as_slice(), None),
        (b"GGUF".as_slice(), None),
        (b"NOTAMODEL".as_slice(), None),
    ] {
        std::fs::write(&file, header).unwrap();
        assert_eq!(probe_model_format(&file).ok(), expected);
    }
    std::fs::remove_file(file).unwrap();
    std::fs::remove_dir(dir).unwrap();
    assert!(probe_model_format(std::path::Path::new("relative.gguf")).is_err());
}
