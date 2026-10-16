import 'dart:convert';
import 'dart:typed_data';
import 'rust/api/knowledge.dart' as native;
import 'rust_initialization.dart';

/// An attributed, stable document chunk.
final class OmnixKnowledgeRecord {
  /// Creates a chunk with an explicit public visibility choice.
  const OmnixKnowledgeRecord({
    required this.id,
    required this.documentId,
    required this.content,
    required this.title,
    this.location,
    this.public = false,
  });

  /// The stable chunk identifier.
  final String id;

  /// The owning document identifier.
  final String documentId;

  /// The original passage text.
  final String content;

  /// The source title presented with retrieval evidence.
  final String title;

  /// The optional source location.
  final String? location;

  /// Whether trusted host policy permits public retrieval.
  final bool public;

  /// Decodes a native document payload.
  factory OmnixKnowledgeRecord.fromJson(Map<String, dynamic> json) {
    final source = json['source'] as Map<String, dynamic>;
    return OmnixKnowledgeRecord(
      id: json['id'] as String,
      documentId: json['document_id'] as String,
      content: json['content'] as String,
      title: source['title'] as String,
      location: source['location'] as String?,
      public: json['public'] as bool,
    );
  }

  /// Encodes the versioned bridge payload.
  Map<String, dynamic> toJson() => {
    'id': id,
    'document_id': documentId,
    'content': content,
    'source': {'title': title, 'location': location},
    'public': public,
  };
}

/// A ranked passage with source attribution.
final class OmnixKnowledgeMatch {
  const OmnixKnowledgeMatch({required this.record, required this.similarity});

  /// The permitted source passage.
  final OmnixKnowledgeRecord record;

  /// The cosine similarity, not a confidence probability.
  final double similarity;
  factory OmnixKnowledgeMatch.fromJson(Map<String, dynamic> json) =>
      OmnixKnowledgeMatch(
        record: OmnixKnowledgeRecord.fromJson(
          json['record'] as Map<String, dynamic>,
        ),
        similarity: (json['similarity'] as num).toDouble(),
      );
}

/// A serialized profile-bound native Qdrant document index.
final class OmnixKnowledgeIndex {
  OmnixKnowledgeIndex._(this._handle);
  final BigInt _handle;
  Future<void> _tail = Future.value();
  Future<void>? _closing;

  /// Opens a dedicated store without adopting an incompatible embedding space.
  static Future<OmnixKnowledgeIndex> open({
    required String path,
    required String profile,
    required int dimension,
  }) async {
    await ensureRustInitialized();
    return OmnixKnowledgeIndex._(
      await native.knowledgeOpen(
        path: path,
        profile: profile,
        dimension: dimension,
      ),
    );
  }

  Future<T> _run<T>(Future<T> Function() action) {
    if (_closing != null) {
      return Future.error(StateError('Knowledge index closed.'));
    }
    final pending = _tail.then((_) => action());
    _tail = pending.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return pending;
  }

  /// Adds a document with a vector produced from the declared embedding profile.
  Future<void> addVector(OmnixKnowledgeRecord record, List<double> vector) =>
      _run(
        () => native.knowledgeAdd(
          handle: _handle,
          record: jsonEncode(record.toJson()),
          vector: Float32List.fromList(vector),
        ),
      );

  /// Searches only public records, with filtering before ranking.
  Future<List<OmnixKnowledgeMatch>> searchVector(
    List<double> vector, {
    int topK = 3,
    double threshold = 0.7,
  }) => _run(() async {
    final result = await native.knowledgeSearch(
      handle: _handle,
      vector: Float32List.fromList(vector),
      topK: topK,
      threshold: threshold,
    );
    return (jsonDecode(result) as List<dynamic>)
        .map(
          (item) => OmnixKnowledgeMatch.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  });

  /// Flushes accepted writes and releases the index once.
  Future<void> close() =>
      _closing ??= _tail.then((_) => native.knowledgeClose(handle: _handle));
}
