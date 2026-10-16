// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
#[cfg(all(feature = "matter-process", target_os = "windows"))]
fn main() {
    use omnix_nexus::matter::{host::*, process::ProcessHost};
    let bundle = std::env::args_os()
        .nth(1)
        .expect("Supply the verified absolute Node/Matter.js bundle directory");
    let bundle = std::path::Path::new(&bundle);
    // Keep the private fixture directory alive until controller shutdown, then
    // remove its generated credentials with the temporary-directory owner.
    let storage = tempfile::tempdir().unwrap();
    let host = ProcessHost::qualification(
        &bundle.join("node.exe"),
        &bundle.join("host_controller.mjs"),
        storage.path(),
    )
    .unwrap();
    let target = host.target();
    let mut controller = Controller::attach(Backend::WindowsMatterJs, host).unwrap();
    for on in [true, false] {
        assert_eq!(
            controller.execute(Command::SetOnOff { target, on }),
            Ok(Reply::Acknowledged)
        );
        assert_eq!(
            controller.execute(Command::ReadOnOff { target }),
            Ok(Reply::OnOff(on))
        );
    }
    assert_eq!(controller.shutdown(), Ok(Shutdown::Released));
    drop(controller);
    storage
        .close()
        .expect("Could not remove temporary Matter fixture storage");
    println!(
        "PASS: Rust -> bundled Matter.js -> software light: On/Off, readback and process shutdown"
    );
}
#[cfg(not(all(feature = "matter-process", target_os = "windows")))]
fn main() {
    panic!("Requires Windows and explicit matter-process selection");
}
