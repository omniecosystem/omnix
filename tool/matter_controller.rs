/*
 *
 *    Copyright (c) 2026 Project CHIP Authors
 *
 *    Licensed under the Apache License, Version 2.0 (the "License");
 *    you may not use this file except in compliance with the License.
 *    You may obtain a copy of the License at
 *
 *        http://www.apache.org/licenses/LICENSE-2.0
 *
 *    Unless required by applicable law or agreed to in writing, software
 *    distributed under the License is distributed on an "AS IS" BASIS,
 *    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *    See the License for the specific language governing permissions and
 *    limitations under the License.
 */

//! Omnix interoperability spike, adapted from the upstream commissioner driver.
//!
//! The PowerShell runner injects this into a disposable rs-matter workspace.
//! MATTER_TEST_PEER names the disposable C++ software light; MATTER_TEST_PASSCODE
//! defaults to 20202021. Real operational mDNS resolution, secure commissioning,
//! and an OnOff read/toggle/read/restore round trip must all succeed.
//!
//! Fabric keys are ephemeral and test attestation is explicitly allowed.
//! This is not a production controller or a tool for commissioning real devices.

use core::num::NonZeroU8;
use core::pin::pin;

use std::net::{SocketAddr, UdpSocket};

use embassy_futures::select::{select, Either};
use embassy_time::{Duration, Timer};

use log::{error, info};

use rs_matter::cert::gen::VALID_FOREVER;
use rs_matter::cert::{MAX_CERT_TLV_AND_ASN1_LEN, MAX_CERT_TLV_LEN};
use rs_matter::crypto::{
    default_crypto, CanonAeadKey, CanonPkcSecretKey, Crypto, Rng as _, SecretKey, SigningSecretKey,
};
use rs_matter::dm::devices::test::{DAC_PRIVKEY, TEST_DEV_ATT, TEST_DEV_COMM, TEST_DEV_DET};
use rs_matter::error::{Error, ErrorCode};
use rs_matter::onboard::cac::{IcacGenerator, RcacGenerator};
use rs_matter::onboard::noc::NocGenerator;
use rs_matter::onboard::{CommissionOptions, Commissioner};
use rs_matter::transport::network::{Address, NoNetwork};
use rs_matter::utils::init::InitMaybeUninit;
use rs_matter::Matter;

use static_cell::StaticCell;

// Omnix spike adaptation: use the real network resolver, not the upstream stub.
#[path = "matter_mdns.rs"]
mod mdns;

/// Defaults match rs-matter's `TEST_DEV_COMM`. Override via CLI args
/// for chip-all-clusters-app or any other peer.
const DEFAULT_PASSCODE: u32 = 20202021;

const COMMISSION_TIMEOUT_SECS: u64 = 60;

static CTRL_MATTER: StaticCell<Matter> = StaticCell::new();

#[test]
fn commission_discover_and_toggle_external_light() {
    let _ = env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .try_init();
    let args = parse_args().expect("valid explicitly supplied test peer");
    let result = futures_lite::future::block_on(run(args))
        .expect("real mDNS, commissioning and OnOff round trip must succeed");
    println!(
        "matter_spike: ok fabric_index={} device_node_id=0x{:016x}",
        result.fabric_index, result.device_node_id
    );
}

#[derive(Debug)]
struct Args {
    passcode: u32,
    peer_addr: SocketAddr,
}

fn parse_args() -> Result<Args, String> {
    let passcode = match std::env::var("MATTER_TEST_PASSCODE").ok() {
        Some(s) => s
            .parse::<u32>()
            .map_err(|e| format!("passcode must be u32: {e}"))?,
        None => DEFAULT_PASSCODE,
    };
    let peer_addr_str = std::env::var("MATTER_TEST_PEER")
        .map_err(|_| "MATTER_TEST_PEER must name a disposable software light".to_string())?;
    let peer_addr = peer_addr_str
        .parse::<SocketAddr>()
        .map_err(|e| format!("peer addr must be SocketAddr (e.g. [::1]:5540): {e}"))?;
    Ok(Args {
        passcode,
        peer_addr,
    })
}

