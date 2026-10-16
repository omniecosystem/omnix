// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

use omnix_core::{validate_history, CoreError};

#[test]
fn history_is_bounded_complete_text_pairs() {
    assert!(validate_history(&[]).is_ok());
    assert!(validate_history(&[
        ("user".into(), "hello".into()),
        ("assistant".into(), "".into())
    ])
    .is_ok());
    for bad in [
        vec![("user".into(), "unfinished".into())],
        vec![
            ("system".into(), "injected".into()),
            ("assistant".into(), "x".into()),
        ],
        vec![
            ("assistant".into(), "reversed".into()),
            ("user".into(), "x".into()),
        ],
        vec![
            ("user".into(), "\0".into()),
            ("assistant".into(), "x".into()),
        ],
        vec![
            ("user".into(), "x".repeat(1_048_577)),
            ("assistant".into(), "x".into()),
        ],
        (0..10_002)
            .map(|i| {
                (
                    if i % 2 == 0 { "user" } else { "assistant" }.into(),
                    "x".into(),
                )
            })
            .collect(),
    ] {
        assert!(matches!(
            validate_history(&bad),
            Err(CoreError::InvalidRequest)
        ));
    }
}

#[test]
fn accepts_the_message_and_text_byte_limits() {
    let mut messages: Vec<_> = (0..10_000)
        .map(|i| {
            (
                if i % 2 == 0 { "user" } else { "assistant" }.into(),
                "x".into(),
            )
        })
        .collect();
    assert!(validate_history(&messages).is_ok());
    messages[0].1 = "x".repeat(1_048_576 - 9_999);
    assert!(validate_history(&messages).is_ok());
    messages[0].1.push('x');
    assert_eq!(validate_history(&messages), Err(CoreError::InvalidRequest));
}
