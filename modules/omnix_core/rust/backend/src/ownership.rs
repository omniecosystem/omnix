// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Host-scoped, single-flight model ownership, independent of bridge registries.

use crate::{
    Conversation, ConversationOptions, CoreError, CoreMessage, LoadedModel, StreamOutcome,
};
use std::{
    collections::BTreeMap,
    sync::{atomic::AtomicBool, Arc, Condvar, Mutex, Weak},
};

type Engine = Arc<Mutex<Box<dyn LoadedModel>>>;
enum State {
    Loading,
    Ready(Weak<Mutex<Box<dyn LoadedModel>>>),
    Failed(CoreError),
}
struct Entry {
    state: Mutex<State>,
    ready: Condvar,
}

/// Shares compatible loads without retaining unused native engines indefinitely.
///
/// Hosts must key by artifact identity and every engine-affecting setting.
/// Separate pools are independent; keys do not grant authority or verify files.
pub struct ModelPool<K> {
    entries: Mutex<BTreeMap<K, Arc<Entry>>>,
    admission: Option<crate::execution::ExecutionAdmission>,
    admission_wait: std::time::Duration,
}

impl<K> Default for ModelPool<K> {
    fn default() -> Self {
        Self {
            entries: Mutex::new(BTreeMap::new()),
            admission: None,
            admission_wait: std::time::Duration::ZERO,
        }
    }
}

fn unavailable() -> CoreError {
    CoreError::BackendFailure("model-pool-unavailable".into())
}

impl<K: Ord> ModelPool<K> {
    /// Shares cold-load and inference capacity across this pool's models.
    /// Cached leases and single-flight followers do not acquire another slot.
    /// Slots are released before host tool execution. Embedding providers
    /// outside this pool are not admitted by this gate.
    pub fn with_admission(
        admission: crate::execution::ExecutionAdmission,
        admission_wait: std::time::Duration,
    ) -> Self {
        Self {
            admission: Some(admission),
            admission_wait,
            ..Self::default()
        }
    }
    /// Returns an independently releasable lease, initializing once per live key.
    ///
    /// Concurrent waiters receive the same initialization error. A later request
    /// may retry. Native initialization runs outside the pool's directory lock.
    pub fn acquire(
        &self,
        key: K,
        load: impl FnOnce() -> Result<Box<dyn LoadedModel>, CoreError>,
    ) -> Result<SharedModel, CoreError> {
        let (entry, leader) = {
            let mut entries = self.entries.lock().map_err(|_| unavailable())?;
            entries.retain(|_, entry| {
                Arc::strong_count(entry) > 1
                    || match entry.state.lock() {
                        Ok(state) => match &*state {
                            State::Loading => true,
                            State::Ready(engine) => engine.strong_count() > 0,
                            State::Failed(_) => false,
                        },
                        Err(_) => false,
                    }
            });
            match entries.get(&key) {
                Some(entry) => (entry.clone(), false),
                None => {
                    let entry = Arc::new(Entry {
                        state: Mutex::new(State::Loading),
                        ready: Condvar::new(),
                    });
                    entries.insert(key, entry.clone());
                    (entry, true)
                }
            }
        };
        if !leader {
            let mut state = entry.state.lock().map_err(|_| unavailable())?;
            loop {
                match &*state {
                    State::Loading => state = entry.ready.wait(state).map_err(|_| unavailable())?,
                    State::Failed(error) => return Err(error.clone()),
                    State::Ready(engine) => match engine.upgrade() {
                        Some(engine) => {
                            return SharedModel::new(
                                engine,
                                self.admission.clone(),
                                self.admission_wait,
                            )
                        }
                        None => {
                            *state = State::Loading;
                            break;
                        }
                    },
                }
            }
        }
        let mut pending = Pending {
            entry: entry.clone(),
            completed: false,
        };
        // Only the single-flight leader admits initialization. Publish admission
        // failures like loader failures so followers wake and later calls can retry.
        // Keep the permit scoped to native loading, outside directory/state locks.
        let result = (|| {
            let _permit = self
                .admission
                .as_ref()
                .map(|gate| {
                    gate.acquire(&AtomicBool::new(false), self.admission_wait)
                        .map_err(|error| CoreError::BackendFailure(error.to_string()))
                })
                .transpose()?;
            load().map(|model| Arc::new(Mutex::new(model)))
        })();
        {
            let mut state = entry.state.lock().map_err(|_| unavailable())?;
            *state = match &result {
                Ok(engine) => State::Ready(Arc::downgrade(engine)),
                Err(error) => State::Failed(error.clone()),
            };
        }
        pending.completed = true;
        entry.ready.notify_all();
        SharedModel::new(result?, self.admission.clone(), self.admission_wait)
    }