async fn run(args: Args) -> Result<CommissionResult, Error> {
    let bind_addr: SocketAddr = "[::]:0".parse().unwrap();
    let socket =
        async_io::Async::<UdpSocket>::bind(bind_addr).map_err(|_| ErrorCode::NoNetworkInterface)?;
    info!(
        "controller bound on {}",
        socket.get_ref().local_addr().unwrap()
    );

    let crypto = default_crypto(rand::rng(), DAC_PRIVKEY);
    let matter = CTRL_MATTER.uninit().init_with(Matter::init(
        &TEST_DEV_DET,
        TEST_DEV_COMM,
        &TEST_DEV_ATT,
        // local port = 0 → kernel-picked, matches the ephemeral `socket`.
        0,
    ));

    // The transport pump must stay alive throughout the flow.
    let transport_fut = async {
        match select(
            matter.run(&crypto, &socket, &socket, NoNetwork),
            mdns::run_mdns(matter, &crypto),
        )
        .await
        {
            Either::First(result) | Either::Second(result) => result,
        }
    };
    let flow_fut = run_commission(matter, &crypto, args);

    let mut transport_fut = pin!(transport_fut);
    let mut flow_fut = pin!(flow_fut);

    match select(&mut transport_fut, &mut flow_fut).await {
        Either::First(r) => {
            error!("transport exited prematurely: {r:?}");
            Err(ErrorCode::NoExchange.into())
        }
        Either::Second(result) => result,
    }
}

/// Mirror of [`rs_matter::onboard::CommissionResult`] — re-declared
/// here so the `main` print doesn't have to import the lifetime-bound
/// type through the public API just to format two scalars.
///
/// `fabric_index` is `NonZeroU8` because the device's `AddNOC` response
/// reserves `0` for "no fabric" / PASE — a real
/// commissioned fabric slot is always non-zero.
#[derive(Debug, Clone, Copy)]
struct CommissionResult {
    fabric_index: NonZeroU8,
    device_node_id: u64,
}

