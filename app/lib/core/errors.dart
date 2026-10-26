import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/keystore.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/core/problems.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/app_localizations_en.dart';
import 'package:photolib/ui/tokens.dart';

/// Sends every uncaught error to [logger] and shows [ErrorView] in place of a
/// widget that fails to build.
void installErrorHandlers(Logger logger) {
  FlutterError.onError = (details) => logger.error(
    details.exceptionAsString(),
    fields: {'library': ?details.library},
    error: details.exception,
    stackTrace: details.stack,
  );
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.error('uncaught error', error: error, stackTrace: stack);
    return true;
  };
  ErrorWidget.builder = (_) => const ErrorView();
}

/// A page or part of one that failed: its [message], or the [ProblemView] of
/// its [error], and a retry.
class ErrorView extends StatelessWidget {
  /// The view of a failure.
  const new({super.key, this.message, this.error, this.onRetry});

  /// What failed, in the user's words; *Something went wrong* when null.
  final String? message;

  /// A failure to show as its [ProblemView] instead of [message].
  final Object? error;

  /// Tries again, when it can.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final strings =
        Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        AppLocalizationsEn();
    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(
            (Theme.of(context).extension<AppTokens>() ?? const AppTokens()).md,
          ),
          child: switch ((error, onRetry)) {
            (final Object error, final retry) => ProblemView(
              error,
              action: retry == null ? null : (strings.errorRetry, retry),
            ),
            _ => Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                const Icon(Icons.error_outline, size: 48),
                Text(
                  message ?? strings.errorTitle,
                  textAlign: TextAlign.center,
                ),
                if (onRetry != null)
                  FilledButton(
                    onPressed: onRetry,
                    child: Text(strings.errorRetry),
                  ),
              ],
            ),
          },
        ),
      ),
    );
  }
}

/// [ErrorView] for a page whose query over the local store failed: it says
/// when the store could not open, and Try again opens again what failed (the
/// vault, the replica) before [retry] runs the query again.
class StoreErrorView extends ConsumerWidget {
  /// Runs [retry] once the store is opened again.
  const new({required this.retry, super.key});

  /// Runs the page's query again.
  final VoidCallback retry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    return ErrorView(
      message: switch (ref.watch(replicaProvider).error) {
        null => null,
        KeystoreUnavailable() => strings.libraryNoKeyring,
        _ => strings.libraryStoreFailed,
      },
      onRetry: () {
        if (ref.exists(vaultProvider) && ref.read(vaultProvider).hasError) {
          ref.invalidate(vaultProvider);
        }
        if (ref.read(replicaProvider).hasError) {
          // The account's replica, which a failed open keeps failing.
          if (ref.read(replicaNameProvider).value case final name?) {
            ref.invalidate(openReplicaProvider(name));
          }
          ref.invalidate(replicaProvider);
        }
        retry();
      },
    );
  }
}
