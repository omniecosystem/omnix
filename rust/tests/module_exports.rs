//! Facade features expose original module types, not duplicated wrapper types.

#[cfg(all(feature = "storage-qdrant", not(target_arch = "wasm32")))]
#[test]
fn qdrant_preserves_original_store_type() {
    assert_eq!(
        std::any::TypeId::of::<omnix::storage::QdrantStore>(),
        std::any::TypeId::of::<omnix_storage::QdrantStore>()
    );
}

#[cfg(feature = "core")]
#[test]
fn core_preserves_original_model_types() {
    let format: omnix_core::ModelFormat = omnix::core::ModelFormat::LiteRtLm;
    assert_eq!(format, omnix_core::ModelFormat::LiteRtLm);
}

#[cfg(all(
    any(feature = "storage", feature = "storage-rusqlite"),
    not(target_arch = "wasm32")
))]
#[test]
fn storage_preserves_original_store_type() {
    assert_eq!(
        std::any::TypeId::of::<omnix::storage::ConversationStore>(),
        std::any::TypeId::of::<omnix_storage::ConversationStore>()
    );
}

#[cfg(all(
    any(feature = "nexus", feature = "nexus-a2a"),
    not(target_arch = "wasm32")
))]
#[test]
fn nexus_preserves_original_identity_type() {
    assert_eq!(
        std::any::TypeId::of::<omnix::nexus::a2a::paired_auth::SigningIdentity>(),
        std::any::TypeId::of::<omnix_nexus::a2a::paired_auth::SigningIdentity>()
    );
}
