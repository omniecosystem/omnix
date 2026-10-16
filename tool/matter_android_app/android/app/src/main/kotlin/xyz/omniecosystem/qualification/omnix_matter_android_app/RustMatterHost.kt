package xyz.omniecosystem.qualification.omnix_matter_android_app

// Runs only on MatterProcessHost's existing SDK worker. No native pointer cast.
internal object RustMatterHost {
    init { System.loadLibrary("omnix_matter_android_host") }
    external fun verify(owner: MatterQualification): Boolean
}
