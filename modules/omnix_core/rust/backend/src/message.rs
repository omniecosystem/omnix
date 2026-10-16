//! Ordered, owned input shared by native inference providers.

use crate::{CoreError, InputModality};
use std::collections::BTreeSet;

/// Encoded media is owned until native completion, including cancellation drain.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MessagePart {
    Text(String),
    Image(Vec<u8>),
    Audio(Vec<u8>),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CoreMessage {
    pub parts: Vec<MessagePart>,
}

impl CoreMessage {
    pub fn text(text: impl Into<String>) -> Self {
        Self {
            parts: vec![MessagePart::Text(text.into())],
        }
    }

    /// Conservative admission limits, not a promise of model media support.
    pub fn validate(&self, supported: &BTreeSet<InputModality>) -> Result<(), CoreError> {
        if self.parts.is_empty() || self.parts.len() > 16 {
            return Err(CoreError::InvalidRequest);
        }
        let mut text_bytes = 0usize;
        let mut media_bytes = 0usize;
        let mut images = 0;
        let mut audio = 0;
        let mut meaningful = false;
        for part in &self.parts {
            let modality = match part {
                MessagePart::Text(text) => {
                    text_bytes = text_bytes
                        .checked_add(text.len())
                        .ok_or(CoreError::InvalidRequest)?;
                    meaningful |= !text.trim().is_empty();
                    InputModality::Text
                }
                MessagePart::Image(bytes) => {
                    images += 1;
                    if bytes.is_empty() || bytes.len() > 8 * 1024 * 1024 {
                        return Err(CoreError::InvalidRequest);
                    }
                    validate_image(bytes)?;
                    media_bytes += bytes.len();
                    meaningful = true;
                    InputModality::Image
                }
                MessagePart::Audio(bytes) => {
                    audio += 1;
                    validate_wav(bytes)?;
                    media_bytes += bytes.len();
                    meaningful = true;
                    InputModality::Audio
                }
            };
            if !supported.contains(&modality) {
                return Err(CoreError::BackendFailure(
                    "input-modality-not-enabled".into(),
                ));
            }
        }
        if !meaningful
            || text_bytes > 1_048_576
            || media_bytes > 16 * 1024 * 1024
            || images > 4
            || audio > 1
        {
            return Err(CoreError::InvalidRequest);
        }
        Ok(())
    }

    pub fn text_only(&self) -> Result<String, CoreError> {
        self.validate(&[InputModality::Text].into())?;
        Ok(self
            .parts
            .iter()
            .filter_map(|p| match p {
                MessagePart::Text(text) => Some(text.as_str()),
                _ => None,
            })
            .collect())
    }
}

// Reject oversized dimensions before handing encoded bytes to the native decoder.
// This admission check is not complete image decoding or integrity validation.
pub(crate) fn validate_image(bytes: &[u8]) -> Result<(), CoreError> {
    let invalid = || CoreError::BackendFailure("image-requires-bounded-png-or-jpeg".into());
    let dimensions = if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        if bytes.len() < 33 || bytes[8..12] != 13u32.to_be_bytes() || &bytes[12..16] != b"IHDR" {
            return Err(invalid());
        }
        (
            u32::from_be_bytes(bytes[16..20].try_into().unwrap()),
            u32::from_be_bytes(bytes[20..24].try_into().unwrap()),
        )
    } else if bytes.starts_with(&[0xff, 0xd8]) {
        let mut offset = 2usize;
        let mut found = None;
        while offset < bytes.len() {
            if bytes[offset] != 0xff {
                return Err(invalid());
            }
            while offset < bytes.len() && bytes[offset] == 0xff {
                offset += 1;
            }
            let marker = *bytes.get(offset).ok_or_else(invalid)?;
            offset += 1;
            if marker == 0xda || marker == 0xd9 {
                break;
            }
            if marker == 0x01 || (0xd0..=0xd7).contains(&marker) {
                continue;
            }
            let length = bytes.get(offset..offset + 2).ok_or_else(invalid)?;
            let size = u16::from_be_bytes(length.try_into().unwrap()) as usize;
            if size < 2 {
                return Err(invalid());
            }
            let end = offset
                .checked_add(size)
                .filter(|end| *end <= bytes.len())
                .ok_or_else(invalid)?;
            if [0xc0, 0xc1, 0xc2].contains(&marker) {
                if size < 8 {
                    return Err(invalid());
                }
                let height =
                    u16::from_be_bytes(bytes[offset + 3..offset + 5].try_into().unwrap()) as u32;
                let width =
                    u16::from_be_bytes(bytes[offset + 5..offset + 7].try_into().unwrap()) as u32;
                found = Some((width, height));
                break;
            }
            offset = end;
        }
        found.ok_or_else(invalid)?
    } else {
        return Err(invalid());
    };
    let (width, height) = dimensions;
    if width == 0
        || height == 0
        || width > 4096
        || height > 4096
        || u64::from(width) * u64::from(height) > 16_000_000
    {
        return Err(invalid());
    }
    Ok(())
}