async fn run_commission<C: Crypto>(
    matter: &Matter<'_>,
    crypto: &C,
    args: Args,
) -> Result<CommissionResult, Error> {
    info!("=== Commissioner::commission (phase 1 — PASE + over PASE) ===");

    // chip-tool's conventional admin NodeID + test vendor — matches
    // what `chip-all-clusters-app` expects on the device-side ACL.
    const FABRIC_ID: u64 = 1;
    const CONTROLLER_NODE_ID: u64 = 112233;
    const DEVICE_NODE_ID: u64 = 112234;
    const ADMIN_VENDOR_ID: u16 = 0xFFF1;

    // Offline CA chain: RCAC then ICAC; RCAC priv key discarded
    // immediately afterwards (in a real deployment it would never
    // have been on the controller in the first place).
    let mut rcac_buf = [0u8; MAX_CERT_TLV_AND_ASN1_LEN];
    let mut rcac_gen = RcacGenerator::new(&mut rcac_buf);
    let (rcac_priv, rcac) = rcac_gen.generate(crypto, FABRIC_ID, VALID_FOREVER)?;

    let mut icac_buf = [0u8; MAX_CERT_TLV_AND_ASN1_LEN];
    let mut icac_gen = IcacGenerator::new(&mut icac_buf);
    let (icac_priv, icac) =
        icac_gen.generate(crypto, rcac_priv.reference(), rcac, VALID_FOREVER)?;
    drop(rcac_priv);

    // Controller operational keypair + CSR.
    let controller_secret_key = crypto.generate_secret_key()?;
    let mut controller_csr_buf = [0u8; 256];
    let controller_csr = controller_secret_key.csr(&mut controller_csr_buf)?;
    let mut controller_secret_key_canon = CanonPkcSecretKey::new();
    controller_secret_key.write_canon(&mut controller_secret_key_canon)?;

    // NocGenerator: signs the controller NOC now, then the device
    // NOC during commissioning. The NOC serial is derived from the
    // NodeID internally.
    let mut noc_buf = [0u8; MAX_CERT_TLV_AND_ASN1_LEN];
    let mut noc_generator = NocGenerator::create(icac_priv.reference(), rcac, icac, &mut noc_buf)?;

    let controller_noc = noc_generator.generate(
        crypto,
        controller_csr,
        CONTROLLER_NODE_ID,
        &[],
        VALID_FOREVER,
    )?;

    // Fabric IPK: 16 random bytes, shared across the fabric.
    let mut ipk = CanonAeadKey::new();
    crypto.rand()?.fill_bytes(ipk.access_mut());

    // Install the fabric in `matter.state.fabrics`.
    let controller_fab_idx = matter.with_state(|state| {
        state
            .fabrics
            .add(
                crypto,
                controller_secret_key_canon.reference(),
                rcac,
                controller_noc,
                icac,
                Some(ipk.reference()),
                ADMIN_VENDOR_ID,
                CONTROLLER_NODE_ID,
            )
            .map(|f| f.fab_idx())
    })?;

    // Scratch buffer for Commissioner — used to stage the fabric's
    // RCAC / ICAC bytes across the async on-wire calls. See
    // `Commissioner::new` for the size requirement.
    let mut commissioner_buf = [0u8; MAX_CERT_TLV_LEN];
    let mut commissioner = Commissioner::new(
        matter,
        crypto,
        controller_fab_idx,
        &mut noc_generator,
        &mut commissioner_buf,
    );

    let opts = CommissionOptions {
        // chip-all-clusters-app ships with the canonical test DAC;
        // skip DCL verification until DAC work lands.
        allow_test_attestation: true,
        ..CommissionOptions::default()
    };

    let phase1 = {
        let mut commission_fut = pin!(commissioner.commission(
            Address::Udp(args.peer_addr),
            args.passcode,
            &opts,
            DEVICE_NODE_ID,
            VALID_FOREVER,
        ));
        let mut timeout = pin!(Timer::after(Duration::from_secs(COMMISSION_TIMEOUT_SECS)));
        match select(&mut commission_fut, &mut timeout).await {
            Either::First(r) => r?,
            Either::Second(_) => {
                error!("commission() timed out after {COMMISSION_TIMEOUT_SECS}s");
                return Err(ErrorCode::RxTimeout.into());
            }
        }
    };
    info!(
        "phase 1 ok: device_fabric_index={}, device_node_id=0x{:016x}",
        phase1.fabric_index, phase1.device_node_id,
    );

    info!("=== complete_via_case (phase 2 — discovery + CASE + CommissioningComplete) ===");
    {
        let resolve = rs_matter::transport::exchange::Exchange::resolve_operational_addrs(
            matter,
            controller_fab_idx,
            DEVICE_NODE_ID,
        );
        let candidates =
            match select(pin!(resolve), pin!(Timer::after(Duration::from_secs(60)))).await {
                Either::First(result) => result?,
                Either::Second(_) => return Err(ErrorCode::RxTimeout.into()),
            };
        assert!(
            !candidates.is_empty(),
            "mDNS must discover an operational endpoint"
        );
        println!("Operational mDNS candidates: {candidates:?}");
        let case = pin!(commissioner.complete_via_case(&phase1));
        let mut timeout = pin!(Timer::after(Duration::from_secs(COMMISSION_TIMEOUT_SECS)));
        match select(case, &mut timeout).await {
            Either::First(r) => r?,
            Either::Second(_) => {
                error!("complete_via_case() timed out after {COMMISSION_TIMEOUT_SECS}s");
                return Err(ErrorCode::RxTimeout.into());
            }
        }
    }
    info!("phase 2 ok: CASE established, CommissioningComplete acknowledged");

    // Unlike commissioning alone, verify a visible state change and restore it.
    use rs_matter::dm::clusters::app::on_off::OnOffClient;
    use rs_matter::transport::exchange::Exchange;
    let controls = async {
        let initial = Exchange::initiate(matter, crypto, controller_fab_idx, DEVICE_NODE_ID)
            .await?
            .on_off()
            .on_off_read(1)
            .await?;
        Exchange::initiate(matter, crypto, controller_fab_idx, DEVICE_NODE_ID)
            .await?
            .on_off()
            .toggle(1)
            .await?;
        let changed = Exchange::initiate(matter, crypto, controller_fab_idx, DEVICE_NODE_ID)
            .await?
            .on_off()
            .on_off_read(1)
            .await?;
        // Restore before asserting, to leave the disposable device in its initial state.
        Exchange::initiate(matter, crypto, controller_fab_idx, DEVICE_NODE_ID)
            .await?
            .on_off()
            .toggle(1)
            .await?;
        let restored = Exchange::initiate(matter, crypto, controller_fab_idx, DEVICE_NODE_ID)
            .await?
            .on_off()
            .on_off_read(1)
            .await?;
        assert_ne!(
            initial, changed,
            "Toggle must change the device's reported state"
        );
        assert_eq!(
            initial, restored,
            "The second Toggle must restore the state"
        );
        println!("OnOff verified: {initial} -> {changed} -> {restored}");
        Ok::<(), Error>(())
    };
    match select(pin!(controls), pin!(Timer::after(Duration::from_secs(60)))).await {
        Either::First(result) => result?,
        Either::Second(_) => return Err(ErrorCode::RxTimeout.into()),
    }

    Ok(CommissionResult {
        fabric_index: phase1.fabric_index,
        device_node_id: phase1.device_node_id,
    })
}
