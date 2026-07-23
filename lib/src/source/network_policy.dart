/// Controls network access during source resolution.
enum NetworkPolicy {
  /// All network access allowed (default).
  allowed,

  /// Only download prebuilt artifacts; no source fetching.
  prebuiltsOnly,

  /// Only fetch sources; no prebuilt downloads.
  sourceOnly,

  /// No network access at all. Only local sources and caches.
  offline,
}
