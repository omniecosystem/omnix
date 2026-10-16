//! Generic task admission: goals + host-accepted triggers and step plans.
//! No messaging semantics, provider, effect policy or default retry safety.
use crate::{
    storage::WorkflowStore,
    workflow::{Progress, RetrySafety, Step},
};
use serde_json::{json, Value};
use std::path::Path;
const KEY: &str = "event-tasks-v2";
fn text<'a>(v: &'a Value, key: &str, max: usize) -> Result<&'a str, String> {
    v[key]
        .as_str()
        .filter(|s| !s.trim().is_empty() && s.len() <= max && !s.contains('\0'))
        .ok_or_else(|| format!("Invalid {key}"))
}
fn identifier(v: &Value, key: &str) -> Result<String, String> {
    let id = text(v, key, 40)?;
    if !id
        .bytes()
        .all(|c| c.is_ascii_alphanumeric() || c == b'-' || c == b'_')
    {
        return Err(format!("Invalid {key}"));
    }
    Ok(id.into())
}
fn metadata(value: &Value) -> Result<(), String> {
    let fields = value.as_object().ok_or("Metadata must be an object")?;
    if fields.len() > 16
        || fields.iter().any(|(k, v)| {
            k.is_empty()
                || k.len() > 80
                || v.is_array()
                || v.is_object()
                || v.as_str().is_some_and(|s| s.len() > 1024)
        })
    {
        return Err("Metadata exceeds the scalar matching contract".into());
    }
    Ok(())
}
fn plan(task: &Value, event: Option<&Value>) -> Result<Vec<Step>, String> {
    let definitions = task["plan"].as_array().ok_or("Plan must be an array")?;
    if definitions.is_empty() || definitions.len() > 32 {
        return Err("Plan requires 1 to 32 steps".into());
    }
    let mut steps = Vec::new();
    let mut ids = std::collections::BTreeSet::new();
    for (index, definition) in definitions.iter().enumerate() {
        let id = identifier(definition, "id")
            .map_err(|_| format!("plan[{index}].id must contain 1 to 40 ASCII letters, digits, underscores or hyphens."))?;
        if !ids.insert(id.clone()) {
            return Err(format!(
                "plan[{index}].id duplicates an earlier step; use distinct step IDs."
            ));
        }
        let executor = text(definition, "executor", 128)
            .map_err(|_| format!("plan[{index}].executor must be a nonempty tool name."))?;
        let retry: RetrySafety =
            serde_json::from_value(definition["retry"].clone()).map_err(|_| {
                format!("plan[{index}].retry must be SafeToRepeat or RequiresReconciliation.")
            })?;
        let mut input = definition["input"]
            .as_object()
            .ok_or_else(|| {
                format!(
                    "plan[{index}].input must be an object; use {{}} for a tool without arguments."
                )
            })?
            .clone();
        if let Some(bindings) = definition.get("bindings") {
            let bindings = bindings.as_object().ok_or("Bindings must be an object")?;
            if bindings.len() > 16 {
                return Err("Too many bindings".into());
            }
            for (argument, binding) in bindings {
                let pointer = binding
                    .as_str()
                    .ok_or("Binding must be an event JSON pointer")?;
                if argument.is_empty()
                    || argument.len() > 80
                    || input.contains_key(argument)
                    || pointer.len() > 256
                    || !(pointer == "/payload"
                        || pointer.starts_with("/payload/")
                        || pointer.starts_with("/metadata/"))
                {
                    return Err("Invalid or conflicting event binding".into());
                }
                if let Some(event) = event {
                    input.insert(
                        argument.clone(),
                        event
                            .pointer(pointer)
                            .ok_or("Event is missing a required binding")?
                            .clone(),
                    );
                }
            }
        }
        let mut step = Step::new(id, executor, Value::Object(input), retry);
        if let Some(bindings) = definition.get("outputBindings") {
            step.output_bindings = serde_json::from_value(bindings.clone()).map_err(|_| {
                format!(
                    "plan[{index}].outputBindings must map input arguments to step/pointer objects."
                )
            })?;
            if definition
                .get("bindings")
                .and_then(Value::as_object)
                .is_some_and(|event| {
                    event
                        .keys()
                        .any(|key| step.output_bindings.contains_key(key))
                })
            {
                return Err("Event and output bindings cannot target the same argument".into());
            }
        }
        steps.push(step);
    }
    Progress::new("validation", steps.clone()).validate()?;
    Ok(steps)
}
fn validate_task(task: &Value) -> Result<(), String> {
    if task.as_object().is_none_or(|o| {
        o.len() != 4
            || o.keys()
                .any(|k| !["id", "goal", "trigger", "plan"].contains(&k.as_str()))
    }) {
        return Err("Task definition must contain only id, goal, trigger and plan".into());
    }
    identifier(task, "id")?;
    text(task, "goal", 4096)?;
    text(&task["trigger"], "source", 80)
        .map_err(|_| "trigger.source must be a nonempty string.".to_string())?;
    text(&task["trigger"], "kind", 80)
        .map_err(|_| "trigger.kind must be a nonempty string.".to_string())?;
    metadata(&task["trigger"]["match"]).map_err(|_| "trigger.match must be an object with at most 16 bounded scalar filters; use {} for no filters.".to_string())?;
    plan(task, None)?;
    Ok(())
}
// Consumer metadata, never model prose, supplies execution recovery semantics.
// Explicit legacy host definitions remain supported when contracts are absent.
fn resolve_proposal(request: &mut Value) -> Result<(), String> {
    let Some(contracts) = request.get("contracts") else {
        validate_task(&request["task"])?;
        return validate_inputs(&request["task"], request.get("schemas"));
    };
    let contracts = contracts
        .as_object()
        .ok_or("Host retry contracts must be an object")?
        .clone();
    if contracts.len() > 64 {
        return Err("Too many host retry contracts".into());
    }
    let steps = request["task"]["plan"]
        .as_array_mut()
        .ok_or("Plan must be an array")?;
    for (index, step) in steps.iter_mut().enumerate() {
        let executor = text(step, "executor", 128)?;
        let retry = contracts
            .get(executor)
            .ok_or_else(|| format!("plan[{index}].executor has no host retry contract."))?;
        serde_json::from_value::<RetrySafety>(retry.clone())
            .map_err(|_| "Invalid host retry contract")?;
        if step.get("retry").is_some_and(|supplied| supplied != retry) {
            return Err(format!(
                "plan[{index}].retry conflicts with host metadata; omit retry."
            ));
        }
        step["retry"] = retry.clone();
    }
    validate_task(&request["task"])?;
    validate_inputs(&request["task"], request.get("schemas"))
}

