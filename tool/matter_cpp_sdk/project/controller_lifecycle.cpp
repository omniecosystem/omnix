// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
// Disposable SDK-host qualification only: test issuer and volatile credentials.
#include "shim/omnix_matter.h"
#include <app/server-cluster/testing/EmptyProvider.h>
#include <controller/CHIPDeviceControllerFactory.h>
#include <controller/ExampleOperationalCredentialsIssuer.h>
#include <credentials/GroupDataProviderImpl.h>
#include <credentials/PersistentStorageOpCertStore.h>
#include <crypto/PersistentStorageOperationalKeystore.h>
#include <crypto/RawKeySessionKeystore.h>
#include <lib/support/TestPersistentStorageDelegate.h>
#include <lib/support/CHIPMem.h>
#include <lib/core/ErrorStr.h>
#include <platform/PlatformManager.h>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <thread>

namespace {
void Require(bool valid, const char *stage) {
    if (!valid) {
        std::fprintf(stderr, "FAIL: %s\n", stage);
        std::fflush(stderr);
        std::_Exit(EXIT_FAILURE);
    }
}
void Check(CHIP_ERROR error, const char *stage) {
    if (error != CHIP_NO_ERROR) {
        // Preserve the SDK source location. Numeric-only errors hide the
        // initialization step that failed. On fatal partial startup, do not
        // run global SDK destructors on an incompletely initialized stack.
        std::fprintf(stderr, "SDK error at %s: %s\n", stage, chip::ErrorStr(error));
        std::fflush(stderr);
        std::_Exit(EXIT_FAILURE);
    }
}
struct Owner {
    // The host owns the initial reference; hooks never tear down the SDK while
    // a callback or StackLock is active. Host shutdown is explicit below.
    std::atomic<unsigned> references{1};
    static void Retain(void *value) {
        static_cast<Owner *>(value)->references.fetch_add(1);
    }
    static void Release(void *value) {
        static_cast<Owner *>(value)->references.fetch_sub(1);
    }
};
}

int main() {
    using namespace chip;
    Check(Platform::MemoryInit(), "memory startup");
    TestPersistentStorageDelegate storage;
    PersistentStorageOperationalKeystore keys;
    Credentials::PersistentStorageOpCertStore certificates;
    Crypto::RawKeySessionKeystore sessionKeys;
    Credentials::GroupDataProviderImpl groups;
    Testing::EmptyProvider model;
    Controller::ExampleOperationalCredentialsIssuer issuer;
    Crypto::P256Keypair key;
    Controller::DeviceController controller;
    Owner owner;

    Check(keys.Init(&storage), "operational key store");
    Check(certificates.Init(&storage), "certificate store");
    groups.SetStorageDelegate(&storage);
    groups.SetSessionKeystore(&sessionKeys);
    Check(groups.Init(), "group store");
    Credentials::SetGroupDataProvider(&groups);
    Check(issuer.Initialize(storage), "test-only issuer");
    Check(key.Initialize(Crypto::ECPKeyTarget::ECDSA), "ephemeral controller key");
    uint8_t root[Credentials::kMaxDERCertLength];
    uint8_t intermediate[Credentials::kMaxDERCertLength];
    uint8_t operational[Credentials::kMaxDERCertLength];
    MutableByteSpan rcac(root), icac(intermediate), noc(operational);
    Check(issuer.GenerateNOCChainAfterValidation(112233, 1, kUndefinedCATs,
          key.Pubkey(), rcac, icac, noc), "test controller certificates");

    auto &factory = Controller::DeviceControllerFactory::GetInstance();
    Controller::FactoryInitParams init;
    init.fabricIndependentStorage = &storage;
    init.operationalKeystore = &keys;
    init.opCertStore = &certificates;
    init.sessionKeystore = &sessionKeys;
    init.groupDataProvider = &groups;
    init.dataModelProvider = &model;
    Check(DeviceLayer::PlatformMgr().InitChipStack(), "platform stack startup");
    Check(factory.Init(init), "controller factory startup");
    Controller::SetupParams setup;
    setup.operationalCredentialsDelegate = &issuer;
    setup.operationalKeypair = &key;
    setup.controllerRCAC = rcac;
    setup.controllerICAC = icac;
    setup.controllerNOC = noc;
    setup.controllerVendorId = VendorId::TestVendor1;
    Check(factory.SetupController(setup, controller), "operational controller startup");
    Check(factory.ServiceEvents(), "event-loop startup");
    std::atomic<bool> dispatched{false};
    Check(DeviceLayer::PlatformMgr().ScheduleWork([](intptr_t value) {
        reinterpret_cast<std::atomic<bool> *>(value)->store(true);
    }, reinterpret_cast<intptr_t>(&dispatched)), "event-loop callback scheduling");
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (!dispatched.load() && std::chrono::steady_clock::now() < deadline) {
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }
    Require(dispatched.load(), "real event-loop callback dispatch");

    const auto *api = omnix_matter_get_api_v1();
    Require(api && api->version == 1 && api->size == sizeof(*api), "shim ABI");
    for (unsigned cycle = 0; cycle < 8; ++cycle) {
        void *handle = nullptr;
        Require(api->attach(&controller, &owner, Owner::Retain, Owner::Release,
                           &handle) == 0 && handle, "attach initialized controller");
        Require(owner.references.load() == 2, "host retained");
        uint32_t error = 0;
        Require(api->poll(handle, 999, &error) == -1, "unknown operation under real stack lock");
        api->close(handle);
        Require(owner.references.load() == 1, "host released after close");
    }

    // No pending commands in this lifecycle gate. Join the event loop before
    // shutdown: the official SDK expects externally synchronized teardown.
    Check(DeviceLayer::PlatformMgr().StopEventLoopTask(), "event-loop join");
    controller.Shutdown();
    factory.Shutdown();
    groups.Finish();
    Credentials::SetGroupDataProvider(nullptr);
    keys.Finish();
    certificates.Finish();
    Platform::MemoryShutdown();
    std::puts("PASS: real SDK controller startup, callback dispatch, shim attach/close and shutdown");
    std::puts("Volatile test credentials only; no commissioning, device commands or restart persistence tested.");
    return EXIT_SUCCESS;
}
