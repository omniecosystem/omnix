// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
#include "omnix_matter.h"
#include "doubles/test_sdk.hpp"
#include <cstdio>
#include <stdexcept>
#define CHECK(value) do { if (!(value)) throw std::runtime_error(#value); } while (false)

namespace {
struct Owner { int leases = 0; };
void Retain(void *owner) { ++static_cast<Owner *>(owner)->leases; }
void Release(void *owner) { --static_cast<Owner *>(owner)->leases; }
void Reset() {
    CHECK(!chip::Test::connection.success && !chip::Test::command.success);
    chip::Test::delayConnection = false;
    chip::Test::delayCommand = false;
    chip::Test::connectError = CHIP_NO_ERROR;
    chip::Test::invokeError = CHIP_NO_ERROR;
    chip::Test::throwOnConnect = false;
    chip::Test::throwOnInvoke = false;
}
void *Attach(const omnix_matter_api_v1 *api, chip::Controller::DeviceController &controller, Owner &owner) {
    void *handle = nullptr;
    CHECK(api->attach(&controller, &owner, Retain, Release, &handle) == 0);
    CHECK(handle && owner.leases == 1);
    return handle;
}
void Complete(const omnix_matter_api_v1 *api, void *handle, uint64_t id, uint32_t expected) {
    uint32_t error = 999;
    CHECK(api->poll(handle, id, &error) == 0 && error == expected);
    CHECK(api->poll(handle, id, &error) == -1);
}
}

// The integration test loads this library through the real Rust loader, then
// invokes these C++ lifetime checks. No device or network traffic is generated.
extern "C" OMNIX_MATTER_EXPORT int32_t omnix_matter_contract_run() noexcept {
    try {
        auto *api = omnix_matter_get_api_v1();
        CHECK(api && api->version == 1 && api->size == sizeof(*api));
        chip::Controller::DeviceController controller;
        Owner owner;
        uint64_t id = 0;
        uint32_t error = 0;

        Reset();
        void *handle = Attach(api, controller, owner);
        CHECK(api->set_on_off(handle, 0, 1, 1, &id) == -1);
        CHECK(api->set_on_off(handle, 42, 1, 2, &id) == -1);
        CHECK(api->set_on_off(handle, 42, 1, 1, &id) == 0 && id != 0);
        Complete(api, handle, id, 0);
        api->close(handle);
        CHECK(owner.leases == 0);

        Reset();
        chip::Test::delayConnection = true;
        chip::Test::delayCommand = true;
        handle = Attach(api, controller, owner);
        CHECK(api->set_on_off(handle, 42, 1, 0, &id) == 0);
        CHECK(api->poll(handle, id, &error) == 1);
        api->close(handle);
        CHECK(owner.leases == 1);
        chip::Test::CompleteConnection(true);
        CHECK(owner.leases == 1);
        chip::Test::CompleteCommand(true);
        CHECK(owner.leases == 0);

        Reset();
        chip::Test::delayConnection = true;
        handle = Attach(api, controller, owner);
        CHECK(api->set_on_off(handle, 42, 1, 0, &id) == 0);
        api->close(handle);
        chip::Test::CompleteConnection(false);
        CHECK(owner.leases == 0);

        Reset();
        chip::Test::delayCommand = true;
        handle = Attach(api, controller, owner);
        CHECK(api->set_on_off(handle, 42, 1, 0, &id) == 0);
        CHECK(api->poll(handle, id, &error) == 1);
        chip::Test::CompleteCommand(false);
        Complete(api, handle, id, 43);
        api->close(handle);
        CHECK(owner.leases == 0);

        Reset();
        chip::Test::delayCommand = true;
        handle = Attach(api, controller, owner);
        CHECK(api->set_on_off(handle, 42, 1, 0, &id) == 0);
        api->close(handle);
        CHECK(owner.leases == 1);
        chip::Test::CompleteCommand(false);
        CHECK(owner.leases == 0);

        Reset();
        chip::Test::connectError = CHIP_ERROR{44};
        handle = Attach(api, controller, owner);
        CHECK(api->set_on_off(handle, 42, 1, 0, &id) == 0);
        Complete(api, handle, id, 44);
        api->close(handle);
        CHECK(owner.leases == 0);

        Reset();
        chip::Test::invokeError = CHIP_ERROR{45};
        handle = Attach(api, controller, owner);
        CHECK(api->set_on_off(handle, 42, 1, 0, &id) == 0);
        Complete(api, handle, id, 45);
        api->close(handle);
        CHECK(owner.leases == 0);

        for (bool connect : {true, false}) {
            Reset();
            chip::Test::throwOnConnect = connect;
            chip::Test::throwOnInvoke = !connect;
            handle = Attach(api, controller, owner);
            CHECK(api->set_on_off(handle, 42, 1, 0, &id) == 0);
            Complete(api, handle, id, CHIP_ERROR_NO_MEMORY.AsInteger());
            api->close(handle);
            CHECK(owner.leases == 0);
        }

        Reset();
        handle = Attach(api, controller, owner);
        for (int i = 0; i != 32; ++i) CHECK(api->set_on_off(handle, 42, 1, 0, &id) == 0);
        const auto lastAccepted = id;
        CHECK(api->set_on_off(handle, 42, 1, 0, &id) == -2);
        CHECK(id == 0);
        Complete(api, handle, lastAccepted, 0);
        CHECK(api->set_on_off(handle, 42, 1, 0, &id) == 0);
        api->close(handle);
        CHECK(owner.leases == 0);
        Reset();
        return 0;
    } catch (const std::exception &error) {
        std::fprintf(stderr, "C++ contract failed: %s\n", error.what());
        return 1;
    } catch (...) { return 2; }
}
