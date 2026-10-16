// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Experimental controller for the upstream disposable software fixture.
//! Explicitly allows test attestation and requires simulator consent on each
//! commission; this is not a production device commissioner.

mod mdns;
mod state;

/// A durable simulator pairing, independent of the Flutter bridge.
#[derive(Clone, serde::Serialize, serde::Deserialize)]
pub struct MatterDevice {
    pub node_id: String,
    pub name: String,
    pub endpoint: u16,
    pub operational: bool,
}
use core::num::NonZeroU8;
use rs_matter::{
    cert::{gen::VALID_FOREVER, MAX_CERT_TLV_AND_ASN1_LEN, MAX_CERT_TLV_LEN},
    crypto::{
        default_crypto, CanonAeadKey, CanonPkcSecretKey, Crypto, Rng as _, SecretKey,
        SigningSecretKey,
    },
    dm::{
        clusters::app::on_off::OnOffClient,
        devices::test::{DAC_PRIVKEY, TEST_DEV_ATT, TEST_DEV_COMM, TEST_DEV_DET},
    },
    error::{Error, ErrorCode},
    onboard::{
        cac::{IcacGenerator, RcacGenerator},
        noc::NocGenerator,
        CommissionOptions, Commissioner,
    },
    transport::{
        exchange::Exchange,
        network::{Address, NoNetwork},
    },
    Matter,
};
use serde_json::{json, Value};
use state::ControllerState;
use std::{
    collections::HashMap,
    net::{SocketAddr, UdpSocket},
    sync::{
        atomic::{AtomicU64, Ordering},
        Mutex, OnceLock,
    },
};
use tokio::sync::oneshot;

type Reply = oneshot::Sender<Result<String, String>>;
struct Command {
    operation: String,
    arguments: Value,
    reply: Reply,
}
static HANDLES: OnceLock<Mutex<HashMap<u64, async_channel::Sender<Command>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
fn handles() -> &'static Mutex<HashMap<u64, async_channel::Sender<Command>>> {
    HANDLES.get_or_init(|| Mutex::new(HashMap::new()))
}

pub async fn open(directory: String) -> Result<u64, String> {
    let (sender, receiver) = async_channel::bounded(16);
    let (ready_tx, ready_rx) = oneshot::channel();
    let id = NEXT.fetch_add(1, Ordering::Relaxed);
    std::thread::Builder::new()
        .name("omnix-matter".into())
        .stack_size(16 * 1024 * 1024)
        .spawn(move || {
            let mut ready = Some(ready_tx);
            let result = futures_lite::future::block_on(run(directory, receiver, &mut ready));
            if let Some(ready) = ready {
                let _ = ready.send(result.map(|_| ()));
            }
        })
        .map_err(|_| "Could not start the Matter worker")?;
    ready_rx
        .await
        .map_err(|_| "Matter worker stopped during startup")??;
    handles()
        .lock()
        .map_err(|_| "Matter registry unavailable")?
        .insert(id, sender);
    Ok(id)
}

pub async fn request(id: u64, operation: String, arguments: String) -> Result<String, String> {
    if arguments.len() > 4096 {
        return Err("Matter request is too large".into());
    }
    let arguments: Value =
        serde_json::from_str(&arguments).map_err(|_| "Invalid Matter arguments")?;
    let sender = handles()
        .lock()
        .map_err(|_| "Matter registry unavailable")?
        .get(&id)
        .cloned()
        .ok_or("Matter controller is closed")?;
    let (reply, result) = oneshot::channel();
    sender
        .send(Command {
            operation,
            arguments,
            reply,
        })
        .await
        .map_err(|_| "Matter worker is closed")?;
    result.await.map_err(|_| "Matter worker stopped")?
}

pub async fn close(id: u64) -> Result<(), String> {
    let sender = handles()
        .lock()
        .map_err(|_| "Matter registry unavailable")?
        .remove(&id);
    if let Some(sender) = sender {
        let (reply, result) = oneshot::channel();
        if sender
            .send(Command {
                operation: "close".into(),
                arguments: Value::Null,
                reply,
            })
            .await
            .is_ok()
        {
            result.await.map_err(|_| "Matter worker stopped")??;
        }
        sender.close();
    }
    Ok(())
}

