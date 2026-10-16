//! Bridge only: task admission and persistence live in root Rust.
/// Applies a host-supplied catalogue command; no tools or OS schedulers run here.
pub fn task_command(database_path: String, command_json: String) -> Result<String, String> {
    #[cfg(all(feature = "workflow-local", not(target_arch = "wasm32")))]
    {
        crate::task_runtime::command(std::path::Path::new(&database_path), &command_json)
    }
    #[cfg(not(all(feature = "workflow-local", not(target_arch = "wasm32"))))]
    {
        let _ = (database_path, command_json);
        Err("Native local Workflow is not selected".into())
    }
}