    /// Counts engines retained by model leases or their conversations.
    pub fn live_models(&self) -> Result<usize, CoreError> {
        let entries = self.entries.lock().map_err(|_| unavailable())?;
        let mut count = 0;
        for entry in entries.values() {
            if let State::Ready(engine) = &*entry.state.lock().map_err(|_| unavailable())? {
                count += usize::from(engine.strong_count() > 0);
            }
        }
        Ok(count)
    }
}

struct Pending {
    entry: Arc<Entry>,
    completed: bool,
}
impl Drop for Pending {
    fn drop(&mut self) {
        if !self.completed {
            if let Ok(mut state) = self.entry.state.lock() {
                *state = State::Failed(CoreError::BackendFailure("model-load-aborted".into()));
            }
            self.entry.ready.notify_all();
        }
    }
}

/// An independent owner of a shared model, not a shared conversation history.
#[derive(Clone)]
pub struct SharedModel {
    engine: Engine,
    provider: String,
    admission: Option<crate::execution::ExecutionAdmission>,
    admission_wait: std::time::Duration,
}
impl SharedModel {
    fn new(
        engine: Engine,
        admission: Option<crate::execution::ExecutionAdmission>,
        admission_wait: std::time::Duration,
    ) -> Result<Self, CoreError> {
        let provider = engine
            .lock()
            .map_err(|_| unavailable())?
            .provider_id()
            .to_owned();
        Ok(Self {
            engine,
            provider,
            admission,
            admission_wait,
        })
    }
    fn admit(
        &self,
        cancel: &AtomicBool,
    ) -> Result<Option<crate::execution::ExecutionPermit>, CoreError> {
        self.admission
            .as_ref()
            .map(|gate| {
                gate.acquire(cancel, self.admission_wait)
                    .map_err(|error| CoreError::BackendFailure(error.to_string()))
            })
            .transpose()
    }
}
impl LoadedModel for SharedModel {
    fn provider_id(&self) -> &str {
        &self.provider
    }
    #[cfg(feature = "tools")]
    fn start_tool_conversation(
        &self,
        options: ConversationOptions,
        tools: Vec<crate::tools::ToolDefinition>,
    ) -> Result<Box<dyn crate::tools::ToolConversation>, CoreError> {
        let conversation = self
            .engine
            .lock()
            .map_err(|_| unavailable())?
            .start_tool_conversation(options, tools)?;
        Ok(Box::new(RetainedToolConversation {
            conversation,
            _owner: self.clone(),
        }))
    }
    fn start_conversation(
        &self,
        options: ConversationOptions,
    ) -> Result<Box<dyn Conversation>, CoreError> {
        let conversation = self
            .engine
            .lock()
            .map_err(|_| unavailable())?
            .start_conversation(options)?;
        Ok(Box::new(RetainedConversation {
            conversation,
            _owner: self.clone(),
        }))
    }
}
#[cfg(feature = "tools")]
struct RetainedToolConversation {
    conversation: Box<dyn crate::tools::ToolConversation>,
    _owner: SharedModel,
}
#[cfg(feature = "tools")]
impl crate::tools::ToolConversation for RetainedToolConversation {
    #[cfg(feature = "history")]
    fn import_portable_history(
        &mut self,
        history: Vec<crate::history::HistoryTurn>,
    ) -> Result<(), CoreError> {
        self.conversation.import_portable_history(history)
    }
    fn restore_checkpoint_with_thinking(
        &mut self,
        checkpoint: &str,
        enabled: bool,
    ) -> Result<(), CoreError> {
        self.conversation
            .restore_checkpoint_with_thinking(checkpoint, enabled)
    }
    fn set_thinking(&mut self, enabled: bool) -> Result<(), CoreError> {
        self.conversation.set_thinking(enabled)
    }
    fn send_message_events(
        &mut self,
        message: &CoreMessage,
        consumer: Box<dyn FnMut(crate::ConversationDelta) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<crate::tools::ToolTurn, CoreError> {
        let _permit = self._owner.admit(&cancel)?;
        self.conversation
            .send_message_events(message, consumer, cancel)
    }
    fn respond_events(
        &mut self,
        results: Vec<crate::tools::ToolResult>,
        consumer: Box<dyn FnMut(crate::ConversationDelta) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<crate::tools::ToolTurn, CoreError> {
        let _permit = self._owner.admit(&cancel)?;
        self.conversation.respond_events(results, consumer, cancel)
    }
    fn restore_interrupted_turn(
        &mut self,
        checkpoint: &str,
        message: &CoreMessage,
        partial: &str,
    ) -> Result<(), CoreError> {
        self.conversation
            .restore_interrupted_turn(checkpoint, message, partial)
    }
    fn restart(&mut self) -> Result<Box<dyn crate::tools::ToolConversation>, CoreError> {
        let conversation = self.conversation.restart()?;
        Ok(Box::new(Self {
            conversation,
            _owner: self._owner.clone(),
        }))
    }
    fn configure_context(
        &mut self,
        policy: Option<crate::working_context::SharedContextPolicy>,
    ) -> Result<(), CoreError> {
        self.conversation.configure_context(policy)
    }
    fn context_usage(&mut self) -> Result<Option<crate::working_context::ContextUsage>, CoreError> {
        self.conversation.context_usage()
    }
    fn import_chat_history(&mut self, history: Vec<(String, String)>) -> Result<(), CoreError> {
        self.conversation.import_chat_history(history)
    }
    fn import_chat_checkpoint(&mut self, context: &str) -> Result<(), CoreError> {
        self.conversation.import_chat_checkpoint(context)
    }
    fn set_tools_enabled(&mut self, enabled: bool) -> Result<(), CoreError> {
        self.conversation.set_tools_enabled(enabled)
    }
    fn reconfigure(
        &mut self,
        tokens: u32,
        sampling: Option<crate::SamplingOptions>,
    ) -> Result<(), CoreError> {
        self.conversation.reconfigure(tokens, sampling)
    }
    fn export_checkpoint(&mut self) -> Result<String, CoreError> {
        self.conversation.export_checkpoint()
    }
    fn restore_checkpoint(&mut self, checkpoint: &str) -> Result<(), CoreError> {
        self.conversation.restore_checkpoint(checkpoint)
    }
    fn send_message(&mut self, message: &CoreMessage) -> Result<crate::tools::ToolTurn, CoreError> {
        let _permit = self._owner.admit(&AtomicBool::new(false))?;
        self.conversation.send_message(message)
    }
    fn send_message_stream(
        &mut self,
        message: &CoreMessage,
        consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<crate::tools::ToolTurn, CoreError> {
        let _permit = self._owner.admit(&cancel)?;
        self.conversation
            .send_message_stream(message, consumer, cancel)
    }
    fn send(&mut self, text: &str) -> Result<crate::tools::ToolTurn, CoreError> {
        let _permit = self._owner.admit(&AtomicBool::new(false))?;
        self.conversation.send(text)
    }
    fn respond(
        &mut self,
        results: Vec<crate::tools::ToolResult>,
    ) -> Result<crate::tools::ToolTurn, CoreError> {
        let _permit = self._owner.admit(&AtomicBool::new(false))?;
        self.conversation.respond(results)
    }
    fn send_stream(
        &mut self,
        text: &str,
        consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<crate::tools::ToolTurn, CoreError> {
        let _permit = self._owner.admit(&cancel)?;
        self.conversation.send_stream(text, consumer, cancel)
    }
    fn respond_stream(
        &mut self,
        results: Vec<crate::tools::ToolResult>,
        consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<crate::tools::ToolTurn, CoreError> {
        let _permit = self._owner.admit(&cancel)?;
        self.conversation.respond_stream(results, consumer, cancel)
    }
}

struct RetainedConversation {
    conversation: Box<dyn Conversation>,
    _owner: SharedModel,
}
impl Conversation for RetainedConversation {
    #[cfg(feature = "history")]
    fn import_portable_history(
        &mut self,
        history: Vec<crate::history::HistoryTurn>,
    ) -> Result<(), CoreError> {
        self.conversation.import_portable_history(history)
    }
    fn restore_checkpoint_with_thinking(
        &mut self,
        checkpoint: &str,
        enabled: bool,
    ) -> Result<(), CoreError> {
        self.conversation
            .restore_checkpoint_with_thinking(checkpoint, enabled)
    }
    fn restore_history_with_thinking(
        &mut self,
        messages: Vec<(String, String)>,
        enabled: bool,
    ) -> Result<(), CoreError> {
        self.conversation
            .restore_history_with_thinking(messages, enabled)
    }
    fn set_thinking(&mut self, enabled: bool) -> Result<(), CoreError> {
        self.conversation.set_thinking(enabled)
    }
    fn send_message_events(
        &mut self,
        message: &CoreMessage,
        consumer: Box<dyn FnMut(crate::ConversationDelta) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<StreamOutcome, CoreError> {
        let _permit = self._owner.admit(&cancel)?;
        self.conversation
            .send_message_events(message, consumer, cancel)
    }
    fn configure_context(
        &mut self,
        policy: Option<crate::working_context::SharedContextPolicy>,
    ) -> Result<(), CoreError> {
        self.conversation.configure_context(policy)
    }
    fn context_usage(&mut self) -> Result<Option<crate::working_context::ContextUsage>, CoreError> {
        self.conversation.context_usage()
    }
    fn reconfigure(
        &mut self,
        tokens: u32,
        sampling: Option<crate::SamplingOptions>,
    ) -> Result<(), CoreError> {
        self.conversation.reconfigure(tokens, sampling)
    }
    fn send(&mut self, text: &str) -> Result<String, CoreError> {
        let _permit = self._owner.admit(&AtomicBool::new(false))?;
        self.conversation.send(text)
    }
    fn send_message(&mut self, message: &CoreMessage) -> Result<String, CoreError> {
        let _permit = self._owner.admit(&AtomicBool::new(false))?;
        self.conversation.send_message(message)
    }
    fn history(&mut self) -> Result<Vec<(String, String)>, CoreError> {
        self.conversation.history()
    }
    fn export_checkpoint(&mut self) -> Result<String, CoreError> {
        self.conversation.export_checkpoint()
    }
    fn restore_checkpoint(&mut self, checkpoint: &str) -> Result<(), CoreError> {
        self.conversation.restore_checkpoint(checkpoint)
    }
    fn restore_history(&mut self, history: Vec<(String, String)>) -> Result<(), CoreError> {
        self.conversation.restore_history(history)
    }
    fn send_stream(
        &mut self,
        text: &str,
        consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<StreamOutcome, CoreError> {
        let _permit = self._owner.admit(&cancel)?;
        self.conversation.send_stream(text, consumer, cancel)
    }
    fn send_message_stream(
        &mut self,
        message: &CoreMessage,
        consumer: Box<dyn FnMut(String) -> bool + Send>,
        cancel: Arc<AtomicBool>,
    ) -> Result<StreamOutcome, CoreError> {
        let _permit = self._owner.admit(&cancel)?;
        self.conversation
            .send_message_stream(message, consumer, cancel)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn retained_conversation_forwards_reasoning_without_erasing_channels() {
        struct StructuredChat;
        impl Conversation for StructuredChat {
            fn send(&mut self, _: &str) -> Result<String, CoreError> {
                unreachable!()
            }
            fn send_message_events(
                &mut self,
                _: &CoreMessage,
                mut consumer: Box<dyn FnMut(crate::ConversationDelta) -> bool + Send>,
                cancel: Arc<AtomicBool>,
            ) -> Result<StreamOutcome, CoreError> {
                if cancel.load(Ordering::Acquire)
                    || !consumer(crate::ConversationDelta::Reasoning("reason".into()))
                {
                    return Ok(StreamOutcome::Cancelled);
                }
                Ok(
                    if consumer(crate::ConversationDelta::Text("answer".into())) {
                        StreamOutcome::Completed
                    } else {
                        StreamOutcome::Cancelled
                    },
                )
            }
        }
        let pool = ModelPool::default();
        let model = pool
            .acquire("typed", || Ok(load(Arc::new(AtomicUsize::new(0)))))
            .unwrap();
        let mut chat = RetainedConversation {
            conversation: Box::new(StructuredChat),
            _owner: model,
        };
        let events = Arc::new(Mutex::new(Vec::new()));
        let delivered = events.clone();
        assert_eq!(
            chat.send_message_events(
                &CoreMessage::text("question"),
                Box::new(move |event| {
                    delivered.lock().unwrap().push(event);
                    false
                }),
                Arc::new(AtomicBool::new(false))
            )
            .unwrap(),
            StreamOutcome::Cancelled
        );
        assert_eq!(
            *events.lock().unwrap(),
            vec![crate::ConversationDelta::Reasoning("reason".into())]
        );
    }
    #[cfg(feature = "tools")]
    #[test]
    fn admission_covers_every_inference_entry_and_releases_before_tools() {
        use crate::{
            execution::ExecutionAdmission,
            tools::{ToolConversation, ToolResult, ToolTurn},
        };
        use std::time::Duration;
        struct ToolChat;
        impl ToolConversation for ToolChat {
            fn send(&mut self, _: &str) -> Result<ToolTurn, CoreError> {
                Ok(ToolTurn {
                    text: "ready".into(),
                    calls: vec![],
                })
            }
            fn respond(&mut self, _: Vec<ToolResult>) -> Result<ToolTurn, CoreError> {
                self.send("")
            }
            fn send_stream(
                &mut self,
                text: &str,
                _: Box<dyn FnMut(String) -> bool + Send>,
                _: Arc<AtomicBool>,
            ) -> Result<ToolTurn, CoreError> {
                self.send(text)
            }
            fn respond_stream(
                &mut self,
                _: Vec<ToolResult>,
                _: Box<dyn FnMut(String) -> bool + Send>,
                _: Arc<AtomicBool>,
            ) -> Result<ToolTurn, CoreError> {
                self.send("")
            }
        }
        struct Both;
        impl LoadedModel for Both {
            fn provider_id(&self) -> &str {
                "test"
            }
            fn start_conversation(
                &self,
                _: ConversationOptions,
            ) -> Result<Box<dyn Conversation>, CoreError> {
                Ok(Box::new(Chat(String::new())))
            }
            fn start_tool_conversation(
                &self,
                _: ConversationOptions,
                _: Vec<crate::tools::ToolDefinition>,
            ) -> Result<Box<dyn ToolConversation>, CoreError> {
                Ok(Box::new(ToolChat))
            }
        }
        let gate = ExecutionAdmission::new(1, 0).unwrap();
        let pool = ModelPool::with_admission(gate.clone(), Duration::ZERO);
        let model = pool.acquire("one", || Ok(Box::new(Both))).unwrap();
        let options = || ConversationOptions {
            thinking: false,
            system_prompt: None,
            max_output_tokens: 16,
            sampling: None,
        };
        let mut ordinary = model.start_conversation(options()).unwrap();
        let mut tools = model.start_tool_conversation(options(), vec![]).unwrap();
        let message = CoreMessage::text("hello");
        let flag = Arc::new(AtomicBool::new(false));
        let busy = CoreError::BackendFailure("execution-busy".into());
        let active = gate.acquire(&flag, Duration::ZERO).unwrap();
        assert_eq!(ordinary.send("hello").unwrap_err(), busy);
        assert_eq!(ordinary.send_message(&message).unwrap_err(), busy);
        assert_eq!(
            ordinary
                .send_stream("hello", Box::new(|_| true), flag.clone())
                .unwrap_err(),
            busy
        );
        assert_eq!(
            ordinary
                .send_message_stream(&message, Box::new(|_| true), flag.clone())
                .unwrap_err(),
            busy
        );
        assert_eq!(tools.send("hello").unwrap_err(), busy);
        assert_eq!(tools.send_message(&message).unwrap_err(), busy);
        assert_eq!(tools.respond(vec![]).unwrap_err(), busy);
        assert_eq!(
            tools
                .send_stream("hello", Box::new(|_| true), flag.clone())
                .unwrap_err(),
            busy
        );
        assert_eq!(
            tools
                .send_message_stream(&message, Box::new(|_| true), flag.clone())
                .unwrap_err(),
            busy
        );
        assert_eq!(
            tools
                .respond_stream(vec![], Box::new(|_| true), flag.clone())
                .unwrap_err(),
            busy
        );
        drop(active);
        assert_eq!(ordinary.send("hello").unwrap(), "hello");
        tools.send("hello").unwrap();
        tools.send_message(&message).unwrap();
        tools.respond(vec![]).unwrap();
        tools
            .send_stream("hello", Box::new(|_| true), flag.clone())
            .unwrap();
        tools
            .send_message_stream(&message, Box::new(|_| true), flag.clone())
            .unwrap();
        tools
            .respond_stream(vec![], Box::new(|_| true), flag.clone())
            .unwrap();
        assert_eq!(gate.snapshot().unwrap().active, 0);
        // A host executor can use the same capacity after the tool turn returns.
        let _host_inference = gate.acquire(&flag, Duration::ZERO).unwrap();
    }
    use std::sync::{
        atomic::{AtomicUsize, Ordering},
        Barrier,
    };
    #[cfg(feature = "tools")]
    #[test]
    fn retained_tool_conversations_forward_media_streams_errors_and_keep_model_alive() {
        use crate::{tools::*, MessagePart};
        struct MediaModel {
            message: CoreMessage,
            cancel: Arc<AtomicBool>,
            drops: Arc<AtomicUsize>,
        }
        impl Drop for MediaModel {
            fn drop(&mut self) {
                self.drops.fetch_add(1, Ordering::SeqCst);
            }
        }
        impl LoadedModel for MediaModel {
            fn provider_id(&self) -> &str {
                "media-tools"
            }
            fn start_tool_conversation(
                &self,
                _: ConversationOptions,
                _: Vec<ToolDefinition>,
            ) -> Result<Box<dyn ToolConversation>, CoreError> {
                Ok(Box::new(MediaChat {
                    message: self.message.clone(),
                    cancel: self.cancel.clone(),
                }))
            }
        }
        struct MediaChat {
            message: CoreMessage,
            cancel: Arc<AtomicBool>,
        }
        impl ToolConversation for MediaChat {
            fn export_checkpoint(&mut self) -> Result<String, CoreError> {
                Ok("owned context".into())
            }
            fn restore_checkpoint(&mut self, checkpoint: &str) -> Result<(), CoreError> {
                assert_eq!(checkpoint, "owned context");
                Ok(())
            }
            fn set_tools_enabled(&mut self, enabled: bool) -> Result<(), CoreError> {
                if enabled {
                    Err(CoreError::BackendFailure("switch-rejected".into()))
                } else {
                    Ok(())
                }
            }
            fn send(&mut self, _: &str) -> Result<ToolTurn, CoreError> {
                panic!("media must not use text-only fallback")
            }
            fn respond(&mut self, _: Vec<ToolResult>) -> Result<ToolTurn, CoreError> {
                unreachable!()
            }
            fn send_message(&mut self, message: &CoreMessage) -> Result<ToolTurn, CoreError> {
                assert_eq!(message, &self.message);
                Ok(ToolTurn {
                    text: "media answer".into(),
                    calls: vec![],
                })
            }
            fn send_message_stream(
                &mut self,
                message: &CoreMessage,
                mut consumer: Box<dyn FnMut(String) -> bool + Send>,
                cancel: Arc<AtomicBool>,
            ) -> Result<ToolTurn, CoreError> {
                assert_eq!(message, &self.message);
                assert!(Arc::ptr_eq(&cancel, &self.cancel));
                if cancel.load(Ordering::SeqCst) {
                    return Err(CoreError::BackendFailure("cancelled-media-turn".into()));
                }
                assert!(consumer("media delta".into()));
                Ok(ToolTurn {
                    text: "media answer".into(),
                    calls: vec![],
                })
            }
        }
        // The spy tests lossless forwarding, not decoder admission. Encoded
        // format validation remains the provider's responsibility.
        for part in [
            MessagePart::Audio(vec![1, 2]),
            MessagePart::Image(vec![3, 4]),
        ] {
            let message = CoreMessage {
                parts: vec![MessagePart::Text("Use tools if needed".into()), part],
            };
            let drops = Arc::new(AtomicUsize::new(0));
            let cancel = Arc::new(AtomicBool::new(false));
            let pool = ModelPool::default();
            let model = pool
                .acquire("media", || {
                    Ok(Box::new(MediaModel {
                        message: message.clone(),
                        cancel: cancel.clone(),
                        drops: drops.clone(),
                    }))
                })
                .unwrap();
            let options = || ConversationOptions {
                thinking: false,
                system_prompt: None,
                max_output_tokens: 32,
                sampling: None,
            };
            let mut chat = model.start_tool_conversation(options(), vec![]).unwrap();
            let mut stream = model.start_tool_conversation(options(), vec![]).unwrap();
            drop(model);
            assert_eq!(drops.load(Ordering::SeqCst), 0);
            assert_eq!(chat.send_message(&message).unwrap().text, "media answer");
            assert_eq!(chat.export_checkpoint().unwrap(), "owned context");
            chat.restore_checkpoint("owned context").unwrap();
            chat.set_tools_enabled(false).unwrap();
            assert_eq!(
                chat.set_tools_enabled(true).unwrap_err(),
                CoreError::BackendFailure("switch-rejected".into())
            );
            let deltas = Arc::new(Mutex::new(Vec::new()));
            let received = deltas.clone();
            assert_eq!(
                stream
                    .send_message_stream(
                        &message,
                        Box::new(move |delta| {
                            received.lock().unwrap().push(delta);
                            true
                        }),
                        cancel.clone()
                    )
                    .unwrap()
                    .text,
                "media answer"
            );
            assert_eq!(*deltas.lock().unwrap(), vec!["media delta"]);
            cancel.store(true, Ordering::SeqCst);
            assert_eq!(
                stream
                    .send_message_stream(&message, Box::new(|_| panic!("cancelled")), cancel)
                    .unwrap_err(),
                CoreError::BackendFailure("cancelled-media-turn".into())
            );
            drop(chat);
            assert_eq!(drops.load(Ordering::SeqCst), 0);
            drop(stream);
            assert_eq!(drops.load(Ordering::SeqCst), 1);
            assert_eq!(pool.live_models().unwrap(), 0);
        }
    }
    struct Model(Arc<AtomicUsize>);
    impl Drop for Model {
        fn drop(&mut self) {
            self.0.fetch_add(1, Ordering::SeqCst);
        }
    }
    impl LoadedModel for Model {
        fn provider_id(&self) -> &str {
            "test"
        }
        fn start_conversation(
            &self,
            _: ConversationOptions,
        ) -> Result<Box<dyn Conversation>, CoreError> {
            Ok(Box::new(Chat(String::new())))
        }
    }
    struct Chat(String);
    impl Conversation for Chat {
        fn send(&mut self, text: &str) -> Result<String, CoreError> {
            self.0.push_str(text);
            Ok(self.0.clone())
        }
    }
    fn load(drops: Arc<AtomicUsize>) -> Box<dyn LoadedModel> {
        Box::new(Model(drops))
    }
    #[test]
    fn concurrent_requests_initialize_once_and_release_after_last_owner() {
        let pool = Arc::new(ModelPool::default());
        let barrier = Arc::new(Barrier::new(8));
        let loads = Arc::new(AtomicUsize::new(0));
        let drops = Arc::new(AtomicUsize::new(0));
        let threads: Vec<_> = (0..8)
            .map(|_| {
                let (pool, barrier, loads, drops) =
                    (pool.clone(), barrier.clone(), loads.clone(), drops.clone());
                std::thread::spawn(move || {
                    barrier.wait();
                    pool.acquire("same", || {
                        loads.fetch_add(1, Ordering::SeqCst);
                        Ok(load(drops))
                    })
                    .unwrap()
                })
            })
            .collect();
        let leases: Vec<_> = threads
            .into_iter()
            .map(|thread| thread.join().unwrap())
            .collect();
        assert_eq!(loads.load(Ordering::SeqCst), 1);
        assert_eq!(pool.live_models().unwrap(), 1);
        drop(leases);
        assert_eq!(drops.load(Ordering::SeqCst), 1);
        assert_eq!(pool.live_models().unwrap(), 0);
    }
    #[test]
    fn conversations_keep_ownership_but_not_shared_history() {
        let pool = ModelPool::default();
        let drops = Arc::new(AtomicUsize::new(0));
        let model = pool.acquire("key", || Ok(load(drops.clone()))).unwrap();
        let options = ConversationOptions {
            thinking: false,
            system_prompt: None,
            max_output_tokens: 16,
            sampling: None,
        };
        let mut a = model.start_conversation(options.clone()).unwrap();
        let mut b = model.start_conversation(options).unwrap();
        drop(model);
        let reacquired = pool
            .acquire("key", || {
                panic!("must not reload while a conversation owns the model")
            })
            .unwrap();
        assert_eq!(a.send("a").unwrap(), "a");
        assert_eq!(b.send("b").unwrap(), "b");
        drop(reacquired);
        drop(a);
        assert_eq!(drops.load(Ordering::SeqCst), 0);
        drop(b);
        assert_eq!(drops.load(Ordering::SeqCst), 1);
    }
    #[test]
    fn distinct_settings_are_separate_and_failed_loads_can_retry() {
        let pool = ModelPool::default();
        assert!(pool
            .acquire(("model", 1024), || Err(CoreError::InvalidRequest))
            .is_err());
        let drops = Arc::new(AtomicUsize::new(0));
        let a = pool
            .acquire(("model", 1024), || Ok(load(drops.clone())))
            .unwrap();
        let b = pool
            .acquire(("model", 2048), || Ok(load(drops.clone())))
            .unwrap();
        assert_eq!(pool.live_models().unwrap(), 2);
        drop(a);
        drop(b);
        assert_eq!(drops.load(Ordering::SeqCst), 2);
    }
    #[test]
    fn cold_load_rejects_contention_but_cached_leases_do_not() {
        use crate::execution::ExecutionAdmission;
        use std::time::Duration;
        let gate = ExecutionAdmission::new(1, 0).unwrap();
        let pool = ModelPool::with_admission(gate.clone(), Duration::ZERO);
        let drops = Arc::new(AtomicUsize::new(0));
        let cached = pool.acquire("cached", || Ok(load(drops.clone()))).unwrap();
        let permit = gate
            .acquire(&AtomicBool::new(false), Duration::ZERO)
            .unwrap();
        let second = pool
            .acquire("cached", || panic!("must reuse live model"))
            .unwrap();
        assert!(matches!(
            pool.acquire("cold", || panic!("rejected load must not run")),
            Err(CoreError::BackendFailure(code)) if code == "execution-busy"
        ));
        assert_eq!(gate.snapshot().unwrap().active, 1);
        drop(permit);
        let cold = pool.acquire("cold", || Ok(load(drops.clone()))).unwrap();
        assert_eq!(gate.snapshot().unwrap().active, 0);
        drop((cached, second, cold));
        assert_eq!(drops.load(Ordering::SeqCst), 2);
    }
    #[test]
    fn cold_load_waits_for_capacity_and_single_flight_uses_one_slot() {
        use crate::execution::ExecutionAdmission;
        use std::time::{Duration, Instant};
        let gate = ExecutionAdmission::new(1, 1).unwrap();
        let pool = Arc::new(ModelPool::with_admission(
            gate.clone(),
            Duration::from_secs(5),
        ));
        let permit = gate
            .acquire(&AtomicBool::new(false), Duration::ZERO)
            .unwrap();
        let loads = Arc::new(AtomicUsize::new(0));
        let first_pool = pool.clone();
        let first_loads = loads.clone();
        let first_gate = gate.clone();
        let first = std::thread::spawn(move || {
            first_pool.acquire("same", || {
                assert_eq!(first_gate.snapshot().unwrap().active, 1);
                first_loads.fetch_add(1, Ordering::SeqCst);
                Ok(load(Arc::new(AtomicUsize::new(0))))
            })
        });
        let deadline = Instant::now() + Duration::from_secs(5);
        while gate.snapshot().unwrap().waiting != 1 {
            assert!(Instant::now() < deadline, "cold load did not queue");
            std::thread::yield_now();
        }
        let second_pool = pool.clone();
        let second = std::thread::spawn(move || {
            second_pool.acquire("same", || panic!("follower must not load"))
        });
        while Arc::strong_count(pool.entries.lock().unwrap().get("same").unwrap()) < 4 {
            assert!(Instant::now() < deadline, "follower did not attach");
            std::thread::yield_now();
        }
        assert_eq!(gate.snapshot().unwrap().waiting, 1);
        drop(permit);
        let leases = (
            first.join().unwrap().unwrap(),
            second.join().unwrap().unwrap(),
        );
        assert_eq!(loads.load(Ordering::SeqCst), 1);
        assert_eq!(gate.snapshot().unwrap().active, 0);
        drop(leases);
    }
    #[test]
    fn failed_or_panicking_initialization_releases_capacity() {
        use crate::execution::ExecutionAdmission;
        use std::time::Duration;
        let gate = ExecutionAdmission::new(1, 0).unwrap();
        let pool = ModelPool::with_admission(gate.clone(), Duration::ZERO);
        assert!(matches!(
            pool.acquire("error", || Err(CoreError::InvalidRequest)),
            Err(CoreError::InvalidRequest)
        ));
        assert_eq!(gate.snapshot().unwrap().active, 0);
        assert!(std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _ = pool.acquire("panic", || panic!("aborted initialization"));
        }))
        .is_err());
        assert_eq!(gate.snapshot().unwrap().active, 0);
        let model = pool
            .acquire("panic", || Ok(load(Arc::new(AtomicUsize::new(0)))))
            .unwrap();
        drop(model);
    }
    #[test]
    fn cold_load_timeout_does_not_initialize_or_leave_a_stale_entry() {
        use crate::execution::ExecutionAdmission;
        use std::time::Duration;
        let gate = ExecutionAdmission::new(1, 1).unwrap();
        let pool = ModelPool::with_admission(gate.clone(), Duration::from_millis(20));
        let permit = gate
            .acquire(&AtomicBool::new(false), Duration::ZERO)
            .unwrap();
        assert!(matches!(
            pool.acquire("cold", || panic!("timed out load must not run")),
            Err(CoreError::BackendFailure(code)) if code == "execution-admission-timeout"
        ));
        assert_eq!(gate.snapshot().unwrap().waiting, 0);
        drop(permit);
        let model = pool
            .acquire("cold", || Ok(load(Arc::new(AtomicUsize::new(0)))))
            .unwrap();
        assert_eq!(gate.snapshot().unwrap().active, 0);
        drop(model);
    }
    #[test]
    fn abandoned_loader_does_not_leave_a_permanent_loading_entry() {
        let pool = ModelPool::default();
        let panic = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _ = pool.acquire("key", || panic!("test aborted load"));
        }));
        assert!(panic.is_err());
        let drops = Arc::new(AtomicUsize::new(0));
        let model = pool.acquire("key", || Ok(load(drops.clone()))).unwrap();
        drop(model);
        assert_eq!(drops.load(Ordering::SeqCst), 1);
        let model = pool.acquire("key", || Ok(load(drops.clone()))).unwrap();
        drop(model);
        assert_eq!(drops.load(Ordering::SeqCst), 2);
    }
    #[test]
    fn failed_single_flight_wakes_waiters_with_the_same_error() {
        let pool = Arc::new(ModelPool::default());
        let (started_tx, started_rx) = std::sync::mpsc::channel();
        let (release_tx, release_rx) = std::sync::mpsc::channel();
        let first_pool = pool.clone();
        let first = std::thread::spawn(move || {
            first_pool.acquire("key", || {
                started_tx.send(()).unwrap();
                release_rx.recv().unwrap();
                Err(CoreError::InvalidRequest)
            })
        });
        started_rx.recv().unwrap();
        let waiter_pool = pool.clone();
        let waiter = std::thread::spawn(move || {
            waiter_pool.acquire("key", || panic!("waiter must not initialize"))
        });
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
        while Arc::strong_count(pool.entries.lock().unwrap().get("key").unwrap()) < 4 {
            assert!(
                std::time::Instant::now() < deadline,
                "waiter did not attach"
            );
            std::thread::yield_now();
        }
        release_tx.send(()).unwrap();
        assert!(matches!(
            first.join().unwrap(),
            Err(CoreError::InvalidRequest)
        ));
        assert!(matches!(
            waiter.join().unwrap(),
            Err(CoreError::InvalidRequest)
        ));
        assert_eq!(pool.live_models().unwrap(), 0);
    }
}
