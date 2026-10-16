// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
use sha2::{Digest, Sha256};
use std::{
    fs,
    io::{self, Read},
    path::Path,
};

// Loaded Windows DLLs cannot be overwritten. Leave identical verified bytes
// in place; genuinely changed binaries still require closing their users.
pub(crate) fn stage_library(source: &Path, destination: &Path) -> io::Result<()> {
    if destination.is_file()
        && fs::metadata(source)?.len() == fs::metadata(destination)?.len()
        && digest_file(source)? == digest_file(destination)?
    {
        return Ok(());
    }
    fs::copy(source, destination)?;
    Ok(())
}
fn digest_file(path: &Path) -> io::Result<Vec<u8>> {
    let mut file = fs::File::open(path)?;
    let mut hash = Sha256::new();
    let mut buffer = [0u8; 65536];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hash.update(&buffer[..read]);
    }
    Ok(hash.finalize().to_vec())
}

#[cfg(all(test, windows))]
mod tests {
    use super::*;
    use std::os::windows::fs::OpenOptionsExt;
    #[test]
    fn locked_identical_binary_is_left_alone_but_updates_fail() {
        let nonce = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let directory =
            std::env::temp_dir().join(format!("omnix-staging-{}-{nonce}", std::process::id()));
        fs::create_dir(&directory).unwrap();
        let source = directory.join("source");
        let destination = directory.join("destination");
        fs::write(&source, b"original").unwrap();
        stage_library(&source, &destination).unwrap();
        // Read-sharing is allowed; write-sharing is not, as with a loaded DLL.
        let locked = fs::OpenOptions::new()
            .read(true)
            .share_mode(1)
            .open(&destination)
            .unwrap();
        stage_library(&source, &destination).unwrap();
        fs::write(&source, b"modified").unwrap();
        assert!(stage_library(&source, &destination).is_err());
        assert_eq!(fs::read(&destination).unwrap(), b"original");
        drop(locked);
        stage_library(&source, &destination).unwrap();
        assert_eq!(fs::read(&destination).unwrap(), b"modified");
        fs::remove_file(source).unwrap();
        fs::remove_file(destination).unwrap();
        fs::remove_dir(directory).unwrap();
    }
}