// Optional for older headless callers. Current consumers supply their schemas
// separately from model-generated plans; values bound at run time are checked
// again by the registered executor after binding resolution.
fn validate_inputs(task: &Value, schemas: Option<&Value>) -> Result<(), String> {
    let Some(schemas) = schemas else {
        return Ok(());
    };
    let schemas = schemas
        .as_object()
        .ok_or("Host schemas must be an object")?;
    if schemas.len() > 64 {
        return Err("Too many host schemas".into());
    }
    for (index, step) in task["plan"]
        .as_array()
        .ok_or("Plan must be an array")?
        .iter()
        .enumerate()
    {
        let executor = text(step, "executor", 128)?;
        let schema = schemas
            .get(executor)
            .ok_or_else(|| format!("plan[{index}].executor has no host schema"))?;
        let mut deferred = std::collections::BTreeSet::new();
        for field in ["bindings", "outputBindings"] {
            if let Some(bindings) = step.get(field) {
                deferred.extend(
                    bindings
                        .as_object()
                        .ok_or("Bindings must be an object")?
                        .keys()
                        .cloned(),
                );
            }
        }
        crate::tool_arguments::validate(schema, &step["input"], &deferred).map_err(|reason| {
            format!("plan[{index}].input: {reason}. No tool action was executed.")
        })?;
    }
    Ok(())
}
// Admission commits before acknowledging; it does not execute or grant tools.
fn task_jobs(
    store: &WorkflowStore,
    catalogue: &Value,
    task_id: &str,
) -> Result<Vec<Value>, String> {
    let prefix = format!("event-{}-{task_id}-", task_id.len());
    let mut jobs = Vec::new();
    let mut output_budget = 8192usize;
    for event in catalogue["events"]
        .as_array()
        .ok_or("Invalid saved events")?
    {
        for job in event["jobs"].as_array().ok_or("Invalid saved jobs")? {
            if !text(job, "id", 128)?.starts_with(&prefix) {
                continue;
            }
            let original: Progress =
                serde_json::from_value(job.clone()).map_err(|_| "Invalid admitted job")?;
            original.validate()?;
            let raw = store.read(&original.id)?;
            let checkpointed = raw.is_some();
            let progress: Progress = match raw {
                Some(raw) => serde_json::from_str(&raw).map_err(|_| "Invalid job checkpoint")?,
                None => original.clone(),
            };
            progress.validate()?;
            if progress.id != original.id
                || progress.version != original.version
                || progress.steps.len() != original.steps.len()
                || progress.steps.iter().zip(&original.steps).any(|(a, b)| {
                    a.id != b.id
                        || a.executor != b.executor
                        || a.input != b.input
                        || a.output_bindings != b.output_bindings
                        || a.retry != b.retry
                })
            {
                return Err("Checkpoint conflicts with admitted definition".into());
            }
            let state = if progress.cancelled {
                "Cancelled"
            } else if progress
                .steps
                .iter()
                .all(|step| step.state == crate::workflow::StepState::Succeeded)
            {
                "Completed"
            } else if progress
                .steps
                .iter()
                .any(|step| step.state == crate::workflow::StepState::NeedsReconciliation)
            {
                "NeedsReconciliation"
            } else if progress
                .steps
                .iter()
                .any(|step| step.state == crate::workflow::StepState::Failed)
            {
                "Failed"
            } else if progress
                .steps
                .iter()
                .any(|step| step.state == crate::workflow::StepState::Running)
            {
                "RunningCheckpoint"
            } else {
                "Pending"
            };
            let steps: Vec<Value> = progress.steps.iter().map(|step| {
                let output = serde_json::to_value(&step.output).unwrap_or(Value::Null);
                let category = match step.state {
                    crate::workflow::StepState::Running | crate::workflow::StepState::NeedsReconciliation => Some("uncertain_execution"),
                    crate::workflow::StepState::Failed if output["code"] == "WORKFLOW_BINDING_UNAVAILABLE" => Some("binding_unavailable"),
                    crate::workflow::StepState::Failed => Some(match output["status"].as_str() {
                        Some("invalid_arguments") => "invalid_arguments",
                        Some("denied") => "denied",
                        Some("unavailable") => "unavailable",
                        _ => "failed",
                    }),
                    _ => None,
                };
                let size = output.to_string().len();
                let omitted = size > 1024 || size > output_budget;
                if !omitted { output_budget -= size; }
                json!({"id":step.id,"executor":step.executor,"state":step.state,
                    "output":if omitted {Value::Null} else {output},"hasOutput":step.output.is_some(),"outputOmitted":omitted,"failureCategory":category})
            }).collect();
            jobs.push(
                json!({"id":progress.id,"state":state,"checkpointed":checkpointed,"steps":steps}),
            );
        }
    }
    Ok(jobs)
}
/// Validates and persists a host-supplied task command in a private database.
/// Proposals remain inactive until accepted. Event admission never executes tools;
/// stopping a task disables future triggers without cancelling admitted jobs.
pub fn command(path: &Path, raw: &str) -> Result<String, String> {
    if raw.len() > 65536 {
        return Err("Task command too large".into());
    }
    let mut request: Value = serde_json::from_str(raw).map_err(|_| "Invalid task command")?;
    // Validate model proposals before touching storage. Only validation-generated
    // field/rule messages are exposed; never include submitted values or paths.
    if request["operation"] == "propose" {
        if let Err(reason) = resolve_proposal(&mut request) {
            return Ok(json!({
                "status":"invalid_arguments", "code":"TASK_PROPOSAL_INVALID",
                "reason":reason, "accepted":false, "executionStarted":false
            })
            .to_string());
        }
    }
    let mut store = WorkflowStore::open(path)?;
    let mut catalogue: Value = match store.read(KEY)? {
        Some(raw) => serde_json::from_str(&raw).map_err(|_| "Invalid task catalogue")?,
        None => {
            if store.read("event-subscriptions-v1")?.is_some() {
                return Err("Legacy prototype retained; choose a separate v2 database. No automatic migration.".into());
            }
            json!({"version":2,"tasks":[],"events":[],"proposals":[]})
        }
    };
    if (catalogue["version"] != 2 && catalogue["version"] != 3)
        || !catalogue["tasks"].is_array()
        || !catalogue["events"].is_array()
    {
        return Err("Unsupported task catalogue".into());
    }
    if catalogue.get("proposals").is_none() {
        catalogue["proposals"] = json!([]);
    }
    if !catalogue["proposals"].is_array() {
        return Err("Invalid proposal catalogue".into());
    }
    let response = match text(&request, "operation", 32)? {
        "inspect" => {
            let id = request["id"]
                .as_str()
                .ok_or("Inspection id must be a string")?;
            let offset = request
                .get("offset")
                .map(|v| {
                    v.as_u64()
                        .filter(|n| *n <= 128)
                        .ok_or("Invalid inspection offset")
                })
                .transpose()?
                .unwrap_or(0) as usize;
            let mut summaries = Vec::new();
            for (collection, phase) in [("proposals", "Proposed"), ("tasks", "Accepted")] {
                for task in catalogue[collection].as_array().unwrap() {
                    let task_id = identifier(task, "id")?;
                    if !id.is_empty() && task_id != id {
                        continue;
                    }
                    let mut jobs = task_jobs(&store, &catalogue, &task_id)?;
                    let total = jobs.len();
                    let completed = jobs
                        .iter()
                        .filter(|job| job["state"] == "Completed")
                        .count();
                    let mut states = serde_json::Map::new();
                    let mut failures = serde_json::Map::new();
                    for job in &jobs {
                        let state = job["state"].as_str().ok_or("Invalid job state")?;
                        let count = states.get(state).and_then(Value::as_u64).unwrap_or(0);
                        states.insert(state.into(), json!(count + 1));
                        for step in job["steps"].as_array().ok_or("Invalid inspection steps")? {
                            let category = step["failureCategory"].as_str();
                            if let Some(category) = category {
                                let count =
                                    failures.get(category).and_then(Value::as_u64).unwrap_or(0);
                                failures.insert(category.into(), json!(count + 1));
                            }
                        }
                    }
                    if id.is_empty() {
                        jobs.clear();
                    } else if jobs.len() > 4 {
                        jobs.drain(..jobs.len() - 4);
                    }
                    let goal = text(task, "goal", 4096)?;
                    let mut summary = json!({"id":task_id,"goal":goal.chars().take(512).collect::<String>(),"goalTruncated":goal.chars().count()>512,"phase":phase,
                        "futureTriggersEnabled":phase == "Accepted" && task["enabled"] == true,
                        "jobsTotal":total,"completedJobs":completed,"jobStateCounts":states,"failureCategories":failures,"jobs":jobs,
                        "jobsOmitted":total-jobs.len()});
                    if !id.is_empty() {
                        summary["trigger"] = task["trigger"].clone();
                        // Acceptance review needs the actual arguments and event
                        // bindings, not just executor names. Existing size guards
                        // below explicitly omit plans that cannot fit the channel.
                        summary["plan"] = task["plan"].clone();
                    }
                    summaries.push(summary);
                }
            }
            let total = summaries.len();
            let mut selected: Vec<_> = summaries.into_iter().skip(offset).take(8).collect();
            // Respect the agent's bounded tool-result channel even for heavily
            // escaped names or large trigger filters. Never silently invent a
            // summary of evidence that could not fit.
            for summary in &mut selected {
                while summary.to_string().len() > 30000
                    && !summary["jobs"].as_array().unwrap().is_empty()
                {
                    summary["jobs"].as_array_mut().unwrap().remove(0);
                    summary["jobsOmitted"] = json!(summary["jobsOmitted"].as_u64().unwrap() + 1);
                }
                if summary.to_string().len() > 30000 {
                    summary.as_object_mut().unwrap().remove("trigger");
                    summary["triggerOmitted"] = json!(true);
                }
                if summary.to_string().len() > 30000 {
                    summary.as_object_mut().unwrap().remove("plan");
                    summary["planOmitted"] = json!(true);
                }
            }
            let next = offset + selected.len();
            return Ok(json!({"status":if !id.is_empty() && total == 0 {"not_found"} else {"succeeded"},
                "tasks":selected,"tasksTotal":total,"nextOffset":if next<total {Some(next)} else {None},"readOnly":true,"executionStarted":false,
                "evidence":"Saved admission and durable checkpoints only; RunningCheckpoint does not confirm a live worker. Job completion does not mean a recurring task has ended."}).to_string());
        }
        "list" => {
            // The immutable admission receipt is not execution evidence.
            // Surface the separately committed Workflow checkpoints when present.
            for event in catalogue["events"].as_array_mut().unwrap() {
                for job in event["jobs"].as_array_mut().ok_or("Invalid saved jobs")? {
                    if let Some(raw) = store.read(text(job, "id", 128)?)? {
                        let saved: Progress =
                            serde_json::from_str(&raw).map_err(|_| "Invalid job checkpoint")?;
                        saved.validate()?;
                        *job = serde_json::to_value(saved).map_err(|_| "Job encoding failed")?;
                    }
                }
            }
            return Ok(catalogue.to_string());
        }
        "job" => {
            let id = text(&request, "id", 128)?;
            let job = catalogue["events"]
                .as_array()
                .unwrap()
                .iter()
                .flat_map(|event| event["jobs"].as_array().into_iter().flatten())
                .find(|job| job["id"] == id)
                .ok_or("Admitted job not found")?;
            // Returning the original definition lets Workflow check identity and
            // resume its own checkpoint, rather than replaying the admission copy.
            return Ok(job.to_string());
        }
        "propose" => {
            let task = request["task"].clone();
            validate_task(&task)?;
            if plan(&task, None)?
                .iter()
                .any(|step| !step.output_bindings.is_empty())
            {
                catalogue["version"] = json!(3);
            }
            if catalogue["tasks"]
                .as_array()
                .unwrap()
                .iter()
                .any(|t| t["id"] == task["id"])
            {
                return Err("Task identity already accepted".into());
            }
            let proposals = catalogue["proposals"].as_array_mut().unwrap();
            if let Some(existing) = proposals.iter().find(|t| t["id"] == task["id"]) {
                if existing != &task {
                    return Err("Proposal identity already has another definition".into());
                }
            } else {
                if proposals.len() >= 64 {
                    return Err("Proposal catalogue full".into());
                }
                proposals.push(task.clone());
            }
            json!({"status":"succeeded","proposal":task,"accepted":false,"executionStarted":false})
        }
        "accept" => {
            let id = identifier(&request, "id")?;
            let index = catalogue["proposals"]
                .as_array()
                .unwrap()
                .iter()
                .position(|t| t["id"] == id)
                .ok_or("Proposal not found")?;
            let mut task = catalogue["proposals"][index].clone();
            validate_task(&task)?;
            validate_inputs(&task, request.get("schemas"))?;
            // The host attests to available executor retry contracts. This is
            // independent of the model's proposal and grants at execution time.
            let contracts = request["contracts"]
                .as_object()
                .ok_or("Host retry contracts required")?;
            for step in plan(&task, None)? {
                let supplied: RetrySafety = serde_json::from_value(
                    contracts
                        .get(&step.executor)
                        .ok_or("Proposed executor unavailable")?
                        .clone(),
                )
                .map_err(|_| "Invalid host retry contract")?;
                if supplied != step.retry {
                    return Err("Proposal conflicts with host retry contract".into());
                }
            }
            let tasks = catalogue["tasks"].as_array_mut().unwrap();
            if tasks.len() >= 64 {
                return Err("Task catalogue full".into());
            }
            if tasks.iter().any(|t| t["id"] == id) {
                return Err("Task identity already accepted".into());
            }
            task["enabled"] = json!(true);
            tasks.push(task.clone());
            catalogue["proposals"].as_array_mut().unwrap().remove(index);
            json!({"status":"succeeded","task":task,"accepted":true,"executionStarted":false})
        }
        "create" => {
            let mut task = request["task"].clone();
            validate_task(&task)?;
            validate_inputs(&task, request.get("schemas"))?;
            if plan(&task, None)?
                .iter()
                .any(|step| !step.output_bindings.is_empty())
            {
                catalogue["version"] = json!(3);
            }
            task["enabled"] = json!(true);
            let tasks = catalogue["tasks"].as_array_mut().unwrap();
            if let Some(existing) = tasks.iter().find(|t| t["id"] == task["id"]) {
                if existing != &task {
                    return Err("Task identity already has another definition".into());
                }
            } else {
                if tasks.len() >= 64 {
                    return Err("Task catalogue full".into());
                }
                tasks.push(task.clone());
            }
            json!({"status":"succeeded","task":task,"executionStarted":false})
        }
        "stop" => {
            let id = identifier(&request, "id")?;
            let task = catalogue["tasks"]
                .as_array_mut()
                .unwrap()
                .iter_mut()
                .find(|t| t["id"] == id);
            let Some(task) = task else {
                return Ok(json!({"status":"not_found","futureTriggersStopped":false,"existingJobsCancelled":false}).to_string());
            };
            task["enabled"] = json!(false);
            json!({"status":"succeeded","task":task,"futureTriggersStopped":true,"existingJobsCancelled":false})
        }
        "event" | "start" => {
            let id = identifier(&request, "id")?;
            let selected = if request["operation"] == "start" {
                Some(identifier(&request, "taskId")?)
            } else {
                None
            };
            let event = if let Some(task_id) = &selected {
                json!({"id":id,"source":"host-request","kind":"manual-run","metadata":{"taskId":task_id},"payload":{}})
            } else {
                json!({"id":id,"source":text(&request,"source",80)?,"kind":text(&request,"kind",80)?,"metadata":request["metadata"],"payload":request["payload"]})
            };
            metadata(&event["metadata"])?;
            if selected.is_none() && request.get("payload").is_none() {
                return Err("Event payload is required".into());
            }
            if let Some(existing) = catalogue["events"]
                .as_array()
                .unwrap()
                .iter()
                .find(|e| e["event"]["id"] == id && e["event"]["source"] == event["source"])
            {
                if existing["event"] != event {
                    return Err("Event identity reused with different content".into());
                }
                return Ok(
                    json!({"status":"succeeded","duplicate":true,"jobs":existing["jobs"]})
                        .to_string(),
                );
            }
            let mut jobs = Vec::new();
            for task in catalogue["tasks"].as_array().unwrap() {
                let mut definition = task.clone();
                definition
                    .as_object_mut()
                    .ok_or("Invalid saved task")?
                    .remove("enabled");
                validate_task(&definition)?;
                let trigger = &task["trigger"];
                if task["enabled"] != true {
                    continue;
                }
                if let Some(task_id) = &selected {
                    if task["id"] != *task_id {
                        continue;
                    }
                } else if trigger["source"] != event["source"]
                    || trigger["kind"] != event["kind"]
                    || trigger["match"]
                        .as_object()
                        .unwrap()
                        .iter()
                        .any(|(key, value)| event["metadata"].get(key) != Some(value))
                {
                    continue;
                }
                let steps = plan(task, Some(&event))?;
                let job = Progress {
                    version: if steps.iter().any(|step| !step.output_bindings.is_empty()) {
                        2
                    } else {
                        1
                    },
                    // Length-prefix prevents ambiguous task/event concatenations.
                    id: format!(
                        "event-{}-{}-{id}",
                        identifier(task, "id")?.len(),
                        identifier(task, "id")?
                    ),
                    cancelled: false,
                    steps,
                };
                job.validate()?;
                // Event deduplication includes the source, but persisted job IDs
                // predate that scope. Reject aliases without rewriting checkpoints.
                for admitted in catalogue["events"].as_array().unwrap() {
                    if admitted["jobs"]
                        .as_array()
                        .ok_or("Invalid saved jobs")?
                        .iter()
                        .any(|saved| saved["id"] == job.id)
                    {
                        return Err("Job identity already belongs to another event; use a distinct event id".into());
                    }
                }
                jobs.push(serde_json::to_value(job).map_err(|_| "Job encoding failed")?);
            }
            if jobs.is_empty() {
                if selected.is_some() {
                    return Err("Accepted enabled task not found; no run was queued".into());
                }
                return Ok(json!({"status":"ignored","jobs":[]}).to_string());
            }
            let events = catalogue["events"].as_array_mut().unwrap();
            if events.len() >= 128 {
                return Err("Event inbox full; no event accepted".into());
            }
            events.push(json!({"event":event,"jobs":jobs}));
            json!({"status":"succeeded","duplicate":false,"jobs":jobs})
        }
        _ => return Err("Unknown task operation".into()),
    };
    store.write(KEY, &catalogue.to_string())?;
    Ok(response.to_string())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn manual_and_source_events_cannot_alias_the_same_durable_job() {
        for manual_first in [false, true] {
            let dir = tempfile::tempdir().unwrap();
            let path = dir.path().join("tasks.sqlite");
            let mut definition = task();
            definition["plan"] = json!([
                {"id":"read","executor":"host_read","input":{},"retry":"SafeToRepeat"}
            ]);
            call(&path, json!({"operation":"create","task":definition})).unwrap();
            let manual = json!({"operation":"start","id":"event1","taskId":"task1"});
            let source = event();
            let (first, second) = if manual_first {
                (manual, source)
            } else {
                (source, manual)
            };
            let admitted = call(&path, first.clone()).unwrap();
            let before = call(&path, json!({"operation":"list"})).unwrap();
            assert_eq!(
                call(&path, second.clone()).unwrap_err(),
                "Job identity already belongs to another event; use a distinct event id"
            );
            assert_eq!(call(&path, json!({"operation":"list"})).unwrap(), before);
            let duplicate = call(&path, first).unwrap();
            assert_eq!(duplicate["duplicate"], true);
            assert_eq!(duplicate["jobs"], admitted["jobs"]);
            let mut distinct = second;
            distinct["id"] = json!("event2");
            assert_eq!(call(&path, distinct).unwrap()["duplicate"], false);
            assert_eq!(
                call(&path, json!({"operation":"list"})).unwrap()["events"]
                    .as_array()
                    .unwrap()
                    .len(),
                2
            );
        }
    }
    #[test]
    fn malformed_executor_inputs_are_rejected_before_proposal_persistence() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        let schema =
            json!({"type":"object","properties":{},"required":[],"additionalProperties":false});
        let request = json!({"operation":"propose","contracts":{"host_read":"SafeToRepeat"},"schemas":{"host_read":schema},"task":{
            "id":"bad","goal":"Read host value","trigger":{"source":"host","kind":"manual","match":{}},
            "plan":[{"id":"one","executor":"host_read","input":{"invented":"private-value"}}]
        }});
        let receipt = call(&path, request).unwrap();
        assert_eq!(receipt["status"], "invalid_arguments");
        assert!(receipt["reason"].as_str().unwrap().contains("no arguments"));
        assert!(!receipt.to_string().contains("private-value"));
        assert!(
            call(&path, json!({"operation":"list"})).unwrap()["proposals"]
                .as_array()
                .unwrap()
                .is_empty()
        );
    }
    #[test]
    fn schema_preflight_allows_declared_bindings_and_rechecks_at_acceptance() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        let empty =
            json!({"type":"object","properties":{},"required":[],"additionalProperties":false});
        let text = json!({"type":"object","properties":{"text":{"type":"string"}},"required":["text"],"additionalProperties":false});
        let schemas = json!({"host_read":empty,"host_format":text});
        let contracts = json!({"host_read":"SafeToRepeat","host_format":"SafeToRepeat"});
        let proposed = call(&path, json!({"operation":"propose","contracts":contracts,"schemas":schemas,"task":{
            "id":"good","goal":"Read then format","trigger":{"source":"host","kind":"manual","match":{}},
            "plan":[{"id":"one","executor":"host_read","input":{}},{"id":"two","executor":"host_format","input":{},"outputBindings":{"text":{"step":"one","pointer":"/text"}}}]
        }})).unwrap();
        assert_eq!(proposed["status"], "succeeded");
        let changed = json!({"host_read":empty,"host_format":empty});
        assert!(call(
            &path,
            json!({"operation":"accept","id":"good","contracts":contracts,"schemas":changed})
        )
        .is_err());
        assert_eq!(
            call(&path, json!({"operation":"list"})).unwrap()["proposals"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        assert_eq!(
            call(
                &path,
                json!({"operation":"accept","id":"good","contracts":contracts,"schemas":schemas})
            )
            .unwrap()["status"],
            "succeeded"
        );
    }
    #[test]
    fn manual_start_targets_one_enabled_task_and_deduplicates_without_execution() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        for id in ["task1", "other"] {
            let mut t = task();
            t["id"] = json!(id);
            t["plan"] =
                json!([{"id":"one","executor":"host_time","input":{},"retry":"SafeToRepeat"}]);
            call(&path, json!({"operation":"create","task":t})).unwrap();
        }
        let request = json!({"operation":"start","id":"run1","taskId":"task1"});
        let admitted = call(&path, request.clone()).unwrap();
        let inspected = call(&path, json!({"operation":"inspect","id":"task1"})).unwrap();
        assert_eq!(inspected["tasks"][0]["plan"][0]["input"], json!({}));
        assert_eq!(admitted["jobs"].as_array().unwrap().len(), 1);
        assert_eq!(admitted["jobs"][0]["steps"][0]["state"], "Pending");
        assert_eq!(call(&path, request).unwrap()["duplicate"], true);
        assert!(call(
            &path,
            json!({"operation":"start","id":"run1","taskId":"other"})
        )
        .is_err());
        call(&path, json!({"operation":"stop","id":"task1"})).unwrap();
        assert!(call(
            &path,
            json!({"operation":"start","id":"run2","taskId":"task1"})
        )
        .is_err());
        assert!(call(
            &path,
            json!({"operation":"start","id":"run3","taskId":"missing"})
        )
        .is_err());
        assert_eq!(
            call(&path, json!({"operation":"list"})).unwrap()["events"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
    }
    #[test]
    fn admission_keeps_output_bindings_and_rejects_conflicting_event_targets() {
        let mut t = task();
        t["plan"][1]["outputBindings"] = json!({"sample":{"step":"inspect","pointer":"/sample"}});
        assert!(validate_task(&t).is_ok());
        t["plan"][1]["bindings"] = json!({"sample":"/payload/value"});
        assert!(validate_task(&t).is_err());
        t["plan"][1].as_object_mut().unwrap().remove("bindings");
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        call(&path, json!({"operation":"create","task":t})).unwrap();
        let admitted = call(&path, event()).unwrap();
        assert_eq!(
            admitted["jobs"][0]["steps"][1]["outputBindings"]["sample"]["step"],
            "inspect"
        );
        assert_eq!(admitted["jobs"][0]["version"], 2);
        assert_eq!(
            call(&path, json!({"operation":"list"})).unwrap()["version"],
            3
        );
    }
    #[test]
    fn failure_categories_survive_receipt_truncation() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        call(&path, json!({"operation":"create","task":task()})).unwrap();
        let admitted = call(&path, event()).unwrap();
        for status in ["invalid_arguments", "denied", "unavailable", "failed"] {
            let mut progress: Progress =
                serde_json::from_value(admitted["jobs"][0].clone()).unwrap();
            progress.steps[0].state = crate::workflow::StepState::Failed;
            progress.steps[0].output = Some(json!({"status":status,"detail":"x".repeat(2000)}));
            {
                let mut store = WorkflowStore::open(&path).unwrap();
                store
                    .write(&progress.id, &serde_json::to_string(&progress).unwrap())
                    .unwrap();
            }
            let inspected = call(&path, json!({"operation":"inspect","id":"task1"})).unwrap();
            assert_eq!(inspected["tasks"][0]["failureCategories"][status], 1);
            assert_eq!(
                inspected["tasks"][0]["jobs"][0]["steps"][0]["outputOmitted"],
                true
            );
        }
    }
    #[test]
    fn heavily_escaped_job_details_fit_tool_channel_and_mark_omissions() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        let mut t = task();
        t["plan"] = json!((0..32).map(|i| json!({"id":format!("step{i}"),"executor":"\\".repeat(128),"retry":"SafeToRepeat","input":{}})).collect::<Vec<_>>());
        call(&path, json!({"operation":"create","task":t})).unwrap();
        for i in 0..4 {
            let mut e = event();
            e["id"] = json!(format!("event{i}"));
            call(&path, e).unwrap();
        }
        let detail = call(&path, json!({"operation":"inspect","id":"task1"})).unwrap();
        assert!(detail.to_string().len() <= 32768);
        assert!(detail["tasks"][0]["jobsOmitted"].as_u64().unwrap() > 0);
        assert_eq!(detail["tasks"][0]["jobStateCounts"]["Pending"], 4);
    }
    #[test]
    fn inspection_reports_saved_evidence_and_stop_does_not_cancel_jobs() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        call(&path, json!({"operation":"propose","task":task()})).unwrap();
        let proposed = call(&path, json!({"operation":"inspect","id":"task1"})).unwrap();
        assert_eq!(proposed["tasks"][0]["phase"], "Proposed");
        assert_eq!(proposed["tasks"][0]["jobsTotal"], 0);
        assert_eq!(proposed["tasks"][0]["futureTriggersEnabled"], false);
        call(&path, json!({"operation":"accept","id":"task1","contracts":{"host_inspect":"SafeToRepeat","host_action":"RequiresReconciliation"}})).unwrap();
        let admitted = call(&path, event()).unwrap();
        let mut progress: Progress = serde_json::from_value(admitted["jobs"][0].clone()).unwrap();
        let initial = call(&path, json!({"operation":"inspect","id":"task1"})).unwrap();
        assert_eq!(initial["tasks"][0]["jobs"][0]["state"], "Pending");
        assert_eq!(initial["tasks"][0]["jobs"][0]["checkpointed"], false);
        progress.steps[0].state = crate::workflow::StepState::Succeeded;
        progress.steps[0].output = Some(json!({"status":"succeeded","sample":42}));
        progress.steps[1].state = crate::workflow::StepState::Failed;
        progress.steps[1].output = Some(json!({"status":"failed","reason":"Host declined"}));
        {
            let mut store = WorkflowStore::open(&path).unwrap();
            store
                .write(&progress.id, &serde_json::to_string(&progress).unwrap())
                .unwrap();
        }
        let detail = call(&path, json!({"operation":"inspect","id":"task1"})).unwrap();
        assert_eq!(detail["tasks"][0]["jobs"][0]["state"], "Failed");
        assert_eq!(detail["tasks"][0]["failureCategories"]["failed"], 1);
        assert_eq!(detail["tasks"][0]["jobs"][0]["checkpointed"], true);
        assert_eq!(
            detail["tasks"][0]["jobs"][0]["steps"][1]["output"]["reason"],
            "Host declined"
        );
        let stopped = call(&path, json!({"operation":"stop","id":"task1"})).unwrap();
        assert_eq!(stopped["futureTriggersStopped"], true);
        assert_eq!(stopped["existingJobsCancelled"], false);
        let after = call(&path, json!({"operation":"inspect","id":"task1"})).unwrap();
        assert_eq!(after["tasks"][0]["jobs"], detail["tasks"][0]["jobs"]);
        assert_eq!(after["tasks"][0]["futureTriggersEnabled"], false);
        assert_eq!(
            call(&path, json!({"operation":"stop","id":"task1"})).unwrap()["status"],
            "succeeded"
        );
        let mut next = event();
        next["id"] = json!("event2");
        assert_eq!(call(&path, next).unwrap()["status"], "ignored");
        assert_eq!(
            call(&path, json!({"operation":"inspect","id":"unknown"})).unwrap()["status"],
            "not_found"
        );
        assert_eq!(
            call(&path, json!({"operation":"stop","id":"unknown"})).unwrap()["status"],
            "not_found"
        );
    }
    #[test]
    fn inspection_pages_tasks_and_bounds_receipts_without_fabricating_success() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        for n in 0..10 {
            let mut t = task();
            t["id"] = json!(format!("task{n}"));
            call(&path, json!({"operation":"create","task":t})).unwrap();
        }
        let page = call(&path, json!({"operation":"inspect","id":""})).unwrap();
        assert_eq!(page["tasks"].as_array().unwrap().len(), 8);
        assert_eq!(page["nextOffset"], 8);
        assert_eq!(
            call(&path, json!({"operation":"inspect","id":"","offset":8})).unwrap()["tasks"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        let admitted = call(&path, event()).unwrap();
        let mut progress: Progress = serde_json::from_value(admitted["jobs"][0].clone()).unwrap();
        progress.steps[0].state = crate::workflow::StepState::Succeeded;
        progress.steps[0].output = Some(json!("x".repeat(2000)));
        progress.steps[1].state = crate::workflow::StepState::Running;
        {
            let mut store = WorkflowStore::open(&path).unwrap();
            store
                .write(&progress.id, &serde_json::to_string(&progress).unwrap())
                .unwrap();
        }
        let detail = call(&path, json!({"operation":"inspect","id":"task0"})).unwrap();
        assert_eq!(detail["tasks"][0]["jobs"][0]["state"], "RunningCheckpoint");
        assert_eq!(
            detail["tasks"][0]["jobs"][0]["steps"][0]["outputOmitted"],
            true
        );
        assert_eq!(detail["tasks"][0]["jobs"][0]["steps"][0]["hasOutput"], true);
        assert_eq!(detail["tasks"][0]["completedJobs"], 0);
    }
    #[test]
    fn host_resolves_model_steps_and_rechecks_contract_at_acceptance() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        let mut proposed = task();
        for step in proposed["plan"].as_array_mut().unwrap() {
            step.as_object_mut().unwrap().remove("retry");
        }
        let contracts =
            json!({"host_inspect":"SafeToRepeat","host_action":"RequiresReconciliation"});
        let receipt = call(
            &path,
            json!({"operation":"propose","task":proposed,"contracts":contracts}),
        )
        .unwrap();
        assert_eq!(receipt["proposal"]["plan"][0]["retry"], "SafeToRepeat");
        assert_eq!(
            receipt["proposal"]["plan"][1]["retry"],
            "RequiresReconciliation"
        );
        assert_eq!(receipt["accepted"], false);
        assert!(call(&path, json!({"operation":"accept","id":"task1","contracts":{"host_inspect":"SafeToRepeat","host_action":"SafeToRepeat"}})).is_err());
        call(
            &path,
            json!({"operation":"accept","id":"task1","contracts":contracts}),
        )
        .unwrap();
        let admitted = call(&path, event()).unwrap();
        assert_eq!(
            admitted["jobs"][0]["steps"][1]["retry"],
            "RequiresReconciliation"
        );
    }
    #[test]
    fn missing_contract_and_model_override_fail_before_storage() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("missing").join("tasks.sqlite");
        let result = call(
            &path,
            json!({"operation":"propose","task":task(),"contracts":{}}),
        )
        .unwrap();
        assert_eq!(result["status"], "invalid_arguments");
        assert!(!path.parent().unwrap().exists());
        let result = call(&path, json!({"operation":"propose","task":task(),"contracts":{"host_inspect":"RequiresReconciliation"}})).unwrap();
        assert!(result["reason"]
            .as_str()
            .unwrap()
            .contains("conflicts with host metadata"));
        assert!(!path.parent().unwrap().exists());
    }
    fn call(path: &Path, request: Value) -> Result<Value, String> {
        command(path, &request.to_string()).map(|s| serde_json::from_str(&s).unwrap())
    }
    fn task() -> Value {
        json!({"id":"task1","goal":"Respond to a supplied event","trigger":{"source":"host","kind":"signal","match":{"resource":"A"}},"plan":[
            {"id":"inspect","executor":"host_inspect","retry":"SafeToRepeat","input":{},"bindings":{"sample":"/payload/value"}},
            {"id":"act","executor":"host_action","retry":"RequiresReconciliation","input":{"level":3}}
        ]})
    }
    fn event() -> Value {
        json!({"operation":"event","id":"event1","source":"host","kind":"signal","metadata":{"resource":"A"},"payload":{"value":42}})
    }
    #[test]
    fn generic_plans_survive_reopen_and_preserve_retry_contracts() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        call(&path, json!({"operation":"create","task":task()})).unwrap();
        let mut unrelated = event();
        unrelated["metadata"]["resource"] = json!("B");
        assert_eq!(call(&path, unrelated).unwrap()["status"], "ignored");
        let admitted = call(&path, event()).unwrap();
        assert_eq!(admitted["jobs"][0]["steps"][0]["input"]["sample"], 42);
        assert_eq!(
            admitted["jobs"][0]["steps"][1]["retry"],
            "RequiresReconciliation"
        );
        assert_eq!(call(&path, event()).unwrap()["duplicate"], true);
        let mut conflicting = event();
        conflicting["payload"] = json!("changed");
        assert!(call(&path, conflicting).is_err());
    }
    #[test]
    fn missing_bindings_are_not_admitted_and_stop_prevents_new_work() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        call(&path, json!({"operation":"create","task":task()})).unwrap();
        let mut missing = event();
        missing["payload"] = json!({});
        assert!(call(&path, missing).is_err());
        assert!(call(&path, json!({"operation":"list"})).unwrap()["events"]
            .as_array()
            .unwrap()
            .is_empty());
        call(&path, json!({"operation":"stop","id":"task1"})).unwrap();
        assert_eq!(call(&path, event()).unwrap()["status"], "ignored");
    }
    #[test]
    fn invalid_plan_and_implicit_retry_are_rejected() {
        let mut value = task();
        value["plan"][0].as_object_mut().unwrap().remove("retry");
        assert!(validate_task(&value).is_err());
        value = task();
        value["plan"][1]["id"] = json!("inspect");
        assert!(validate_task(&value).is_err());
        value = task();
        value["plan"][0]["bindings"] = json!({"sample":"/permissions"});
        assert!(validate_task(&value).is_err());
    }

    #[test]
    fn proposal_feedback_is_safe_specific_and_precedes_storage() {
        let dir = tempfile::tempdir().unwrap();
        let missing = dir.path().join("not-created").join("tasks.sqlite");
        let mut invalid = task();
        invalid["plan"][0].as_object_mut().unwrap().remove("retry");
        let response = call(&missing, json!({"operation":"propose","task":invalid})).unwrap();
        assert_eq!(response["status"], "invalid_arguments");
        assert_eq!(response["code"], "TASK_PROPOSAL_INVALID");
        assert!(response["reason"]
            .as_str()
            .unwrap()
            .contains("plan[0].retry"));
        assert!(!missing.parent().unwrap().exists());
        invalid = task();
        invalid["plan"][1]["id"] = json!("inspect");
        let response = call(&missing, json!({"operation":"propose","task":invalid})).unwrap();
        assert!(response["reason"]
            .as_str()
            .unwrap()
            .contains("distinct step IDs"));
        invalid = task();
        invalid["plan"][0]["id"] = json!("PRIVATE REQUEST CONTENT");
        let response = call(&missing, json!({"operation":"propose","task":invalid})).unwrap();
        assert!(!response.to_string().contains("PRIVATE REQUEST CONTENT"));
        // A corrected proposal is admitted but never activated automatically.
        let path = dir.path().join("tasks.sqlite");
        assert_eq!(
            call(&path, json!({"operation":"propose","task":task()})).unwrap()["accepted"],
            false
        );
        assert!(call(&path, json!({"operation":"list"})).unwrap()["tasks"]
            .as_array()
            .unwrap()
            .is_empty());
    }

    #[test]
    fn proposals_do_not_listen_until_host_acceptance() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        let result = call(&path, json!({"operation":"propose","task":task()})).unwrap();
        assert_eq!(result["accepted"], false);
        assert_eq!(call(&path, event()).unwrap()["status"], "ignored");
        assert!(call(&path, json!({"operation":"accept","id":"task1","contracts":{"host_inspect":"SafeToRepeat","host_action":"SafeToRepeat"}})).is_err());
        assert_eq!(
            call(&path, json!({"operation":"list"})).unwrap()["proposals"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
        call(&path, json!({"operation":"accept","id":"task1","contracts":{"host_inspect":"SafeToRepeat","host_action":"RequiresReconciliation"}})).unwrap();
        assert_eq!(
            call(&path, event()).unwrap()["jobs"]
                .as_array()
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn admitted_job_execution_checkpoints_are_not_replaced_by_redelivery() {
        use crate::{
            workflow::{Executor, Outcome, Workflow},
            workflow_runtime::StorageJournal,
        };
        use std::sync::atomic::AtomicBool;
        struct Inspect;
        impl Executor for Inspect {
            fn execute(&mut self, _: &str, _: &Step, _: &AtomicBool) -> Outcome {
                Outcome::Succeeded(json!({"status":"succeeded","sample":42}))
            }
        }
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tasks.sqlite");
        call(&path, json!({"operation":"create","task":task()})).unwrap();
        let receipt = call(&path, event()).unwrap();
        let definition: Progress = serde_json::from_value(receipt["jobs"][0].clone()).unwrap();
        let id = definition.id.clone();
        let mut owner = Workflow::open(StorageJournal::open(&path).unwrap(), definition).unwrap();
        owner
            .run_next(&mut Inspect, &AtomicBool::new(false))
            .unwrap();
        drop(owner);
        call(&path, event()).unwrap();
        let original = call(&path, json!({"operation":"job","id":id})).unwrap();
        assert_eq!(original["steps"][0]["state"], "Pending");
        let snapshot = call(&path, json!({"operation":"list"})).unwrap();
        assert_eq!(
            snapshot["events"][0]["jobs"][0]["steps"][0]["state"],
            "Succeeded"
        );
        assert_eq!(
            snapshot["events"][0]["jobs"][0]["steps"][0]["output"]["value"]["sample"],
            42
        );
        let reopened = Workflow::open(
            StorageJournal::open(&path).unwrap(),
            serde_json::from_value(original).unwrap(),
        )
        .unwrap();
        assert_eq!(
            reopened.progress().steps[0].state,
            crate::workflow::StepState::Succeeded
        );
    }
}
