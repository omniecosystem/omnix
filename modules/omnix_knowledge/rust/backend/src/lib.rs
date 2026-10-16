// Copyright 2026 The Omnix Authors
// SPDX-License-Identifier: Apache-2.0

//! Document-level retrieval independent of a particular model or database.
//! Embedders can be borrowed or own a synchronized Core model; the index owns
//! its store. Optional adapters provide native storage and Core integration;
//! the base contracts do not select a runtime or database.

use std::{error::Error, fmt};

pub mod text;

#[cfg(feature = "qdrant")]
pub mod qdrant;

#[cfg(feature = "core-adapter")]
pub mod core;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EmbeddingProfile {
    pub id: String,
    pub dimension: usize,
}

#[derive(Clone, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "qdrant", derive(serde::Serialize, serde::Deserialize))]
#[cfg_attr(feature = "qdrant", serde(deny_unknown_fields))]
pub struct Source {
    pub title: String,
    pub location: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
#[cfg_attr(feature = "qdrant", derive(serde::Serialize, serde::Deserialize))]
#[cfg_attr(feature = "qdrant", serde(deny_unknown_fields))]
pub struct Record {
    /// Stable chunk ID; changing the backend must not change this public ID.
    pub id: String,
    pub document_id: String,
    pub content: String,
    pub source: Source,
    pub public: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Match {
    pub record: Record,
    pub similarity: f32,
}

/// Supplied by trusted host policy, never inferred from a remote request.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AccessScope {
    PublicOnly,
    LocalAll,
}

#[derive(Clone, Copy, Debug)]
pub struct SearchOptions {
    pub top_k: usize,
    /// Cosine similarity threshold, not a probability.
    pub threshold: f32,
    pub scope: AccessScope,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum KnowledgeError {
    InvalidInput(&'static str),
    IncompatibleProfile,
    InvalidStoreResult,
    Backend(String),
}

impl fmt::Display for KnowledgeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidInput(message) => write!(f, "{message}"),
            Self::IncompatibleProfile => write!(f, "incompatible embedding profile"),
            Self::InvalidStoreResult => write!(f, "store violated retrieval contract"),
            Self::Backend(message) => write!(f, "knowledge backend: {message}"),
        }
    }
}
impl Error for KnowledgeError {}

/// Model execution belongs to Core. Document and query task conventions differ.
/// A borrowed provider must keep its declared profile stable for each operation.
pub trait Embedder {
    fn profile(&self) -> Result<EmbeddingProfile, KnowledgeError>;
    fn embed_document(&self, text: &str) -> Result<Vec<f32>, KnowledgeError>;
    fn embed_query(&self, text: &str) -> Result<Vec<f32>, KnowledgeError>;
}

/// Adapter contract for an already-open, profile-bound persistent store.
/// The profile must be read from durable storage, not adopted by dimension alone.
/// Search must apply access/threshold filters BEFORE top-k ranking. Record and
/// vector updates must be coherent; flush makes accepted mutations durable.
pub trait Store {
    fn profile(&self) -> Result<EmbeddingProfile, KnowledgeError>;
    fn upsert(&mut self, record: Record, vector: Vec<f32>) -> Result<(), KnowledgeError>;
    fn search(&self, vector: &[f32], options: SearchOptions) -> Result<Vec<Match>, KnowledgeError>;
    fn remove(&mut self, id: &str) -> Result<(), KnowledgeError>;
    fn flush(&mut self) -> Result<(), KnowledgeError>;
}

pub struct KnowledgeIndex<S: Store> {
    store: S,
    profile: EmbeddingProfile,
}

impl<S: Store> KnowledgeIndex<S> {
    pub fn open(store: S, expected: EmbeddingProfile) -> Result<Self, KnowledgeError> {
        if expected.id.trim().is_empty() || expected.dimension == 0 {
            return Err(KnowledgeError::InvalidInput("invalid embedding profile"));
        }
        if store.profile()? != expected {
            return Err(KnowledgeError::IncompatibleProfile);
        }
        Ok(Self {
            store,
            profile: expected,
        })
    }

    pub fn embedding_profile(&self) -> &EmbeddingProfile {
        &self.profile
    }

    pub fn add_vector(&mut self, record: Record, vector: Vec<f32>) -> Result<(), KnowledgeError> {
        validate_record(&record)?;
        self.validate_vector(&vector)?;
        self.store.upsert(record, vector)
    }

