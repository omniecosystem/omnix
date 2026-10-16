// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0
fn main() {
    #[cfg(feature = "litertlm")]
    litertlm_bundle::prepare().expect("LiteRT-LM native delivery failed");
    #[cfg(feature = "llamacpp")]
    {
        // No network acquisition or external runtime wrapper: build the pinned
        // upstream C/C++ implementation and link its public C API directly.
        println!("cargo:rerun-if-changed=vendor/llama.cpp");
        let mut builder = cmake::Config::new("vendor/llama.cpp");
        let target = std::env::var("TARGET").unwrap();
        if target.contains("msvc") {
            let static_crt = std::env::var("CARGO_CFG_TARGET_FEATURE")
                .unwrap_or_default()
                .split(',')
                .any(|feature| feature == "crt-static");
            // Match Rust's CRT choice; mixing /MD and /MT is not a safe fix.
            builder.define("CMAKE_POLICY_DEFAULT_CMP0091", "NEW");
            builder.define(
                "CMAKE_MSVC_RUNTIME_LIBRARY",
                if static_crt {
                    "MultiThreaded"
                } else {
                    "MultiThreadedDLL"
                },
            );
        }
        let dst = builder
            .profile("Release")
            .define("BUILD_SHARED_LIBS", "OFF")
            .define("LLAMA_BUILD_COMMON", "OFF")
            .define("LLAMA_BUILD_TESTS", "OFF")
            .define("LLAMA_BUILD_TOOLS", "OFF")
            .define("LLAMA_BUILD_EXAMPLES", "OFF")
            .define("LLAMA_BUILD_SERVER", "OFF")
            .define("LLAMA_BUILD_APP", "OFF")
            .define("LLAMA_OPENSSL", "OFF")
            .define("GGML_NATIVE", "OFF")
            .define("GGML_OPENMP", "OFF")
            .define("GGML_CUDA", "OFF")
            .define("GGML_METAL", "OFF")
            .define("GGML_VULKAN", "OFF")
            .define("GGML_BACKEND_DL", "OFF")
            .build();
        for dir in ["lib", "lib64"] {
            println!("cargo:rustc-link-search=native={}", dst.join(dir).display());
        }
        for lib in ["llama", "ggml", "ggml-cpu", "ggml-base"] {
            println!("cargo:rustc-link-lib=static={lib}");
        }
        if target.contains("windows") {
            println!("cargo:rustc-link-lib=advapi32");
        }
        if target.contains("apple") {
            println!("cargo:rustc-link-lib=c++");
            println!("cargo:rustc-link-lib=framework=Accelerate");
        } else if !target.contains("msvc") {
            println!("cargo:rustc-link-lib=stdc++");
            println!("cargo:rustc-link-lib=m");
            if target.contains("linux") {
                println!("cargo:rustc-link-lib=dl");
            }
        }
    }
}

#[cfg(feature = "litertlm")]
#[path = "build_support/litertlm_bundle.rs"]
mod litertlm_bundle;
