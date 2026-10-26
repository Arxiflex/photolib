import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/servers.dart'
    show SecondFactorRequired;
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/tokens.dart';
import 'package:photolib_api/photolib_api.dart';
import 'package:photolib_data/photolib_data.dart' show KernelError;

/// What the user reads of a failure (OPS-30): its cause and the next step in
/// plain words; its detail, the technical text, only behind [ProblemView]'s
/// expander.
typedef Problem = ({String cause, String next, String detail});

/// A cause and its next step, in the user's language.
typedef Words = (String, String) Function(AppLocalizations s);

/// The error catalogue: the cause and next step of every reason photolibd
/// sends (`ApiError`). tools/tests/check_errors.py holds it to the server's
/// reasons and to every language.
final Map<String, Words> reasons = {
  'api_key.not_found': (s) => (s.problemGone, s.nextRefresh),
  'api_key.rate_limited': (s) => (s.problemTooMany, s.nextWait),
  'api_key.scope_missing': (s) => (s.problemNotAllowed, s.nextAskAdmin),
  'asset.not_found': (s) => (s.problemGone, s.nextRefresh),
  'backup.not_found': (s) => (s.problemGone, s.nextRefresh),
  'backup.restore': (s) => (s.problemRestoreKey, s.nextSignInAccount),
  'confirmation.required': (s) => (s.problemConfirm, s.nextConfirm),
  'device.not_found': (s) => (s.problemGone, s.nextRefresh),
  'disk.low': (s) => (s.problemDiskLow, s.nextAskAdmin),
  'faces.notice_outdated': (s) => (s.problemFaceNotice, s.nextUpdateAndAgree),
  'field.invalid': (s) => (s.problemInvalid, s.nextCheckEntry),
  'job.maintenance': (s) => (s.problemMaintenanceKey, s.nextSignInAccount),
  'job.not_cancellable': (s) => (s.problemChanged, s.nextRefresh),
  'job.not_paused': (s) => (s.problemChanged, s.nextRefresh),
  'job.not_retryable': (s) => (s.problemChanged, s.nextRefresh),
  'keys.exist': (s) => (s.problemExists, s.nextRefresh),
  'keys.kit_mismatch': (s) => (s.privacyKitOther, s.nextCheckEntry),
  'keys.no_password': (s) => (s.problemNotAllowed, s.nextAskAdmin),
  'keys.none': (s) => (s.problemChanged, s.nextRefresh),
  'keys.recovery_incomplete': (s) => (s.privacyNotReady, s.nextSetUpPrivate),
  'library.contribute_denied': (s) => (s.problemContribute, s.nextAskOwner),
  'library.not_external': (s) => (s.problemNotExternal, s.nextRefresh),
  'library.not_found': (s) => (s.problemGone, s.nextRefresh),
  'library.nothing_held': (s) => (s.problemChanged, s.nextRefresh),
  'library.root_differs': (s) => (s.problemRootDiffers, s.nextCheckEntry),
  'library.root_not_allowed': (s) => (s.problemRootNotAllowed, s.nextAddRoot),
  'library.root_overlaps': (s) => (s.problemRootOverlaps, s.nextOtherFolder),
  'library.scanning': (s) => (s.problemScanning, s.nextWait),
  'login.failed': (s) => (s.problemLoginFailed, s.nextCheckEntry),
  'login.insecure_http': (s) => (s.serverNeedsHttps, s.nextUseHttps),
  'login.throttled': (s) => (s.problemTooMany, s.nextWait),
  'oidc.claim_invalid': (s) => (s.problemOidcClaim, s.nextAskAdmin),
  'oidc.failed': (s) => (s.problemOidcFailed, s.nextTryAgain),
  'oidc.identity_taken': (s) => (s.problemOidcTaken, s.nextAskAdmin),
  'oidc.not_allowed': (s) => (s.problemOidcNotAllowed, s.nextAskAdmin),
  'oidc.provider_unknown': (s) => (s.problemOidcUnknown, s.nextRefresh),
  'oidc.unavailable': (s) => (s.problemOidcDown, s.nextWait),
  'passkey.exists': (s) => (s.problemExists, s.nextRefresh),
  'passkey.not_found': (s) => (s.problemGone, s.nextRefresh),
  'passkey.unavailable': (s) => (s.problemPasskeysOff, s.nextAskAdmin),
  'password_setup.invalid': (s) => (s.problemLinkInvalid, s.nextNewLink),
  'policy.disabled': (s) => (s.problemPolicyOff, s.nextAskAdmin),
  'quota.exceeded': (s) => (s.problemQuota, s.nextFreeSpace),
  'route.no_rule': (s) => (s.problemUnexpected, s.nextReport),
  'second_factor.required': (s) => (s.problemSecondFactor, s.nextAskAdmin),
  'server.internal': (s) => (s.problemUnexpected, s.nextReport),
  'session.required': (s) => (s.problemSignedOut, s.nextSignIn),
  'setting.pinned': (s) => (s.problemPinned, s.nextEditConfig),
  'setup.done': (s) => (s.problemSetupDone, s.nextSignInInstead),
  'setup.expired': (s) => (s.problemSetupExpired, s.nextTryAgain),
  'setup.token_invalid': (s) => (s.problemSetupToken, s.nextNewestToken),
  'step_up.required': (s) => (s.problemStepUp, s.nextTryAgain),
  'store.unavailable': (s) => (s.problemStorage, s.nextAskAdmin),
  'upload.complete': (s) => (s.problemExists, s.nextRefresh),
  'upload.hash_mismatch': (s) => (s.problemUploadDamaged, s.nextTryAgain),
  'upload.length_mismatch': (s) => (s.problemUploadDamaged, s.nextTryAgain),
  'upload.not_found': (s) => (s.problemUploadExpired, s.nextTryAgain),
  'upload.offset_mismatch': (s) => (s.problemInterrupted, s.nextTryAgain),
  'user.admin_required': (s) => (s.problemAdminOnly, s.nextAskAdmin),
  'user.email_taken': (s) => (s.problemEmailTaken, s.nextUseAnother),
  'user.handle_taken': (s) => (s.problemHandleTaken, s.nextUseAnother),
  'user.last_admin': (s) => (s.problemLastAdmin, s.nextOtherAdmin),
  'user.not_found': (s) => (s.problemGone, s.nextRefresh),
  'webhook.limit': (s) => (s.problemWebhookLimit, s.nextDeleteWebhook),
  'webhook.not_found': (s) => (s.problemGone, s.nextRefresh),
  'webhooks.disabled': (s) => (s.problemWebhooksOff, s.nextAskAdmin),
};

