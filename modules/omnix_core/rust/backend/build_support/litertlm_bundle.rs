// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{self, Read},
    path::{Path, PathBuf},
    process::Command,
    time::Duration,
};

const SHA256: &str = "e505e247b07313c05bbc957b7c33c82f6adb6c6c78eecae03a590319c7d049e2";
const URL: &str = "https://github.com/DenisovAV/flutter_gemma/releases/download/native-v0.17.1-a/litertlm-windows_x86_64.tar.gz";
const CPU_LIBRARIES: &str = include_str!("litertlm_windows_cpu.txt");

mod native_staging;

pub fn prepare() -> Result<(), Box<dyn std::error::Error>> {
    for name in [
        "OMNIX_CORE_LITERTLM_ARCHIVE",
        "OMNIX_CORE_LITERTLM_HOST_PACKAGING",
        "OMNIX_CORE_LITERTLM_ANDROID_LIBRARY",
    ] {
        println!("cargo:rerun-if-env-changed={name}");
    }
    println!("cargo:rerun-if-changed=build_support/litertlm_bundle.rs");
    println!("cargo:rerun-if-changed=build_support/litertlm_windows_cpu.txt");
    // Flutter's verified Native Assets hook owns installation for that host.
    // No inference-time downloads, and no download for excluded runtimes.
    if std::env::var_os("OMNIX_CORE_LITERTLM_HOST_PACKAGING").is_some()
        || std::env::var("TARGET")? != "x86_64-pc-windows-msvc"
    {
        return Ok(());
    }
    let out = PathBuf::from(std::env::var_os("OUT_DIR").ok_or("OUT_DIR missing")?);
    let archive = out.join("litertlm-0.17.1-a.tar.gz");
    if let Some(local) = std::env::var_os("OMNIX_CORE_LITERTLM_ARCHIVE") {
        let local = PathBuf::from(local);
        verify(&local)?;
        println!("cargo:rerun-if-changed={}", local.display());
        fs::copy(local, &archive)?;
    } else if !archive.is_file() {
        let client = reqwest::blocking::Client::builder()
            .connect_timeout(Duration::from_secs(30))
            .timeout(Duration::from_secs(300))
            .build()?;
        let mut response = client.get(URL).send()?.error_for_status()?;
        let temporary = out.join("litertlm.download");
        let result = (|| -> Result<(), Box<dyn std::error::Error>> {
            io::copy(&mut response, &mut fs::File::create(&temporary)?)?;
            verify(&temporary)?;
            fs::rename(&temporary, &archive)?;
            Ok(())
        })();
        if temporary.exists() {
            fs::remove_file(temporary)?;
        }
        result?;
    }
    verify(&archive)?;
    let extracted = out.join("litertlm");
    fs::create_dir_all(&extracted)?;
    // Windows ships bsdtar. Extraction only occurs after the pinned digest
    // passes; no untrusted archive is passed to an external executable.
    if !Command::new("tar")
        .arg("-xzf")
        .arg(&archive)
        .arg("-C")
        .arg(&extracted)
        .status()?
        .success()
    {
        return Err("Cannot extract verified LiteRT-LM archive; Windows tar is required".into());
    }
    if CPU_LIBRARIES
        .lines()
        .any(|name| !extracted.join(name).is_file())
    {
        return Err("LiteRT-LM archive is incomplete".into());
    }
    // OUT_DIR = <target>/<profile>/build/<package>/out, including --target.
    let profile = out
        .ancestors()
        .nth(3)
        .ok_or("Unexpected Cargo output layout")?;
    for destination in [
        profile.to_path_buf(),
        profile.join("examples"),
        profile.join("deps"),
    ] {
        fs::create_dir_all(&destination)?;
        // Keep upstream import names, including their lib-prefixed aliases.
        // This Cargo distribution contains CPU libraries only; GPU/NPU builds
        // require a separate compatible native distribution.
        for name in CPU_LIBRARIES.lines() {
            native_staging::stage_library(&extracted.join(name), &destination.join(name))?;
        }
    }
    Ok(())
}

pub fn verify(path: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let mut file = fs::File::open(path)?;
    let mut digest = Sha256::new();
    let mut buffer = [0; 65536];
    loop {
        let count = file.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        digest.update(&buffer[..count]);
    }
    if format!("{:x}", digest.finalize()) != SHA256 {
        return Err("LiteRT-LM checksum mismatch; refusing native delivery".into());
    }
    Ok(())
}
