import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photolib/core/feature_flags.dart';
import 'package:photolib/core/keystore.dart';
import 'package:photolib/core/log_native.dart'
    if (dart.library.js_interop) 'package:photolib/core/log_web.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/core/replica.dart';

/// Riverpod's retries, but none for a missing keyring, which only the user can
/// start: the library says so and offers to try again.
Duration? retry(int count, Object error) => error is KeystoreUnavailable
    ? null
    : ProviderContainer.defaultRetry(count, error);

/// The newest records of the root isolate's log, for Settings › Diagnostics.
final Provider<MemoryLog> memoryLogProvider = Provider((ref) {
  final log = MemoryLog();
  ref.onDispose(log.dispose);
  return log;
});

/// The app's root logger; reading it starts the in-memory log.
final Provider<Logger> loggerProvider = Provider((ref) {
  ref.watch(memoryLogProvider);
  return const Logger('photolib');
});

/// This build's log across restarts, kept from the first read on; a release
/// build's sealed under the vault (ADR-0115).
final logStoreProvider = Provider<LogStore>((ref) {
  final store = openLogStore(
    seal: ref.read(releaseBuildProvider)
        ? vaultSeal(() => ref.read(vaultProvider.future))
        : null,
  );
  final listening = Log.records.listen(store.add);
  ref.onDispose(listening.cancel);
  return store;
});

/// Whether this is a release build, whose log is redacted and whose
/// diagnostics hide behind an advanced setting (ADR-0115).
final Provider<bool> releaseBuildProvider = Provider((ref) => kReleaseMode);

/// The `PHOTOLIB_FLAGS` this build was made with.
final Provider<FeatureFlags> featureFlagsProvider = Provider(
  (ref) => FeatureFlags.parse(const String.fromEnvironment('PHOTOLIB_FLAGS')),
);
