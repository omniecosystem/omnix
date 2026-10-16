//! Deterministic Unicode text chunking. Character counts are NOT token counts.
use crate::{validate_record, KnowledgeError, Record};

#[derive(Clone, Copy)]
pub struct TextChunkOptions {
    pub characters: usize,
    pub overlap: usize,
}
impl Default for TextChunkOptions {
    fn default() -> Self {
        Self {
            characters: 512,
            overlap: 64,
        }
    }
}

pub fn chunk_document(
    document: Record,
    options: TextChunkOptions,
) -> Result<Vec<Record>, KnowledgeError> {
    validate_record(&document)?;
    if document.content.len() > 128 * 1024
        || options.characters == 0
        || options.characters > 4096
        || options.overlap >= options.characters
    {
        return Err(KnowledgeError::InvalidInput(
            "invalid text size or chunk options",
        ));
    }
    let mut offsets: Vec<_> = document
        .content
        .char_indices()
        .map(|(offset, _)| offset)
        .collect();
    offsets.push(document.content.len());
    let length = offsets.len() - 1;
    if length <= options.characters {
        return Ok(vec![document]);
    }
    let mut chunks = Vec::new();
    let mut start = 0;
    while start < length {
        let end = (start + options.characters).min(length);
        let content = &document.content[offsets[start]..offsets[end]];
        if !content.trim().is_empty() {
            let mut chunk = Record {
                id: format!("{}::chars:{start}-{end}", document.id),
                document_id: document.document_id.clone(),
                content: content.into(),
                source: document.source.clone(),
                public: document.public,
            };
            chunk.source.location = Some(match &document.source.location {
                Some(location) => format!("{location}; chars:{start}-{end}"),
                None => format!("chars:{start}-{end}"),
            });
            chunks.push(chunk);
            if chunks.len() > 1024 {
                return Err(KnowledgeError::InvalidInput("too many text chunks"));
            }
        }
        if end == length {
            break;
        }
        start = end - options.overlap;
    }
    Ok(chunks)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn document(content: &str) -> Record {
        Record {
            id: "import-1".into(),
            document_id: "import-1".into(),
            content: content.into(),
            source: crate::Source {
                title: "notes.md".into(),
                location: None,
            },
            public: false,
        }
    }
    #[test]
    fn short_text_preserves_existing_record_identity() {
        let record = document("hello");
        assert_eq!(
            chunk_document(record.clone(), TextChunkOptions::default()).unwrap(),
            vec![record]
        );
    }
    #[test]
    fn unicode_overlap_identity_and_visibility_are_preserved() {
        let input = document("é🌍a你好z");
        let options = TextChunkOptions {
            characters: 4,
            overlap: 1,
        };
        let chunks = chunk_document(input.clone(), options).unwrap();
        assert_eq!(chunks, chunk_document(input, options).unwrap());
        assert_eq!(chunks[0].content, "é🌍a你");
        assert_eq!(chunks[1].content, "你好z");
        assert_eq!(chunks[1].id, "import-1::chars:3-6");
        assert!(chunks
            .iter()
            .all(|c| !c.public && c.document_id == "import-1" && c.source.title == "notes.md"));
    }
    #[test]
    fn invalid_options_and_oversized_documents_are_explicit() {
        for options in [
            TextChunkOptions {
                characters: 0,
                overlap: 0,
            },
            TextChunkOptions {
                characters: 4,
                overlap: 4,
            },
        ] {
            assert!(chunk_document(document("hello"), options).is_err());
        }
        assert!(chunk_document(
            document(&"a".repeat(128 * 1024 + 1)),
            TextChunkOptions::default()
        )
        .is_err());
    }
}
