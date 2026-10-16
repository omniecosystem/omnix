// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
#include "omnix_matter.h"
#include <controller/CHIPDeviceController.h>
#include <controller/InvokeInteraction.h>
#include <platform/PlatformManager.h>
#include <app-common/zap-generated/cluster-objects.h>
#include <memory>
#include <unordered_map>

namespace {
using chip::Controller::DeviceController;
struct Request;
struct State {
    DeviceController *controller = nullptr;
    void *owner = nullptr;
    omnix_matter_owner_fn release = nullptr;
    uint64_t next = 1;
    std::unordered_map<uint64_t, std::shared_ptr<Request>> requests;
    ~State() { if (release) release(owner); }
};
struct Handle { std::shared_ptr<State> state; };
struct Request : std::enable_shared_from_this<Request> {
    std::shared_ptr<State> state;
    std::shared_ptr<Request> connectionLease;
    uint16_t endpoint;
    bool on;
    bool done = false;
    uint32_t error = 0;
    chip::Callback::Callback<chip::OnDeviceConnected> connected;
    chip::Callback::Callback<chip::OnDeviceConnectionFailure> failed;
    Request(std::shared_ptr<State> s, uint16_t ep, bool value)
        : state(std::move(s)), endpoint(ep), on(value), connected(OnConnected, this), failed(OnFailed, this) {}
    void Finish(CHIP_ERROR result) noexcept { error = result.AsInteger(); done = true; }
    static void OnFailed(void *context, const chip::ScopedNodeId &, CHIP_ERROR error) noexcept {
        auto *request = static_cast<Request *>(context);
        auto keep = request->shared_from_this();
        request->Finish(error);
        request->connectionLease.reset();
    }
    template<typename Command>
    void Invoke(chip::Messaging::ExchangeManager &manager, const chip::SessionHandle &session) {
        auto keep = shared_from_this();
        auto result = chip::Controller::InvokeCommandRequest(&manager, session, endpoint, Command{},
            [keep](const auto &, const auto &, const auto &) { keep->Finish(CHIP_NO_ERROR); },
            [keep](CHIP_ERROR commandError) { keep->Finish(commandError); });
        if (result != CHIP_NO_ERROR) Finish(result);
    }
    static void OnConnected(void *context, chip::Messaging::ExchangeManager &manager,
                            const chip::SessionHandle &session) noexcept {
        auto *request = static_cast<Request *>(context);
        auto keep = request->shared_from_this();
        try {
            if (request->on) request->Invoke<chip::app::Clusters::OnOff::Commands::On::Type>(manager, session);
            else request->Invoke<chip::app::Clusters::OnOff::Commands::Off::Type>(manager, session);
        } catch (...) { request->Finish(CHIP_ERROR_NO_MEMORY); }
        request->connectionLease.reset();
    }
};

int32_t Attach(void *controller, void *owner, omnix_matter_owner_fn retain,
               omnix_matter_owner_fn release, void **output) noexcept {
    if (!controller || !owner || !retain || !release || !output) return -1;
    *output = nullptr;
    try {
        chip::DeviceLayer::StackLock lock;
        auto state = std::make_shared<State>();
        state->controller = static_cast<DeviceController *>(controller);
        state->owner = owner;
        state->release = release;
        retain(owner);
        auto handle = std::make_unique<Handle>();
        handle->state = std::move(state);
        *output = handle.release();
        return 0;
    } catch (...) { return -3; }
}
int32_t SetOnOff(void *opaque, uint64_t node, uint16_t endpoint, uint8_t value, uint64_t *output) noexcept {
    if (!opaque || !output || node == 0 || value > 1) return -1;
    *output = 0;
    try {
        chip::DeviceLayer::StackLock lock;
        auto state = static_cast<Handle *>(opaque)->state;
        if (state->requests.size() >= 32 || state->next == 0) return -2;
        const uint64_t id = state->next++;
        auto request = std::make_shared<Request>(state, endpoint, value != 0);
        state->requests.emplace(id, request);
        request->connectionLease = request;
        CHIP_ERROR result;
        try { result = state->controller->GetConnectedDevice(node, &request->connected, &request->failed); }
        catch (...) { result = CHIP_ERROR_NO_MEMORY; }
        if (result != CHIP_NO_ERROR) {
            request->Finish(result);
            request->connectionLease.reset();
        }
        *output = id;
        return 0;
    } catch (...) { return -3; }
}
int32_t Poll(void *opaque, uint64_t id, uint32_t *error) noexcept {
    if (!opaque || !error) return -1;
    chip::DeviceLayer::StackLock lock;
    auto state = static_cast<Handle *>(opaque)->state;
    auto found = state->requests.find(id);
    if (found == state->requests.end()) return -1;
    if (!found->second->done) return 1;
    *error = found->second->error;
    state->requests.erase(found);
    return 0;
}
void Close(void *opaque) noexcept {
    if (!opaque) return;
    chip::DeviceLayer::StackLock lock;
    auto *handle = static_cast<Handle *>(opaque);
    handle->state->requests.clear();
    delete handle;
}
const omnix_matter_api_v1 api = {1, sizeof(omnix_matter_api_v1), Attach, SetOnOff, Poll, Close};
}
extern "C" const omnix_matter_api_v1 *omnix_matter_get_api_v1() { return &api; }