async fn run(
    directory: String,
    commands: async_channel::Receiver<Command>,
    ready: &mut Option<oneshot::Sender<Result<(), String>>>,
) -> Result<(), String> {
    let mut state = ControllerState::open(&directory)?;
    let crypto = default_crypto(rand_matter::rng(), DAC_PRIVKEY);
    let matter = Matter::new(&TEST_DEV_DET, TEST_DEV_COMM, &TEST_DEV_ATT, 0);
    if state.identity.is_none() {
        state.identity = Some(
            create_identity(&crypto)
                .map_err(|e| format!("Matter identity initialization failed: {e}"))?,
        );
        state.save()?;
    }
    let identity = state.identity.as_ref().ok_or("Missing Matter identity")?;
    let mut private_key = CanonPkcSecretKey::new();
    private_key
        .try_load_from_slice(&identity.private_key)
        .map_err(|_| "Invalid stored operational key")?;
    let mut ipk = CanonAeadKey::new();
    ipk.try_load_from_slice(&identity.ipk)
        .map_err(|_| "Invalid stored IPK")?;
    let fab = matter
        .with_state(|s| {
            s.fabrics
                .add(
                    &crypto,
                    private_key.reference(),
                    &identity.rcac,
                    &identity.noc,
                    &identity.icac,
                    Some(ipk.reference()),
                    0xfff1,
                    112233,
                )
                .map(|f| f.fab_idx())
        })
        .map_err(|_| "Could not restore Matter fabric; no credentials were replaced")?;
    let socket = socket2::Socket::new(
        socket2::Domain::IPV6,
        socket2::Type::DGRAM,
        Some(socket2::Protocol::UDP),
    )
    .map_err(|e| e.to_string())?;
    socket.set_only_v6(false).map_err(|e| e.to_string())?;
    socket
        .bind(&"[::]:0".parse::<SocketAddr>().unwrap().into())
        .map_err(|e| e.to_string())?;
    let socket =
        async_io::Async::<UdpSocket>::new_nonblocking(socket.into()).map_err(|e| e.to_string())?;
    let hostname = format!("omnix-{:016x}", rand_matter::random::<u64>());
    if let Some(ready) = ready.take() {
        let _ = ready.send(Ok(()));
    }
    let transport = embassy_futures_select(
        matter.run(&crypto, &socket, &socket, NoNetwork),
        mdns::run_mdns(&matter, &crypto, &hostname),
    );
    let operations = async {
        while let Ok(command) = commands.recv().await {
            if command.operation == "close" {
                // Drop sockets and the directory lock before acknowledging close.
                return Ok(Some(command.reply));
            }
            let result = execute(
                &matter,
                &crypto,
                fab,
                &mut state,
                &command.operation,
                command.arguments,
            )
            .await;
            let _ = command.reply.send(result.map(|v| v.to_string()));
        }
        Ok::<_, String>(None)
    };
    let result = futures_lite::future::race(
        async {
            transport
                .await
                .map_err(|e| format!("Matter network stopped: {e}"))
                .map(|_| None)
        },
        operations,
    )
    .await;
    drop(socket);
    drop(state);
    if let Some(reply) = result? {
        let _ = reply.send(Ok("null".into()));
    }
    Ok(())
}

async fn embassy_futures_select<A, B>(a: A, b: B) -> Result<(), Error>
where
    A: std::future::Future<Output = Result<(), Error>>,
    B: std::future::Future<Output = Result<(), Error>>,
{
    futures_lite::future::race(a, b).await
}

fn create_identity<C: Crypto>(crypto: &C) -> Result<state::Identity, Error> {
    let mut rcac_buf = [0; MAX_CERT_TLV_AND_ASN1_LEN];
    let mut rcac_gen = RcacGenerator::new(&mut rcac_buf);
    let (root, rcac) = rcac_gen.generate(crypto, 1, VALID_FOREVER)?;
    let mut icac_buf = [0; MAX_CERT_TLV_AND_ASN1_LEN];
    let mut icac_gen = IcacGenerator::new(&mut icac_buf);
    let (signer, icac) = icac_gen.generate(crypto, root.reference(), rcac, VALID_FOREVER)?;
    let private = crypto.generate_secret_key()?;
    let mut csr_buf = [0; 256];
    let csr = private.csr(&mut csr_buf)?;
    let mut canonical = CanonPkcSecretKey::new();
    private.write_canon(&mut canonical)?;
    let mut noc_buf = [0; MAX_CERT_TLV_AND_ASN1_LEN];
    let mut generator = NocGenerator::create(signer.reference(), rcac, icac, &mut noc_buf)?;
    let noc = generator.generate(crypto, csr, 112233, &[], VALID_FOREVER)?;
    let mut ipk = CanonAeadKey::new();
    crypto.rand()?.fill_bytes(ipk.access_mut());
    Ok(state::Identity {
        rcac: rcac.to_vec(),
        icac: icac.to_vec(),
        noc: noc.to_vec(),
        private_key: canonical.access().to_vec(),
        signer: signer.access().to_vec(),
        ipk: ipk.access().to_vec(),
    })
}

