#[derive(Clone)]
pub enum InteractionInputKind {
    Text,
    Image,
    Audio,
}
#[derive(Clone)]
pub struct InteractionInputPart {
    pub kind: InteractionInputKind,
    pub text: Option<String>,
    pub bytes: Vec<u8>,
}
#[cfg(feature = "core")]
pub(crate) fn message(
    parts: Vec<InteractionInputPart>,
) -> Result<crate::core::CoreMessage, String> {
    use crate::core::{CoreMessage, InputModality, MessagePart};
    let parts = parts
        .into_iter()
        .map(|p| match p.kind {
            InteractionInputKind::Text if p.bytes.is_empty() => {
                p.text.map(MessagePart::Text).ok_or("Missing text")
            }
            InteractionInputKind::Image if p.text.is_none() => Ok(MessagePart::Image(p.bytes)),
            InteractionInputKind::Audio if p.text.is_none() => Ok(MessagePart::Audio(p.bytes)),
            _ => Err("Invalid input part"),
        })
        .collect::<Result<Vec<_>, _>>()?;
    let message = CoreMessage { parts };
    message
        .validate(
            &[
                InputModality::Text,
                InputModality::Image,
                InputModality::Audio,
            ]
            .into(),
        )
        .map_err(|e| e.to_string())?;
    Ok(message)
}
