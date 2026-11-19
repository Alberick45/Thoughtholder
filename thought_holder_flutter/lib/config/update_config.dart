/// Configuration and data structures for ThoughtHolder in-app updater.
class UpdateConfig {
  /// GitHub repository owner
  static const String repoOwner = 'Alberick45';

  /// GitHub repository name (public repository hosting the release assets)
  static const String repoName = 'Thoughtholder';

  /// Stable URL to the production version manifest
  static String get stableManifestUrl =>
      'https://github.com/$repoOwner/$repoName/releases/latest/download/version.json';

  /// Stable URL to the beta version manifest
  static String get betaManifestUrl =>
      'https://github.com/$repoOwner/$repoName/releases/latest/download/version-beta.json';
}

/// Asset metadata containing download URL and SHA-256 integrity checksum.
class PlatformReleaseAsset {
  final String url;
  final String sha256;

  const PlatformReleaseAsset({
    required this.url,
    required this.sha256,
  });

  factory PlatformReleaseAsset.fromJson(Map<String, dynamic> json) {
    return PlatformReleaseAsset(
      url: json['url'] as String? ?? '',
      sha256: (json['sha256'] as String? ?? '').toLowerCase(),
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'sha256': sha256,
      };
}

/// Manifest structure published in version.json
class VersionManifest {
  final String version;
  final int build;
  final int minSupportedBuild;
  final List<String> notes;
  final PlatformReleaseAsset? android;
  final PlatformReleaseAsset? windows;

  const VersionManifest({
    required this.version,
    required this.build,
    required this.minSupportedBuild,
    required this.notes,
    this.android,
    this.windows,
  });

  factory VersionManifest.fromJson(Map<String, dynamic> json) {
    return VersionManifest(
      version: json['version'] as String? ?? '1.0.0',
      build: (json['build'] as num?)?.toInt() ?? 1,
      minSupportedBuild: (json['minSupportedBuild'] as num?)?.toInt() ?? 1,
      notes: (json['notes'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      android: json['android'] is Map<String, dynamic>
          ? PlatformReleaseAsset.fromJson(json['android'] as Map<String, dynamic>)
          : null,
      windows: json['windows'] is Map<String, dynamic>
          ? PlatformReleaseAsset.fromJson(json['windows'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'build': build,
        'minSupportedBuild': minSupportedBuild,
        'notes': notes,
        if (android != null) 'android': android!.toJson(),
        if (windows != null) 'windows': windows!.toJson(),
      };
}

