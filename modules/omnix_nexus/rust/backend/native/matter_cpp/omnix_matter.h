// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
#ifndef OMNIX_MATTER_H
#define OMNIX_MATTER_H
#include <stdint.h>
#if defined(_WIN32)
#define OMNIX_MATTER_EXPORT __declspec(dllexport)
#else
#define OMNIX_MATTER_EXPORT __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif

// Host supplies a live official DeviceController and a retained platform owner.
// Retain/release must not throw. Release must defer SDK shutdown until the
// current SDK callback/stack-lock scope has unwound. No commissioning bypass.
typedef void (*omnix_matter_owner_fn)(void *);
typedef struct omnix_matter_api_v1 {
    uint32_t version;
    uint32_t size;
    int32_t (*attach)(void *controller, void *owner, omnix_matter_owner_fn retain,
                      omnix_matter_owner_fn release, void **out_handle);
    int32_t (*set_on_off)(void *handle, uint64_t node, uint16_t endpoint,
                         uint8_t value, uint64_t *out_operation);
    // 1: pending; 0: completed (consumes ID, writes SDK error, zero = success).
    // Negative values are bridge errors; no C++ exception crosses this ABI.
    int32_t (*poll)(void *handle, uint64_t operation, uint32_t *out_sdk_error);
    // Invalidates the handle. Pending native callbacks retain the host owner.
    void (*close)(void *handle);
} omnix_matter_api_v1;

OMNIX_MATTER_EXPORT const omnix_matter_api_v1 *omnix_matter_get_api_v1(void);
#ifdef __cplusplus
}
#endif
#endif
