// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

use sha2::{Digest, Sha256};
use std::{error::Error, fs, path::PathBuf};

fn main() -> Result<(), Box<dyn Error>> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    if std::env::args().any(|arg| arg == "--embedding-engine") {
        let vendor = root.join("vendor/litertlm_embedding");
        for (file, expected) in [
            (
                "c/api_export.h",
                "97489762c154658c6180d44c0a4b3479781cfe982a42920221189fe587e40637",
            ),
            (
                "c/engine.h",
                "41c38c182e736f3c239785b474e7c9d145cd711a1d5dc9882f403e0319953584",
            ),
            (
                "c/embedding_engine.h",
                "54a5d82516c71529c42f86a031605dc47bdf5ee5c7379be65bf1dd0fae22d512",
            ),
        ] {
            if format!("{:x}", Sha256::digest(fs::read(vendor.join(file))?)) != expected {
                return Err(format!("Pinned embedding engine header changed: {file}").into());
            }
        }
        let bindings = bindgen::Builder::default()
            .header(vendor.join("c/embedding_engine.h").to_string_lossy())
            .clang_arg(format!("-I{}", vendor.display()))
            .allowlist_function("litert_lm_(embedding_engine_(settings_create|settings_delete|settings_set_max_input_length|settings_set_activation_data_type|create|delete|compute_embedding)|embedding_options_(create|delete|set_normalize|set_insert_special_tokens|set_input_overflow_strategy|set_output_size)|embedding_response_(delete|get_size|get_values)|input_data_(create|delete))")
            .dynamic_library_name("LiteRtLmEmbeddingApi")
            .dynamic_link_require_all(true)
            .generate_comments(false).layout_tests(false)
            .formatter(bindgen::Formatter::Rustfmt)
            .raw_line("// Copyright 2026 The Omnix Authors")
            .raw_line("// SPDX-License-Identifier: Apache-2.0")
            .raw_line("// Generated from LiteRT-LM b2f686e2 (v0.18.0); do not edit.")
            .generate()?;
        let output = root.join("src/litertlm_embedding_bindings.rs");
        if std::env::args().any(|arg| arg == "--check") {
            if fs::read_to_string(output)? != bindings.to_string() {
                return Err("Generated embedding engine bindings differ".into());
            }
        } else {
            bindings.write_to_file(output)?;
        }
        return Ok(());
    }
    if std::env::args().any(|arg| arg == "--embedding") {
        let vendor = root.join("vendor/litert");
        for (file, expected) in [
            (
                "litert/c/litert_environment.h",
                "a83820ef9e68bd175db75a7ef155ce67f5bab2e7ad04e6b046affe9ee3366b3d",
            ),
            (
                "litert/c/litert_model.h",
                "c409c985fc79b9f967890e475e28ab77c1fe7776874197a598438a7b2d916d8b",
            ),
            (
                "litert/c/litert_options.h",
                "d7ff502b26c7f54574b351a5afbc247e639843bcb4270d0615d38abbde503d9a",
            ),
            (
                "litert/c/litert_compiled_model.h",
                "e613c98b5299b0c3c130c883963d29f98a6f0b2dccc66c73b8a10bdccdcac13b",
            ),
            (
                "litert/c/litert_tensor_buffer.h",
                "2e45153e2d8510e2570f7965b2c46403445786b535c542f077ac9afda78b1274",
            ),
            (
                "litert/c/litert_layout.h",
                "c16011a88f7487fa6d3e386905317cf9491d1666d5c7a7ed33e07a9f8b4cf514",
            ),
            (
                "litert/c/litert_model_types.h",
                "01cf6ea792a7f6f55690fe7acfd8d41f5a707c8ea7cb7418f71e44c84d45757a",
            ),
            (
                "litert/c/litert_common.h",
                "d5c4a54c62f4018ce6a536e4ff600fec931aa729824d28e58c39de30fd221856",
            ),
        ] {
            if format!("{:x}", Sha256::digest(fs::read(vendor.join(file))?)) != expected {
                return Err(format!("Pinned LiteRT header changed: {file}").into());
            }
        }
        let bindings = bindgen::Builder::default()
            .header(root.join("tool/bindings-generator/include/embedding.h").to_string_lossy())
            .clang_arg(format!("-I{}", vendor.display()))
            .clang_arg(format!("-I{}", root.join("tool/bindings-generator/include").display()))
            .allowlist_function("LiteRt(CreateEnvironment|DestroyEnvironment|CreateModelFromFile|DestroyModel|GetModelSignature|GetNumSignatureInputs|GetNumSignatureOutputs|GetSignatureInputTensorByIndex|GetSignatureOutputTensorByIndex|GetRankedTensorType|CreateOptions|DestroyOptions|SetOptionsHardwareAccelerators|CreateCompiledModel|DestroyCompiledModel|GetCompiledModelInputTensorLayout|GetCompiledModelOutputTensorLayouts|CreateTensorBufferFromHostMemory|DestroyTensorBuffer|RunCompiledModel|LockTensorBuffer|UnlockTensorBuffer)")
            .dynamic_library_name("LiteRtEmbeddingApi")
            .dynamic_link_require_all(true)
            .generate_comments(false).layout_tests(false)
            .formatter(bindgen::Formatter::Rustfmt)
            .raw_line("// Generated from LiteRT 9fe5be45564c868408e6514c8aabb83e211a0911; do not edit.")
            .generate()?;
        let output = root.join("src/litert_embedding_bindings.rs");
        if std::env::args().any(|arg| arg == "--check") {
            if fs::read_to_string(output)? != bindings.to_string() {
                return Err("Generated embedding bindings differ".into());
            }
        } else {
            bindings.write_to_file(output)?;
        }
        return Ok(());
    }
    if std::env::args().any(|arg| arg == "--llama") {
        let vendor = root.join("vendor/llama.cpp");
        if format!(
            "{:x}",
            Sha256::digest(fs::read(vendor.join("include/llama.h"))?)
        ) != "0199c9f12a5dd4099191a9b508d62ad715212981d181046a0d29750c57dd8694"
        {
            return Err("Pinned llama.cpp header changed".into());
        }
        let bindings = bindgen::Builder::default()
            .header(vendor.join("include/llama.h").to_string_lossy())
            .clang_arg(format!("-I{}", vendor.join("ggml/include").display()))
            .allowlist_function("llama_(backend_init|log_set|model_default_params|model_load_from_file|model_free|model_chat_template|model_get_vocab|context_default_params|init_from_model|free|batch_init|batch_free|decode|tokenize|token_to_piece|vocab_is_eog|sampler_chain_default_params|sampler_chain_init|sampler_chain_add|sampler_init_top_k|sampler_init_top_p|sampler_init_temp|sampler_init_dist|sampler_init_greedy|sampler_free|sampler_sample|sampler_accept)")
            .generate_comments(false).layout_tests(false)
            .formatter(bindgen::Formatter::Rustfmt)
            .raw_line("// Copyright 2026 The Omnix Authors")
            .raw_line("// SPDX-License-Identifier: Apache-2.0")
            .raw_line("// Generated from llama.cpp 26394b4e6749a41c3633db040e0987500a5f7013; do not edit.")
            .allowlist_function("llama_chat_apply_template")
            .generate()?;
        let output = root.join("src/llamacpp_bindings.rs");
        if std::env::args().any(|arg| arg == "--check") {
            if fs::read_to_string(output)? != bindings.to_string() {
                return Err("Generated llama bindings differ".into());
            }
        } else {
            bindings.write_to_file(output)?;
        }
        return Ok(());
    }
    let vendor = root.join("vendor/litertlm");
    for (file, expected) in [
        (
            "c/engine.h",
            "30cfcb49f838a9e9637289f7c7f696b38e4112e3da5edb173cf6b46c749e2c9c",
        ),
        (
            "c/conversation.h",
            "3746b206d0d75817228f20061c5ecef2ed5b59f0893b95701a57fbd60b77cde1",
        ),
    ] {
        if format!("{:x}", Sha256::digest(fs::read(vendor.join(file))?)) != expected {
            return Err(format!("Pinned upstream header changed: {file}").into());
        }
    }
    // Deliberately bind only the surface the adapter implements. Adding a
    // symbol here requires corresponding lifecycle/capability qualification.
    let functions = [
        "engine_settings_create",
        "engine_settings_delete",
        "engine_settings_set_max_num_tokens",
        "engine_settings_set_cache_dir",
        "engine_settings_set_litert_dispatch_lib_dir",
        "engine_create",
        "engine_delete",
        "session_config_create",
        "session_config_set_max_output_tokens",
        "session_config_set_sampler_params",
        "sampler_params_create",
        "sampler_params_delete",
        "sampler_params_set_temperature",
        "sampler_params_set_top_k",
        "sampler_params_set_top_p",
        "sampler_params_set_seed",
        "session_config_delete",
        "conversation_config_create",
        "conversation_config_set_session_config",
        "conversation_config_set_system_message",
        "conversation_config_set_messages",
        "conversation_config_set_tools",
        "conversation_config_set_thinking_config",
        "conversation_config_set_enable_constrained_decoding",
        "conversation_config_delete",
        "thinking_config_create",
        "thinking_config_set_enable_thinking",
        "thinking_config_delete",
        "conversation_create",
        "conversation_delete",
        "conversation_send_message",
        "conversation_send_message_stream",
        "conversation_cancel_process",
        "stream_chunk_get_text",
        "stream_chunk_is_final",
        "stream_chunk_get_error",
        "json_response_get_string",
        "json_response_delete",
    ];
    let pattern = format!("litert_lm_({})", functions.join("|"));
    let bindings = bindgen::Builder::default()
        .header(vendor.join("c/conversation.h").to_string_lossy())
        .clang_arg(format!("-I{}", vendor.display()))
        .allowlist_function(pattern)
        .dynamic_library_name("LiteRtLm")
        .dynamic_link_require_all(true)
        .generate_comments(false)
        .layout_tests(false)
        .formatter(bindgen::Formatter::Rustfmt)
        .raw_line("// Copyright 2026 The Omnix Authors")
        .raw_line("// SPDX-License-Identifier: Apache-2.0")
        .raw_line("// Generated from upstream LiteRT-LM 5e58e9a0 (v0.17.1). Do not edit.")
        .generate()?;
    let output = root.join("src/litertlm_bindings.rs");
    if std::env::args().any(|arg| arg == "--check") {
        if fs::read_to_string(&output)? != bindings.to_string() {
            return Err("Generated bindings differ; regenerate and review".into());
        }
    } else {
        bindings.write_to_file(output)?;
    }
    Ok(())
}
