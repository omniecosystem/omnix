//! Shared bounded scalar-object contract for host tools and workflow preflight.
use serde_json::Value;
use std::collections::BTreeSet;

pub(crate) fn validate(
    schema: &Value,
    input: &Value,
    deferred: &BTreeSet<String>,
) -> Result<(), String> {
    let properties = schema["properties"]
        .as_object()
        .ok_or("Invalid host schema")?;
    let required = schema["required"].as_array().ok_or("Invalid host schema")?;
    if schema["type"] != "object"
        || schema["additionalProperties"] != false
        || properties.len() > 16
        || required
            .iter()
            .any(|v| v.as_str().is_none_or(|k| !properties.contains_key(k)))
        || properties.values().any(|v| {
            !matches!(
                v["type"].as_str(),
                Some("string" | "boolean" | "integer" | "number")
            )
        })
    {
        return Err("Unsupported host schema; expected a closed scalar object".into());
    }
    let input = input.as_object().ok_or("Tool input must be an object")?;
    if input.len() + deferred.len() > 16 {
        return Err("Tool input exceeds 16 fields".into());
    }
    if input
        .keys()
        .chain(deferred.iter())
        .any(|key| !properties.contains_key(key))
    {
        return Err(if properties.is_empty() {
            "This tool takes no arguments; input must be {}"
        } else {
            "Unexpected input or binding field; use only declared tool fields"
        }
        .into());
    }
    if deferred.iter().any(|key| input.contains_key(key)) {
        return Err("Literal input conflicts with a deferred binding".into());
    }
    for name in required.iter().filter_map(Value::as_str) {
        if !input.contains_key(name) && !deferred.contains(name) {
            return Err(format!("Missing required tool field: {name}"));
        }
    }
    for (name, value) in input {
        let valid = match properties[name]["type"].as_str() {
            Some("string") => value
                .as_str()
                .is_some_and(|s| s.len() <= 8192 && !s.contains('\0')),
            Some("boolean") => value.is_boolean(),
            Some("integer") => value.is_i64() || value.is_u64(),
            Some("number") => value.is_number(),
            _ => false,
        };
        if !valid {
            return Err(format!(
                "Tool field {name} does not match its declared type or size limits"
            ));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn no_argument_tools_reject_invented_fields_without_echoing_values() {
        let schema =
            json!({"type":"object","properties":{},"required":[],"additionalProperties":false});
        assert!(validate(&schema, &json!({}), &BTreeSet::new()).is_ok());
        let error = validate(&schema, &json!({"private":"secret"}), &BTreeSet::new()).unwrap_err();
        assert!(error.contains("no arguments"));
        assert!(!error.contains("private") && !error.contains("secret"));
    }
    #[test]
    fn bindings_defer_values_not_field_names_or_literal_validation() {
        let schema = json!({"type":"object","properties":{"text":{"type":"string"}},"required":["text"],"additionalProperties":false});
        assert!(validate(&schema, &json!({}), &BTreeSet::from(["text".into()])).is_ok());
        assert!(validate(&schema, &json!({}), &BTreeSet::from(["invented".into()])).is_err());
        assert!(validate(&schema, &json!({"text":10}), &BTreeSet::new()).is_err());
        assert!(validate(
            &schema,
            &json!({"text":"ok"}),
            &BTreeSet::from(["text".into()])
        )
        .is_err());
    }
}
