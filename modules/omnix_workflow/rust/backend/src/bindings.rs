use crate::{Progress, Step, StepState};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// A top-level input argument sourced from an earlier successful receipt.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OutputBinding {
    pub step: String,
    /// RFC 6901 pointer; empty selects the whole output, including JSON null.
    pub pointer: String,
}

pub(crate) fn validate(step: &Step, earlier: &[Step]) -> Result<(), String> {
    if step.output_bindings.is_empty() {
        return Ok(());
    }
    let input = step
        .input
        .as_object()
        .ok_or("Bound inputs must be an object")?;
    if step.output_bindings.len() > 16 {
        return Err("Too many output bindings".into());
    }
    for (argument, binding) in &step.output_bindings {
        if argument.is_empty()
            || argument.len() > 80
            || argument.contains('\0')
            || input.contains_key(argument)
            || !earlier.iter().any(|s| s.id == binding.step)
            || binding.pointer.len() > 256
            || binding.pointer.contains('\0')
            || (!binding.pointer.is_empty() && !binding.pointer.starts_with('/'))
        {
            return Err("Invalid, conflicting or forward output binding".into());
        }
        let mut chars = binding.pointer.chars();
        while let Some(c) = chars.next() {
            if c == '~' && !matches!(chars.next(), Some('0' | '1')) {
                return Err("Invalid output JSON pointer escape".into());
            }
        }
    }
    Ok(())
}

pub(crate) fn resolve(progress: &Progress, index: usize) -> Result<Step, String> {
    let mut invocation = progress.steps[index].clone();
    if invocation.output_bindings.is_empty() {
        return Ok(invocation);
    }
    let mut values = BTreeMap::new();
    for (argument, binding) in &invocation.output_bindings {
        let source = progress.steps[..index]
            .iter()
            .find(|s| s.id == binding.step)
            .filter(|s| s.state == StepState::Succeeded)
            .and_then(|s| s.output.as_ref())
            .ok_or("Successful source receipt unavailable")?;
        let value = source
            .pointer(&binding.pointer)
            .ok_or("Required output field unavailable")?;
        values.insert(argument.clone(), value.clone());
    }
    if !values.is_empty() {
        let input = invocation
            .input
            .as_object_mut()
            .ok_or("Bound inputs must be an object")?;
        input.extend(values);
    }
    if serde_json::to_vec(&invocation.input)
        .map_err(|_| "Input encoding failed")?
        .len()
        > 65536
    {
        return Err("Resolved input exceeds execution limit".into());
    }
    Ok(invocation)
}
