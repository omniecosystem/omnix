// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
#pragma once
// Minimal authored test doubles for the SDK surfaces the production shim uses.
// These are NEVER included by the production GN target.
#include <cstdint>
#include <functional>
#include <stdexcept>
#include <utility>

struct CHIP_ERROR {
    uint32_t value;
    uint32_t AsInteger() const { return value; }
    bool operator!=(CHIP_ERROR other) const { return value != other.value; }
};
inline constexpr CHIP_ERROR CHIP_NO_ERROR{0};
inline constexpr CHIP_ERROR CHIP_ERROR_NO_MEMORY{1};
namespace chip {
struct ScopedNodeId {};
struct SessionHandle {};
namespace Messaging { struct ExchangeManager {}; }
using OnDeviceConnected = void(void *, Messaging::ExchangeManager &, const SessionHandle &);
using OnDeviceConnectionFailure = void(void *, const ScopedNodeId &, CHIP_ERROR);
namespace Callback {
template<class Function> struct Callback {
    Function *function;
    void *context;
    Callback(Function *fn, void *ctx) : function(fn), context(ctx) {}
};
}
namespace DeviceLayer {
// This double does not prove actual SDK threading/locking behavior.
struct StackLock {};
}
namespace app::Clusters::OnOff::Commands {
struct On { struct Type {}; };
struct Off { struct Type {}; };
}
namespace Test {
struct Pending {
    std::function<void()> success;
    std::function<void(CHIP_ERROR)> failure;
};
inline bool delayConnection = false;
inline bool delayCommand = false;
inline CHIP_ERROR connectError{0};
inline CHIP_ERROR invokeError{0};
inline bool throwOnConnect = false;
inline bool throwOnInvoke = false;
inline Pending connection;
inline Pending command;
inline void CompleteConnection(bool success) {
    // Move callbacks out before running them: the callback may release the
    // request that owns the raw callback pointers.
    auto current = std::move(connection);
    connection = {};
    if (success) current.success(); else current.failure(CHIP_ERROR{42});
}
inline void CompleteCommand(bool success) {
    auto current = std::move(command);
    command = {};
    if (success) current.success(); else current.failure(CHIP_ERROR{43});
}
}
namespace Controller {
struct DeviceController {
    CHIP_ERROR GetConnectedDevice(uint64_t, Callback::Callback<OnDeviceConnected> *connected,
                                   Callback::Callback<OnDeviceConnectionFailure> *failed) {
        if (Test::throwOnConnect) throw std::bad_alloc();
        if (Test::connectError != CHIP_NO_ERROR) return Test::connectError;
        auto success = [connected] {
            Messaging::ExchangeManager manager;
            SessionHandle session;
            connected->function(connected->context, manager, session);
        };
        if (Test::delayConnection) {
            Test::connection = {success, [failed](CHIP_ERROR error) {
                failed->function(failed->context, ScopedNodeId{}, error);
            }};
        } else success();
        return CHIP_NO_ERROR;
    }
};
template<class Command, class Success, class Failure>
CHIP_ERROR InvokeCommandRequest(Messaging::ExchangeManager *, const SessionHandle &,
                               uint16_t, Command, Success success, Failure failure) {
    if (Test::throwOnInvoke) throw std::bad_alloc();
    if (Test::invokeError != CHIP_NO_ERROR) return Test::invokeError;
    auto complete = [success] { success(0, 0, 0); };
    if (Test::delayCommand) Test::command = {complete, failure};
    else complete();
    return CHIP_NO_ERROR;
}
}
}