/// A Connect code without a reason this app knows, as from a newer server.
Words _code(String code) => switch (code) {
  'unauthenticated' => (s) => (s.problemSignedOut, s.nextSignIn),
  'permission_denied' => (s) => (s.problemNotAllowed, s.nextAskAdmin),
  'not_found' => (s) => (s.problemGone, s.nextRefresh),
  'already_exists' => (s) => (s.problemExists, s.nextRefresh),
  'invalid_argument' ||
  'out_of_range' => (s) => (s.problemInvalid, s.nextCheckEntry),
  'failed_precondition' ||
  'aborted' => (s) => (s.problemChanged, s.nextRefresh),
  'resource_exhausted' => (s) => (s.problemTooMany, s.nextWait),
  'unavailable' || 'deadline_exceeded' => (s) => (s.problemBusy, s.nextWait),
  _ => (s) => (s.problemUnexpected, s.nextReport),
};

/// The [Problem] of any failure.
Problem problemOf(AppLocalizations s, Object error) {
  final (cause, next) = switch (error) {
    ServerError(:final detail?) when reasons.containsKey(detail.code) =>
      reasons[detail.code]!(s),
    ServerError(:final code) => _code(code)(s),
    HttpsRequired() => reasons['login.insecure_http']!(s),
    Unreachable() => (s.problemUnreachable, s.nextCheckConnection),
    // Only the sign-in answers a challenge (ADR-0088).
    SecondFactorRequired() => reasons['second_factor.required']!(s),
    // The kernel finds a wrong password before the server does.
    KernelError(reason: 'envelope_recovery') => reasons['login.failed']!(s),
    _ => (s.problemUnexpected, s.nextReport),
  };
  return (cause: cause, next: next, detail: _detail(error));
}

String _detail(Object error) => switch (error) {
  ServerError(:final code, :final detail?) => [
    code,
    detail.code,
    for (final MapEntry(:key, :value) in detail.params.entries) '$key=$value',
  ].join(' '),
  // error-ok: the technical detail, behind ProblemView's expander
  _ => '$error',
};

/// A failure's cause and next step, an [action] that fixes it, and its
/// technical detail behind an expander, with a copy button.
class ProblemView extends StatelessWidget {
  /// The view of [error].
  const new(this.error, {super.key, this.action});

  /// The failure, of any type.
  final Object error;

  /// What the button says and does, such as *Check the connection*.
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    final problem = problemOf(s, error);
    final styles = Theme.of(context).textTheme;
    // Also outside the app's theme, as in place of a widget that failed.
    final tokens =
        Theme.of(context).extension<AppTokens>() ?? const AppTokens();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tokens.xs,
      children: [
        Text(
          problem.cause,
          style: styles.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        Text(problem.next),
        if (action case (final label, final onPressed))
          Padding(
            padding: EdgeInsets.only(top: tokens.xs),
            child: FilledButton.tonal(onPressed: onPressed, child: Text(label)),
          ),
        ExpansionTile(
          title: Text(s.problemDetails, style: styles.bodySmall),
          tilePadding: EdgeInsets.zero,
          expandedAlignment: AlignmentDirectional.centerStart,
          children: [
            SelectableText(
              problem.detail,
              style: styles.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: Text(s.problemCopy),
              onPressed: () => Clipboard.setData(
                ClipboardData(
                  text: [
                    problem.cause,
                    problem.next,
                    problem.detail,
                  ].join('\n'),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Shows [error]'s cause and next step in a snack bar, its detail one tap
/// away.
void showProblem(BuildContext context, Object error) {
  final s = AppLocalizations.of(context);
  final problem = problemOf(s, error);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('${problem.cause} ${problem.next}'),
      persist: false,
      action: SnackBarAction(
        label: s.problemDetails,
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            content: SingleChildScrollView(child: ProblemView(error)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(MaterialLocalizations.of(context).closeButtonLabel),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
