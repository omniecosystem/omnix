// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Explicit, verified model acquisition. No inference operation calls this API.
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::atomic::{AtomicBool, AtomicU64, Ordering},
    time::Duration,
};

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ModelSpec {
    pub filename: String,
    pub sha256: String,
    pub bytes: u64,
    /// Host declaration only; integrity does not establish model capabilities.
    pub role: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct InstalledModel {
    pub spec: ModelSpec,
    pub path: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Progress {
    pub phase: String,
    pub received: u64,
    pub total: u64,
    pub path: Option<String>,
    pub error: Option<String>,
}
impl ModelSpec {
    pub fn validate(&self) -> Result<(), String> {
        if self.filename.len() > 120
            || self.filename.starts_with('.')
            || !self
                .filename
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
            || !(self.filename.ends_with(".litertlm") || self.filename.ends_with(".gguf"))
            || self.sha256.len() != 64
            || !self
                .sha256
                .bytes()
                .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
            || self.bytes < 8
            || self.bytes > 32 * 1024 * 1024 * 1024
            || !matches!(self.role.as_str(), "chat" | "embedding")
        {
            return Err("Invalid model specification: require a safe filename, lowercase SHA-256, byte size and chat/embedding role".into());
        }
        Ok(())
    }
    fn key(&self) -> String {
        format!("{}-{}-{}", self.sha256, self.role, self.filename)
    }
}
fn checked_root(root: &Path) -> Result<PathBuf, String> {
    if !root.is_absolute() {
        return Err("Model store must be an absolute host-owned path".into());
    }
    fs::create_dir_all(root).map_err(|_| "Cannot create model store")?;
    root.canonicalize()
        .map_err(|_| "Cannot resolve model store".into())
}
fn cancelled(cancel: &AtomicBool) -> Result<(), String> {
    if cancel.load(Ordering::Acquire) {
        Err("Installation cancelled".into())
    } else {
        Ok(())
    }
}
async fn cancellation(cancel: &AtomicBool) {
    while !cancel.load(Ordering::Acquire) {
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
}
fn digest_file(path: &Path, cancel: &AtomicBool) -> Result<String, String> {
    let mut file = fs::File::open(path).map_err(|_| "Cannot read installed model")?;
    let mut hash = Sha256::new();
    let mut buffer = [0u8; 65536];
    loop {
        cancelled(cancel)?;
        let n = file
            .read(&mut buffer)
            .map_err(|_| "Cannot verify installed model")?;
        if n == 0 {
            break;
        }
        hash.update(&buffer[..n]);
    }
    Ok(format!("{:x}", hash.finalize()))
}
struct Staging(PathBuf);
impl Staging {
    fn persist(mut self) {
        self.0.clear();
    }
}
impl Drop for Staging {
    fn drop(&mut self) {
        if !self.0.as_os_str().is_empty() {
            let _ = fs::remove_dir_all(&self.0);
        }
    }
}
static NEXT: AtomicU64 = AtomicU64::new(1);

/// Durable handoff to a host/OS transfer adapter, not an installed model.
/// The adapter owns scheduling and must close its writer before completion.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TransferReservation {
    pub id: String,
    pub spec: ModelSpec,
    pub path: String,
}

/// Reserves a same-filesystem destination without starting network activity.
/// Only artifact metadata is persisted: no URL, token or platform task handle.
pub fn reserve_transfer(root: &Path, spec: ModelSpec) -> Result<TransferReservation, String> {
    spec.validate()?;
    let root = checked_root(root)?;
    if root.join(spec.key()).exists() {
        return Err(
            "Artifact already exists; inspect or verify its installation before scheduling".into(),
        );
    }
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| "Clock unavailable")?
        .as_nanos();
    let id = format!(
        "{:x}-{nonce:x}-{:x}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    );
    let directory = root.join(format!(".transfer-{id}"));
    // Create before arming cleanup so a failed create cannot remove another job.
    fs::create_dir(&directory).map_err(|_| "Cannot reserve transfer directory")?;
    let stage = Staging(directory);
    let path = stage.0.join(&spec.filename);
    fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .and_then(|file| file.sync_all())
        .map_err(|_| "Cannot reserve model file")?;
    let mut metadata = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(stage.0.join("installed.json"))
        .map_err(|_| "Cannot create transfer record")?;
    metadata
        .write_all(&serde_json::to_vec(&spec).map_err(|_| "Cannot encode transfer record")?)
        .and_then(|()| metadata.sync_all())
        .map_err(|_| "Cannot save transfer record")?;
    let reservation = TransferReservation {
        id,
        spec,
        path: path.to_string_lossy().into_owned(),
    };
    stage.persist(); // Persistent reservation, owned by the host until publication.
    Ok(reservation)
}

fn read_transfer(root: &Path, id: &str) -> Result<TransferReservation, String> {
    if id.is_empty() || id.len() > 100 || !id.bytes().all(|b| b.is_ascii_hexdigit() || b == b'-') {
        return Err("Invalid transfer identity".into());
    }
    let directory = root.join(format!(".transfer-{id}"));
    if !fs::symlink_metadata(&directory)
        .map_err(|_| "Unknown transfer")?
        .file_type()
        .is_dir()
    {
        return Err("Transfer directory must not be a symlink".into());
    }
    let metadata = directory.join("installed.json");
    let info = fs::symlink_metadata(&metadata).map_err(|_| "Missing transfer record")?;
    if !info.is_file() || info.len() > 4096 {
        return Err("Invalid transfer record".into());
    }
    let spec: ModelSpec =
        serde_json::from_slice(&fs::read(metadata).map_err(|_| "Cannot read transfer record")?)
            .map_err(|_| "Invalid transfer record")?;
    spec.validate()?;
    Ok(TransferReservation {
        id: id.into(),
        path: directory
            .join(&spec.filename)
            .to_string_lossy()
            .into_owned(),
        spec,
    })
}

/// Recovers pending reservations after restart; does not imply OS task recovery.
pub fn pending_transfers(root: &Path) -> Result<Vec<TransferReservation>, String> {
    let root = checked_root(root)?;
    let mut pending = Vec::new();
    for entry in fs::read_dir(&root).map_err(|_| "Cannot list transfers")? {
        let entry = entry.map_err(|_| "Cannot read transfer entry")?;
        if let Some(id) = entry
            .file_name()
            .to_string_lossy()
            .strip_prefix(".transfer-")
        {
            if let Ok(record) = read_transfer(&root, id) {
                pending.push(record);
            }
        }
    }
    pending.sort_by(|a, b| a.id.cmp(&b.id));
    Ok(pending)
}

/// Verifies and publishes the adapter's completed file without a model copy.
/// On failure or cancellation the reservation is retained, never deleted.
/// Call only after the adapter has stopped writing. Concurrent completion and
/// cancellation/removal require host coordination; this is not an OS scheduler.
pub fn complete_transfer(
    root: &Path,
    id: &str,
    cancel: &AtomicBool,
) -> Result<InstalledModel, String> {
    let root = checked_root(root)?;
    let reservation = read_transfer(&root, id)?;
    let path = Path::new(&reservation.path);
    let info = fs::symlink_metadata(path).map_err(|_| "Missing transferred model")?;
    if !info.is_file() || info.len() != reservation.spec.bytes {
        return Err("Transferred model size differs from declared size".into());
    }
    if digest_file(path, cancel)? != reservation.spec.sha256 {
        return Err("Transferred model SHA-256 verification failed".into());
    }
    let format =
        crate::probe_model_format(path).map_err(|_| "Unsupported transferred model container")?;
    if reservation.spec.filename.ends_with(".gguf") != (format == crate::ModelFormat::Gguf) {
        return Err("Transferred model container does not match its filename".into());
    }
    fs::OpenOptions::new()
        .read(true)
        .write(true)
        .open(path)
        .and_then(|file| file.sync_all())
        .map_err(|_| "Cannot flush transferred model")?;
    cancelled(cancel)?;
    let destination = root.join(reservation.spec.key());
    if destination.exists() {
        return Err("Installation already exists; transfer was preserved".into());
    }
    fs::rename(root.join(format!(".transfer-{id}")), &destination)
        .map_err(|_| "Cannot publish completed transfer")?;
    Ok(InstalledModel {
        path: destination
            .join(&reservation.spec.filename)
            .to_string_lossy()
            .into_owned(),
        spec: reservation.spec,
    })
}

/// Import copies the source; it never renames or deletes the user's file.
/// Network transfers require HTTPS and do not persist authentication tokens.
pub fn install(
    root: &Path,
    spec: ModelSpec,
    source: &str,
    network: bool,
    token: Option<&str>,
    cancel: &AtomicBool,
    progress: impl Fn(Progress),
) -> Result<InstalledModel, String> {
    spec.validate()?;
    cancelled(cancel)?;
    let root = checked_root(root)?;
    let destination = root.join(spec.key());
    if destination.exists() {
        let record = read_record(&root, &destination)?;
        if record.spec.sha256 != spec.sha256
            || record.spec.bytes != spec.bytes
            || digest_file(Path::new(&record.path), cancel)? != spec.sha256
        {
            return Err("Existing installation failed verification; it was not overwritten".into());
        }
        return Ok(record);
    }
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| "Clock unavailable")?
        .as_nanos();
    let staging_path = root.join(format!(
        ".install-{}-{nonce}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    fs::create_dir(&staging_path).map_err(|_| "Cannot create installation staging directory")?;
    let stage = Staging(staging_path);
    let partial = stage.0.join(&spec.filename);
    let mut output = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&partial)
        .map_err(|_| "Cannot create model file")?;
    let mut received = 0u64;
    let mut hash = Sha256::new();
    let mut consume = |chunk: &[u8]| -> Result<(), String> {
        cancelled(cancel)?;
        received = received
            .checked_add(chunk.len() as u64)
            .ok_or("Model size overflow")?;
        if received > spec.bytes {
            return Err("Transfer exceeds declared model size".into());
        }
        output
            .write_all(chunk)
            .map_err(|_| "Cannot write model; check available storage")?;
        hash.update(chunk);
        progress(Progress {
            phase: "transferring".into(),
            received,
            total: spec.bytes,
            path: None,
            error: None,
        });
        Ok(())
    };
    if network {
        let url = reqwest::Url::parse(source).map_err(|_| "Invalid model URL")?;
        if url.scheme() != "https" || !url.username().is_empty() || url.password().is_some() {
            return Err("Model downloads require HTTPS without URL credentials".into());
        }
        // Explicit public roots avoid Android Java/JNI verifier initialization.
        // This does not trust user-installed/private CAs or disable verification.
        let roots =
            rustls::RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
        let tls = rustls::ClientConfig::builder_with_provider(std::sync::Arc::new(
            rustls::crypto::aws_lc_rs::default_provider(),
        ))
        .with_safe_default_protocol_versions()
        .map_err(|_| "Cannot configure TLS")?
        .with_root_certificates(roots)
        .with_no_client_auth();
        let client = reqwest::Client::builder()
            .tls_backend_preconfigured(tls)
            .https_only(true)
            .connect_timeout(Duration::from_secs(15))
            .read_timeout(Duration::from_secs(30))
            .build()
            .map_err(|_| "Cannot create HTTPS transport")?;
        let mut request = client.get(url);
        if let Some(token) = token {
            request = request.bearer_auth(token);
        }
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|_| "Cannot create download executor")?;
        runtime.block_on(async {
            let mut response = tokio::select! {
                result = request.send() => result.map_err(|_| "Model request failed; check network or credentials")?,
                _ = cancellation(cancel) => return Err("Installation cancelled".to_string()),
            };
            if response.status() != reqwest::StatusCode::OK { return Err(format!("Model server returned HTTP {}", response.status().as_u16())); }
            if response.content_length().is_some_and(|size| size != spec.bytes) { return Err("Server size differs from declared model size".into()); }
            loop {
                let chunk = tokio::select! {
                    result = response.chunk() => result.map_err(|_| "Model transfer interrupted")?,
                    _ = cancellation(cancel) => return Err("Installation cancelled".to_string()),
                };
                match chunk { Some(chunk) => consume(&chunk)?, None => break }
            }
            Ok::<(), String>(())
        })?;
    } else {
        let source = Path::new(source);
        if !source.is_absolute() {
            return Err("Import requires a readable absolute file path".into());
        }
        let mut input = fs::File::open(source).map_err(|_| "Cannot read selected model file")?;
        let mut buffer = [0u8; 65536];
        loop {
            let n = input
                .read(&mut buffer)
                .map_err(|_| "Model import interrupted")?;
            if n == 0 {
                break;
            }
            consume(&buffer[..n])?;
        }
    }
    cancelled(cancel)?;
    progress(Progress {
        phase: "verifying".into(),
        received,
        total: spec.bytes,
        path: None,
        error: None,
    });
    if received != spec.bytes || format!("{:x}", hash.finalize()) != spec.sha256 {
        return Err("Model size or SHA-256 verification failed".into());
    }
    output
        .sync_all()
        .map_err(|_| "Cannot flush model to storage")?;
    drop(output);
    let format = crate::probe_model_format(&partial)
        .map_err(|_| "Downloaded file is not a supported model container")?;
    if (spec.filename.ends_with(".gguf")) != (format == crate::ModelFormat::Gguf) {
        return Err("Model container does not match its filename".into());
    }
    let mut metadata = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(stage.0.join("installed.json"))
        .map_err(|_| "Cannot create installation record")?;
    metadata
        .write_all(&serde_json::to_vec(&spec).map_err(|_| "Cannot encode installation record")?)
        .map_err(|_| "Cannot save installation record")?;
    metadata
        .sync_all()
        .map_err(|_| "Cannot flush installation record")?;
    drop(metadata);
    cancelled(cancel)?;
    fs::rename(&stage.0, &destination)
        .map_err(|_| "Cannot finalize installation; another installation may already exist")?;
    Ok(InstalledModel {
        path: destination
            .join(&spec.filename)
            .to_string_lossy()
            .into_owned(),
        spec,
    })
}
/// Registers a host-owned file in place after verifying its declared integrity.
/// No model bytes are copied, moved or deleted. The host must stop all writers
/// before calling and retain the file for the lifetime of this registration.
pub fn adopt_file(
    root: &Path,
    spec: ModelSpec,
    source: &Path,
    cancel: &AtomicBool,
) -> Result<InstalledModel, String> {
    spec.validate()?;
    cancelled(cancel)?;
    if !source.is_absolute() {
        return Err("Adoption requires an absolute host-owned file path".into());
    }
    let info = fs::symlink_metadata(source).map_err(|_| "Cannot inspect model for adoption")?;
    if !info.is_file() || info.len() != spec.bytes {
        return Err("Adopted model size differs from declared size".into());
    }
    let source = source
        .canonicalize()
        .map_err(|_| "Cannot resolve adopted model")?;
    if digest_file(&source, cancel)? != spec.sha256 {
        return Err("Adopted model SHA-256 verification failed".into());
    }
    let format =
        crate::probe_model_format(&source).map_err(|_| "Unsupported adopted model container")?;
    if spec.filename.ends_with(".gguf") != (format == crate::ModelFormat::Gguf) {
        return Err("Adopted model container does not match its filename".into());
    }
    let root = checked_root(root)?;
    let destination = root.join(spec.key());
    if destination.exists() {
        let record = read_record(&root, &destination)?;
        if Path::new(&record.path) != source {
            return Err(
                "Another installation already owns this identity; it was not overwritten".into(),
            );
        }
        return Ok(record);
    }
    let nonce = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_err(|_| "Clock unavailable")?
        .as_nanos();
    let staging = root.join(format!(
        ".adopt-{}-{nonce}-{}",
        std::process::id(),
        NEXT.fetch_add(1, Ordering::Relaxed)
    ));
    fs::create_dir(&staging).map_err(|_| "Cannot create adoption record")?;
    let stage = Staging(staging);
    for (name, bytes) in [
        ("installed.json", serde_json::to_vec(&spec)),
        ("external.json", serde_json::to_vec(&source)),
    ] {
        let mut file = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(stage.0.join(name))
            .map_err(|_| "Cannot create adoption metadata")?;
        file.write_all(&bytes.map_err(|_| "Cannot encode adoption metadata")?)
            .and_then(|()| file.sync_all())
            .map_err(|_| "Cannot save adoption metadata")?;
    }
    cancelled(cancel)?;
    fs::rename(&stage.0, &destination).map_err(|_| "Cannot publish adoption record")?;
    stage.persist();
    Ok(InstalledModel {
        spec,
        path: source.to_string_lossy().into_owned(),
    })
}

fn read_record(root: &Path, directory: &Path) -> Result<InstalledModel, String> {
    if fs::symlink_metadata(directory)
        .map_err(|_| "Missing installation")?
        .file_type()
        .is_symlink()
    {
        return Err("Symlink installation refused".into());
    }
    let metadata = directory.join("installed.json");
    if fs::metadata(&metadata)
        .map_err(|_| "Incomplete installation")?
        .len()
        > 4096
    {
        return Err("Invalid installation record".into());
    }
    let spec: ModelSpec =
        serde_json::from_slice(&fs::read(metadata).map_err(|_| "Cannot read installation record")?)
            .map_err(|_| "Invalid installation record")?;
    spec.validate()?;
    if directory != root.join(spec.key()) {
        return Err("Installation identity mismatch".into());
    }
    let external = directory.join("external.json");
    let path = if external
        .try_exists()
        .map_err(|_| "Cannot inspect adoption record")?
    {
        let info = fs::symlink_metadata(&external).map_err(|_| "Missing adoption record")?;
        if !info.is_file() || info.len() > 8192 {
            return Err("Invalid adoption record".into());
        }
        let path: PathBuf =
            serde_json::from_slice(&fs::read(external).map_err(|_| "Cannot read adoption record")?)
                .map_err(|_| "Invalid adoption record")?;
        if !path.is_absolute() {
            return Err("Adopted model path must be absolute".into());
        }
        path
    } else {
        directory.join(&spec.filename)
    };
    let information = fs::symlink_metadata(&path).map_err(|_| "Missing model file")?;
    if !information.is_file() || information.len() != spec.bytes {
        return Err("Installed file size changed".into());
    }
    Ok(InstalledModel {
        spec,
        path: path.to_string_lossy().into_owned(),
    })
}
/// Removes a registration and any engine-owned model file.
/// Host-owned adopted files are never deleted; their path is returned to the
/// host, which may separately choose to delete them after explicit user intent.
/// The host must first release inference and transfer handles for this model.
pub fn remove(root: &Path, spec: ModelSpec) -> Result<Option<String>, String> {
    spec.validate()?;
    let root = checked_root(root)?;
    let directory = root.join(spec.key());
    let record = read_record(&root, &directory)?;
    if record.spec.bytes != spec.bytes {
        return Err("Removal specification differs from the installed artifact".into());
    }
    let external = directory.join("external.json");
    let host_path = if external
        .try_exists()
        .map_err(|_| "Cannot inspect adoption record")?
    {
        fs::remove_file(&external).map_err(|_| "Cannot remove adoption record")?;
        Some(record.path)
    } else {
        fs::remove_file(directory.join(&spec.filename))
            .map_err(|_| "Cannot remove model; release all native handles first")?;
        None
    };
    fs::remove_file(directory.join("installed.json"))
        .map_err(|_| "Cannot remove installation record")?;
    // Never recursively delete unexpected files placed in this directory.
    fs::remove_dir(directory)
        .map_err(|_| "Installation directory contains other files or cannot be removed")?;
    Ok(host_path)
}

/// Partial staging directories are never returned as installed models.
pub fn list(root: &Path) -> Result<Vec<InstalledModel>, String> {
    let root = checked_root(root)?;
    let mut records = Vec::new();
    for entry in fs::read_dir(&root).map_err(|_| "Cannot list model store")? {
        let entry = entry.map_err(|_| "Cannot read model entry")?;
        if entry.file_name().to_string_lossy().starts_with('.') {
            continue;
        }
        if let Ok(record) = read_record(&root, &entry.path()) {
            records.push(record);
        }
    }
    records.sort_by(|a, b| a.spec.filename.cmp(&b.spec.filename));
    Ok(records)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> (Staging, PathBuf, ModelSpec) {
        let root = Staging(std::env::temp_dir().join(format!(
            "omnix-install-test-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        )));
        fs::create_dir_all(&root.0).unwrap();
        let source = root.0.join("source.litertlm");
        fs::write(&source, b"LITERTLMfixture").unwrap();
        let spec = ModelSpec {
            filename: "test.litertlm".into(),
            sha256: format!("{:x}", Sha256::digest(b"LITERTLMfixture")),
            bytes: 15,
            role: "chat".into(),
        };
        (root, source, spec)
    }
    #[test]
    fn removal_deletes_only_owned_artifacts_and_preserves_adopted_source() {
        let (root, source, spec) = fixture();
        let store = root.0.join("models");
        let cancel = AtomicBool::new(false);
        adopt_file(&store, spec.clone(), &source, &cancel).unwrap();
        assert!(remove(&store, spec.clone()).unwrap().is_some());
        assert!(source.exists());
        assert!(list(&store).unwrap().is_empty());
        let record = install(
            &store,
            spec.clone(),
            source.to_str().unwrap(),
            false,
            None,
            &cancel,
            |_| {},
        )
        .unwrap();
        assert!(remove(&store, spec).unwrap().is_none());
        assert!(!Path::new(&record.path).exists());
        assert!(source.exists());
    }
    #[test]
    fn adoption_verifies_without_copying_and_survives_restart() {
        let (root, source, spec) = fixture();
        let store = root.0.join("models");
        let cancel = AtomicBool::new(false);
        let record = adopt_file(&store, spec.clone(), &source, &cancel).unwrap();
        assert_eq!(Path::new(&record.path), source.canonicalize().unwrap());
        assert!(!store.join(spec.key()).join(&spec.filename).exists());
        assert_eq!(list(&store).unwrap()[0].path, record.path);
        assert_eq!(
            adopt_file(&store, spec, &source, &cancel).unwrap().path,
            record.path
        );
        assert_eq!(fs::read(&source).unwrap(), b"LITERTLMfixture");
        fs::remove_file(&source).unwrap();
        assert!(list(&store).unwrap().is_empty());
    }
    #[test]
    fn adoption_rejects_corruption_cancellation_and_identity_conflicts() {
        let (root, source, spec) = fixture();
        let store = root.0.join("models");
        let mut bad = spec.clone();
        bad.sha256 = "0".repeat(64);
        assert!(adopt_file(&store, bad, &source, &AtomicBool::new(false)).is_err());
        assert!(adopt_file(&store, spec.clone(), &source, &AtomicBool::new(true)).is_err());
        assert!(adopt_file(
            &store,
            spec.clone(),
            Path::new("relative"),
            &AtomicBool::new(false)
        )
        .is_err());
        assert!(!store.exists());
        let installed = install(
            &store,
            spec.clone(),
            source.to_str().unwrap(),
            false,
            None,
            &AtomicBool::new(false),
            |_| {},
        )
        .unwrap();
        assert!(adopt_file(&store, spec, &source, &AtomicBool::new(false)).is_err());
        assert_eq!(list(&store).unwrap()[0].path, installed.path);
        assert!(source.exists());
    }
    #[test]
    fn platform_transfer_recovers_and_publishes_without_copy() {
        let (root, source, spec) = fixture();
        let store = root.0.join("models");
        let transfer = reserve_transfer(&store, spec.clone()).unwrap();
        fs::write(&transfer.path, fs::read(&source).unwrap()).unwrap();
        assert!(list(&store).unwrap().is_empty());
        assert_eq!(pending_transfers(&store).unwrap()[0].id, transfer.id);
        let installed = complete_transfer(&store, &transfer.id, &AtomicBool::new(false)).unwrap();
        assert!(!Path::new(&transfer.path).exists());
        assert!(source.exists());
        assert_eq!(fs::read(installed.path).unwrap(), b"LITERTLMfixture");
        assert!(pending_transfers(&store).unwrap().is_empty());
        assert_eq!(list(&store).unwrap().len(), 1);
        assert!(reserve_transfer(&store, spec).is_err());
    }
    #[test]
    fn platform_failure_preserves_partial_and_never_installs() {
        let (root, _, spec) = fixture();
        let store = root.0.join("models");
        let transfer = reserve_transfer(&store, spec).unwrap();
        fs::write(&transfer.path, b"partial").unwrap();
        assert!(complete_transfer(&store, &transfer.id, &AtomicBool::new(false)).is_err());
        assert_eq!(fs::read(&transfer.path).unwrap(), b"partial");
        fs::write(&transfer.path, b"LITERTLMcorrupt").unwrap();
        assert!(complete_transfer(&store, &transfer.id, &AtomicBool::new(false)).is_err());
        fs::write(&transfer.path, b"LITERTLMfixture").unwrap();
        assert!(complete_transfer(&store, &transfer.id, &AtomicBool::new(true)).is_err());
        assert!(Path::new(&transfer.path).exists());
        assert!(list(&store).unwrap().is_empty());
        assert!(complete_transfer(&store, "../escape", &AtomicBool::new(false)).is_err());
    }
    #[test]
    fn publication_conflict_preserves_other_reservation() {
        let (root, _, spec) = fixture();
        let store = root.0.join("models");
        let first = reserve_transfer(&store, spec.clone()).unwrap();
        let second = reserve_transfer(&store, spec).unwrap();
        fs::write(&first.path, b"LITERTLMfixture").unwrap();
        fs::write(&second.path, b"LITERTLMfixture").unwrap();
        complete_transfer(&store, &first.id, &AtomicBool::new(false)).unwrap();
        assert!(complete_transfer(&store, &second.id, &AtomicBool::new(false)).is_err());
        assert!(Path::new(&second.path).exists());
        assert_eq!(list(&store).unwrap().len(), 1);
        assert_eq!(pending_transfers(&store).unwrap().len(), 1);
    }
    #[test]
    fn import_persists_and_reuses_verified_file() {
        let (root, source, spec) = fixture();
        let store = root.0.join("models");
        let cancel = AtomicBool::new(false);
        let record = install(
            &store,
            spec.clone(),
            source.to_str().unwrap(),
            false,
            None,
            &cancel,
            |_| {},
        )
        .unwrap();
        assert!(source.exists());
        assert_eq!(list(&store).unwrap().len(), 1);
        assert_eq!(
            install(&store, spec, "unused", false, None, &cancel, |_| {})
                .unwrap()
                .path,
            record.path
        );
    }
    #[test]
    fn failures_never_publish_or_remove_source() {
        let (root, source, mut spec) = fixture();
        let store = root.0.join("models");
        spec.sha256 = "0".repeat(64);
        assert!(install(
            &store,
            spec,
            source.to_str().unwrap(),
            false,
            None,
            &AtomicBool::new(false),
            |_| {}
        )
        .is_err());
        assert!(source.exists());
        assert!(list(&store).unwrap().is_empty());
        assert_eq!(fs::read_dir(&store).unwrap().count(), 0);
    }
    #[test]
    fn cancellation_cleans_only_its_staging() {
        let (root, source, spec) = fixture();
        let store = root.0.join("models");
        let cancel = AtomicBool::new(false);
        assert!(install(
            &store,
            spec,
            source.to_str().unwrap(),
            false,
            None,
            &cancel,
            |_| {
                cancel.store(true, Ordering::Release);
            }
        )
        .is_err());
        assert!(source.exists());
        assert!(list(&store).unwrap().is_empty());
    }
    #[test]
    fn traversal_and_bad_container_rejected() {
        let (root, source, mut spec) = fixture();
        spec.filename = "../test.litertlm".into();
        assert!(spec.validate().is_err());
        spec.filename = "test.gguf".into();
        assert!(install(
            &root.0.join("models"),
            spec,
            source.to_str().unwrap(),
            false,
            None,
            &AtomicBool::new(false),
            |_| {}
        )
        .is_err());
    }
    #[test]
    fn insecure_network_source_rejected_without_request() {
        let (root, _, spec) = fixture();
        assert!(install(
            &root.0.join("models"),
            spec,
            "http://example.invalid/model",
            true,
            None,
            &AtomicBool::new(false),
            |_| {}
        )
        .unwrap_err()
        .contains("HTTPS"));
    }
    #[test]
    fn truncated_import_is_never_listed() {
        let (root, source, mut spec) = fixture();
        spec.bytes += 1;
        let store = root.0.join("models");
        assert!(install(
            &store,
            spec,
            source.to_str().unwrap(),
            false,
            None,
            &AtomicBool::new(false),
            |_| {}
        )
        .is_err());
        assert!(list(&store).unwrap().is_empty());
    }
    #[test]
    fn same_size_corruption_fails_reuse_without_overwrite() {
        let (root, source, spec) = fixture();
        let store = root.0.join("models");
        let cancel = AtomicBool::new(false);
        let record = install(
            &store,
            spec.clone(),
            source.to_str().unwrap(),
            false,
            None,
            &cancel,
            |_| {},
        )
        .unwrap();
        fs::write(&record.path, b"LITERTLMcorrupt").unwrap();
        assert!(install(
            &store,
            spec,
            source.to_str().unwrap(),
            false,
            None,
            &cancel,
            |_| {}
        )
        .is_err());
        assert_eq!(fs::read(&record.path).unwrap(), b"LITERTLMcorrupt");
    }
    #[test]
    fn abandoned_staging_and_relative_roots_are_not_ready() {
        let (root, _, _) = fixture();
        fs::create_dir(root.0.join(".install-abandoned")).unwrap();
        assert!(list(&root.0).unwrap().is_empty());
        assert!(list(Path::new("relative-model-store")).is_err());
    }
}
