import 'backends/unsupported_backend.dart';
import 'supported_platforms.dart';
import 'url_launcher_backend.dart';

/// Chooses the backend for [operatingSystem].
///
/// A pure function of the **name**, never of `Platform.operatingSystem`
/// directly. That is what lets every arm — including the ones this host is not
/// — be asserted from any machine; a resolver that read the ambient platform
/// could only ever have one of its branches tested.
///
/// The lookup is [supportedPlatforms], the same table the refusal message reads
/// its list from, so "listed as supported but not wired" is not a state this
/// can be in.
UrlLauncherBackend resolveUrlLauncherBackend(String operatingSystem) =>
    supportedPlatforms[operatingSystem]?.create() ??
    UnsupportedUrlLauncherBackend(operatingSystem);