async fn execute<C: Crypto>(
    matter: &Matter<'_>,
    crypto: &C,
    fab: NonZeroU8,
    state: &mut ControllerState,
    operation: &str,
    args: Value,
) -> Result<Value, String> {
    if operation == "list" {
        return serde_json::to_value(&state.devices).map_err(|e| e.to_string());
    }
    if operation == "commission" {
        if args["simulatorConsent"] != true {
            return Err(
                "Production device attestation is not implemented; simulator consent is required"
                    .into(),
            );
        }
        let address = args["address"]
            .as_str()
            .ok_or("Missing address")?
            .parse::<SocketAddr>()
            .map_err(|_| "Enter an IP address and port, not a URL")?;
        let passcode = u32::try_from(args["passcode"].as_u64().ok_or("Invalid passcode")?)
            .map_err(|_| "Invalid passcode")?;
        // Public upstream fixture passcode, not a consumer device credential.
        if passcode != 20202021 {
            return Err(
                "This experimental adapter only commissions the disposable test fixture".into(),
            );
        }
        let name = args["name"].as_str().ok_or("Missing device name")?.trim();
        if name.is_empty() || name.len() > 128 {
            return Err("Invalid device name".into());
        }
        let node_id = state.next_node;
        state.next_node = state.next_node.checked_add(1).ok_or("Node IDs exhausted")?;
        let device = MatterDevice {
            node_id: node_id.to_string(),
            name: name.into(),
            endpoint: 1,
            operational: false,
        };
        state.devices.push(device.clone());
        state.save()?;
        let identity = state.identity.as_ref().ok_or("Missing fabric")?;
        let mut signer = CanonPkcSecretKey::new();
        signer
            .try_load_from_slice(&identity.signer)
            .map_err(|_| "Invalid stored issuer key")?;
        let mut noc = [0; MAX_CERT_TLV_AND_ASN1_LEN];
        let mut generator =
            NocGenerator::create(signer.reference(), &identity.rcac, &identity.icac, &mut noc)
                .map_err(|_| "Invalid stored issuer")?;
        let mut buf = [0; MAX_CERT_TLV_LEN];
        let mut commissioner = Commissioner::new(matter, crypto, fab, &mut generator, &mut buf);
        let flow = async {
            let phase = commissioner
                .commission(
                    Address::Udp(address),
                    passcode,
                    &CommissionOptions {
                        allow_test_attestation: true,
                        ..Default::default()
                    },
                    node_id,
                    VALID_FOREVER,
                )
                .await?;
            commissioner.complete_via_case(&phase).await
        };
        bounded(flow)
            .await
            .map_err(|e| format!("Simulator commissioning failed: {e}; pending record retained"))?;
        let index = state.devices.len() - 1;
        state.devices[index].operational = true;
        state.save()?;
        return serde_json::to_value(&state.devices[index]).map_err(|e| e.to_string());
    }
    let id = args["nodeId"].as_str().ok_or("Missing device ID")?;
    let device = state
        .devices
        .iter()
        .find(|d| d.node_id == id && d.operational)
        .ok_or("Device is not an operational pairing")?;
    let node = id.parse::<u64>().map_err(|_| "Invalid device ID")?;
    let endpoint = device.endpoint;
    let action = async {
        let exchange = Exchange::initiate(matter, crypto, fab, node).await?;
        match operation {
            "read" => Ok(json!(exchange.on_off().on_off_read(endpoint).await?)),
            "set" => {
                let on = args["on"]
                    .as_bool()
                    .ok_or(Error::from(ErrorCode::InvalidData))?;
                if on {
                    exchange.on_off().on(endpoint).await?;
                } else {
                    exchange.on_off().off(endpoint).await?;
                }
                Ok(Value::Null)
            }
            _ => Err(ErrorCode::InvalidData.into()),
        }
    };
    bounded(action)
        .await
        .map_err(|e| format!("Matter operation failed: {e}"))
}

async fn bounded<T>(
    future: impl std::future::Future<Output = Result<T, Error>>,
) -> Result<T, Error> {
    futures_lite::future::race(future, async {
        embassy_time::Timer::after(embassy_time::Duration::from_secs(60)).await;
        Err(ErrorCode::RxTimeout.into())
    })
    .await
}
