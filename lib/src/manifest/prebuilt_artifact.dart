/// Describes a single prebuilt native artifact within a [PrebuiltManifest].
///
/// Each artifact has an archive name, integrity hashes for both the archive
/// and the extracted payload, and a description of the payload type.
final class PrebuiltArtifact {
  const PrebuiltArtifact({
    required this.archiveName,
    required this.archiveSha256,
    required this.payloadSha256,
    required this.payload,
  });

  /// The tarball filename in the GitHub release.
  ///
  /// Example: `pty-linux-x64.tar.gz`.
  final String archiveName;

  /// SHA-256 hash of the downloaded archive file.
  ///
  /// Verified before extraction to catch corruption or tampering early.
  final String archiveSha256;

  /// SHA-256 hash of the selected native library after extraction.
  ///
  /// Verified after extraction and selection to ensure the correct binary
  /// was unpacked.
  final String payloadSha256;

  /// Describes the type and naming of the expected payload within the archive.
  final ArtifactPayload payload;

  @override
  String toString() => 'PrebuiltArtifact($archiveName, payload: $payload)';
}

/// Describes the expected native binary payload within an archive.
///
/// See [DynamicLibraryPayload] and [StaticLibraryPayload].
sealed class ArtifactPayload {
  const ArtifactPayload();
}

/// A shared/dynamic library (`.so`, `.dylib`, `.dll`).
final class DynamicLibraryPayload extends ArtifactPayload {
  const DynamicLibraryPayload({
    required this.libraryStem,
    this.acceptVersionedNames = true,
  });

  /// The library stem without platform prefix or extension.
  ///
  /// Example: `portable_pty_rs` resolves to `libportable_pty_rs.so` on
  /// Linux, `libportable_pty_rs.dylib` on macOS, and
  /// `portable_pty_rs.dll` on Windows.
  final String libraryStem;

  /// Whether versioned library names are acceptable.
  ///
  /// When `true`, `libfoo.so.1.2` matches a canonical name of `libfoo.so`.
  /// Defaults to `true`.
  final bool acceptVersionedNames;

  @override
  String toString() =>
      'DynamicLibraryPayload($libraryStem, '
      'acceptVersionedNames: $acceptVersionedNames)';
}

/// A static library (`.a` archive).
final class StaticLibraryPayload extends ArtifactPayload {
  const StaticLibraryPayload({required this.libraryStem});

  /// The library stem without platform prefix or extension.
  ///
  /// Example: `portable_pty_rs` resolves to `libportable_pty_rs.a` on
  /// Unix-like systems.
  final String libraryStem;

  @override
  String toString() => 'StaticLibraryPayload($libraryStem)';
}