    pub fn add_text(
        &mut self,
        record: Record,
        embedder: &impl Embedder,
    ) -> Result<(), KnowledgeError> {
        validate_record(&record)?;
        self.check_embedder(embedder)?;
        let vector = embedder.embed_document(&record.content)?;
        // Detect provider switches during embedding, before writing anything.
        self.check_embedder(embedder)?;
        self.add_vector(record, vector)
    }

    /// Indexes a complete text document using explicit character-based chunks.
    /// All embeddings are checked before writes; storage writes are not transactional.
    pub fn add_text_document(
        &mut self,
        document: Record,
        embedder: &impl Embedder,
        options: text::TextChunkOptions,
    ) -> Result<usize, KnowledgeError> {
        let chunks = text::chunk_document(document, options)?;
        self.check_embedder(embedder)?;
        let mut prepared = Vec::with_capacity(chunks.len());
        for chunk in chunks {
            let vector = embedder.embed_document(&chunk.content)?;
            self.check_embedder(embedder)?;
            self.validate_vector(&vector)?;
            prepared.push((chunk, vector));
        }
        let count = prepared.len();
        for (chunk, vector) in prepared {
            self.add_vector(chunk, vector)?;
        }
        self.flush()?;
        Ok(count)
    }

    pub fn search_text(
        &self,
        query: &str,
        embedder: &impl Embedder,
        options: SearchOptions,
    ) -> Result<Vec<Match>, KnowledgeError> {
        if query.trim().is_empty() {
            return Err(KnowledgeError::InvalidInput("empty query"));
        }
        validate_options(options)?;
        self.check_embedder(embedder)?;
        let vector = embedder.embed_query(query)?;
        self.check_embedder(embedder)?;
        self.search_vector(&vector, options)
    }

    pub fn search_vector(
        &self,
        vector: &[f32],
        options: SearchOptions,
    ) -> Result<Vec<Match>, KnowledgeError> {
        validate_options(options)?;
        self.validate_vector(vector)?;
        let mut matches = self.store.search(vector, options)?;
        if matches.len() > options.top_k
            || matches.iter().any(|hit| {
                validate_record(&hit.record).is_err()
                    || !hit.similarity.is_finite()
                    || !(-1.0..=1.0).contains(&hit.similarity)
                    || hit.similarity < options.threshold
                    || (options.scope == AccessScope::PublicOnly && !hit.record.public)
            })
        {
            return Err(KnowledgeError::InvalidStoreResult);
        }
        matches.sort_by(|a, b| {
            b.similarity
                .total_cmp(&a.similarity)
                .then_with(|| a.record.id.cmp(&b.record.id))
        });
        if matches.iter().enumerate().any(|(i, hit)| {
            matches[..i]
                .iter()
                .any(|other| other.record.id == hit.record.id)
        }) {
            return Err(KnowledgeError::InvalidStoreResult);
        }
        Ok(matches)
    }

    pub fn remove(&mut self, id: &str) -> Result<(), KnowledgeError> {
        if id.trim().is_empty() {
            return Err(KnowledgeError::InvalidInput("empty record ID"));
        }
        self.store.remove(id)
    }

    /// Explicit durability boundary; dropping an index is not a flush guarantee.
    pub fn flush(&mut self) -> Result<(), KnowledgeError> {
        self.store.flush()
    }

    fn check_embedder(&self, embedder: &impl Embedder) -> Result<(), KnowledgeError> {
        if embedder.profile()? != self.profile {
            return Err(KnowledgeError::IncompatibleProfile);
        }
        Ok(())
    }

    fn validate_vector(&self, vector: &[f32]) -> Result<(), KnowledgeError> {
        if vector.len() != self.profile.dimension
            || vector.iter().any(|v| !v.is_finite())
            || vector.iter().all(|v| *v == 0.0)
        {
            return Err(KnowledgeError::InvalidInput("invalid cosine vector"));
        }
        Ok(())
    }
}

fn validate_record(record: &Record) -> Result<(), KnowledgeError> {
    if [
        &record.id,
        &record.document_id,
        &record.content,
        &record.source.title,
    ]
    .iter()
    .any(|value| value.trim().is_empty())
    {
        return Err(KnowledgeError::InvalidInput("incomplete knowledge record"));
    }
    Ok(())
}

fn validate_options(options: SearchOptions) -> Result<(), KnowledgeError> {
    if !(1..=100).contains(&options.top_k)
        || !options.threshold.is_finite()
        || !(-1.0..=1.0).contains(&options.threshold)
    {
        return Err(KnowledgeError::InvalidInput("invalid search options"));
    }
    Ok(())
}
