import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/problems.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib_api/photolib_api.dart'
    show CallError, GetTextRequest, SearchServiceApi;
import 'package:photolib_data/photolib_data.dart' show uuidOf;

/// Shows the text OCR read from the server's picture [asset] and copies it on
/// request, or says that it holds none or was not read yet. The text is what
/// a picture says, whoever made it: it is only ever a string in a text widget
/// and on the clipboard, never parsed (threat model T33).
Future<void> showPhotoText(
  BuildContext context,
  WidgetRef ref,
  Uint8List asset,
) async {
  final strings = AppLocalizations.of(context);
  final link = ref.read(sessionProvider);
  if (link == null) return;
  final String text;
  final bool read;
  try {
    final answer = await SearchServiceApi(link)
        .getText(null, GetTextRequest(assetId: uuidOf(asset)));
    (text, read) = (answer.text, answer.read);
  } on CallError catch (error) {
    if (context.mounted) showProblem(context, error);
    return;
  }
  if (!context.mounted) return;
  if (text.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(read ? strings.viewerTextNone : strings.viewerTextUnread),
        persist: false,
      ),
    );
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.viewerText),
      content: SingleChildScrollView(child: SelectableText(text)),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (!context.mounted) return;
            Navigator.of(context).pop();
            messenger.showSnackBar(
              SnackBar(content: Text(strings.viewerTextCopied), persist: false),
            );
          },
          child: Text(strings.viewerCopyText),
        ),
      ],
    ),
  );
}
