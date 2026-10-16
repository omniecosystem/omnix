# Copyright 2026 The Omnix Authors
# SPDX-License-Identifier: Apache-2.0
"""Load the actual SDK-linked shim without starting a controller or network."""

import ctypes
import sys


class Api(ctypes.Structure):
    _fields_ = [
        ("version", ctypes.c_uint32),
        ("size", ctypes.c_uint32),
        ("attach", ctypes.c_void_p),
        ("set_on_off", ctypes.c_void_p),
        ("poll", ctypes.c_void_p),
        ("close", ctypes.c_void_p),
    ]


library = ctypes.CDLL(sys.argv[1])
getter = library.omnix_matter_get_api_v1
getter.argtypes = []
getter.restype = ctypes.POINTER(Api)
pointer = getter()
if not pointer:
    raise RuntimeError("ABI getter returned null")
api = pointer.contents
if api.version != 1 or api.size != ctypes.sizeof(Api):
    raise RuntimeError("Unexpected ABI version/size")
if not all((api.attach, api.set_on_off, api.poll, api.close)):
    raise RuntimeError("ABI table contains a null function")
print("PASS: SDK-linked library loads and exposes the complete v1 ABI")