// First audio contract: PCM16 mono WAV at 16 kHz, at most one minute.
// Parse chunks instead of assuming a fixed 44-byte header.
pub(crate) fn validate_wav(bytes: &[u8]) -> Result<(), CoreError> {
    let invalid =
        || CoreError::BackendFailure("audio-requires-pcm16-mono-16khz-wav-max-60s".into());
    if bytes.len() < 44
        || bytes.len() > 2 * 1024 * 1024
        || &bytes[..4] != b"RIFF"
        || &bytes[8..12] != b"WAVE"
    {
        return Err(invalid());
    }
    let u32_at =
        |offset| u32::from_le_bytes(bytes[offset..offset + 4].try_into().unwrap()) as usize;
    if u32_at(4).checked_add(8) != Some(bytes.len()) {
        return Err(invalid());
    }
    let mut offset = 12usize;
    let mut format = false;
    let mut samples = None;
    while offset < bytes.len() {
        if bytes.len() - offset < 8 {
            return Err(invalid());
        }
        let size = u32_at(offset + 4);
        let start = offset + 8;
        let end = start
            .checked_add(size)
            .filter(|end| *end <= bytes.len())
            .ok_or_else(invalid)?;
        match &bytes[offset..offset + 4] {
            b"fmt " => {
                if format || size < 16 {
                    return Err(invalid());
                }
                let fmt = &bytes[start..end];
                if fmt[..4] != [1, 0, 1, 0]
                    || fmt[4..8] != 16000u32.to_le_bytes()
                    || fmt[8..12] != 32000u32.to_le_bytes()
                    || fmt[12..16] != [2, 0, 16, 0]
                {
                    return Err(invalid());
                }
                format = true;
            }
            b"data" => {
                if samples.is_some() || size == 0 || size % 2 != 0 || size > 16000 * 2 * 60 {
                    return Err(invalid());
                }
                samples = Some(size);
            }
            _ => {}
        }
        offset = end
            .checked_add(size % 2)
            .filter(|end| *end <= bytes.len())
            .ok_or_else(invalid)?;
    }
    if !format || samples.is_none() {
        return Err(invalid());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn wav() -> Vec<u8> {
        let mut bytes = b"RIFF".to_vec();
        bytes.extend(38u32.to_le_bytes());
        bytes.extend(b"WAVEfmt ");
        bytes.extend(16u32.to_le_bytes());
        bytes.extend([1, 0, 1, 0]);
        bytes.extend(16000u32.to_le_bytes());
        bytes.extend(32000u32.to_le_bytes());
        bytes.extend([2, 0, 16, 0]);
        bytes.extend(b"data");
        bytes.extend(2u32.to_le_bytes());
        bytes.extend([0, 0]);
        bytes
    }
    #[test]
    fn preserves_text_boundaries_and_rejects_media_on_text_provider() {
        let message = CoreMessage {
            parts: vec![
                MessagePart::Text("hello ".into()),
                MessagePart::Text("world".into()),
            ],
        };
        assert_eq!(message.text_only().unwrap(), "hello world");
        assert!(CoreMessage {
            parts: vec![MessagePart::Image(vec![1])]
        }
        .text_only()
        .is_err());
    }
    #[test]
    fn rejects_empty_oversize_and_excess_parts() {
        let supported = [InputModality::Text, InputModality::Image].into();
        for parts in [
            vec![],
            vec![MessagePart::Text(" ".into())],
            vec![MessagePart::Image(vec![])],
            vec![MessagePart::Image(vec![1]); 5],
            vec![MessagePart::Text("x".repeat(1_048_577))],
        ] {
            assert!(CoreMessage { parts }.validate(&supported).is_err());
        }
    }
    #[test]
    fn accepts_bounded_pcm_audio_and_rejects_truncated_or_wrong_sample_rate() {
        let supported = [InputModality::Audio].into();
        assert!(CoreMessage {
            parts: vec![MessagePart::Audio(wav())]
        }
        .validate(&supported)
        .is_ok());
        let mut wrong = wav();
        wrong[24..28].copy_from_slice(&44100u32.to_le_bytes());
        for bytes in [wav()[..40].to_vec(), wrong, vec![0; 44]] {
            assert!(CoreMessage {
                parts: vec![MessagePart::Audio(bytes)]
            }
            .validate(&supported)
            .is_err());
        }
    }

    #[test]
    fn image_admission_rejects_invalid_formats_and_decompression_dimensions() {
        let mut png = b"\x89PNG\r\n\x1a\n".to_vec();
        png.extend(13u32.to_be_bytes());
        png.extend(b"IHDR");
        png.extend(2u32.to_be_bytes());
        png.extend(2u32.to_be_bytes());
        png.extend([0; 9]);
        assert!(validate_image(&png).is_ok());
        png[16..20].copy_from_slice(&100000u32.to_be_bytes());
        assert!(validate_image(&png).is_err());
        assert!(validate_image(b"not an image").is_err());
        assert!(validate_image(&[0xff, 0xd8, 0xff, 0xc0, 0, 1]).is_err());
    }
}
