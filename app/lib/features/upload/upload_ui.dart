import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/features/upload/drops.dart';
import 'package:photolib/features/upload/upload.dart';
import 'package:photolib/l10n/app_localizations.dart';

/// The row over the library of a signed-in account: the button that picks
/// photos and videos to upload, and how the uploads go, with what to do about
/// the ones that failed. Files dropped on the window go the same way.
class UploadBar extends ConsumerWidget {
  /// The bar; nothing while signed out.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sessionProvider) == null) return const SizedBox.shrink();
    final strings = AppLocalizations.of(context);
    final items = ref.watch(uploadsProvider);
    final done = items.where((i) => i.state == UploadState.done).length;
    final failed = items.where((i) => i.state == UploadState.failed).length;
    final running = items.length - done - failed;
    final uploads = ref.read(uploadsProvider.notifier);
    // Half a file for its hashing, half for its sending, over the running.
    final progress = [
      for (final i in items)
        if (i.state == UploadState.hashing || i.state == UploadState.sending)
          i.hashed / 2 + (i.size == 0 ? 0 : i.sent / i.size / 2),
    ];
    return UploadDrops(
      onDrop: uploads.add,
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.upload_file),
                tooltip: strings.uploadAction,
                onPressed: () async {
                  final files = await ref.read(uploadPickerProvider)();
                  if (files.isNotEmpty) unawaited(uploads.add(files));
                },
              ),
              if (items.isNotEmpty) ...[
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      [
                        strings.uploadProgress(done, items.length),
                        if (failed > 0) strings.uploadsFailed(failed),
                      ].join(' · '),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (running == 0)
                  TextButton(
                    onPressed: uploads.clearFinished,
                    child: Text(strings.uploadClear),
                  ),
              ],
            ],
          ),
          if (running > 0)
            LinearProgressIndicator(
              value: progress.isEmpty
                  ? null
                  : progress.reduce((a, b) => a + b) / progress.length,
            ),
        ],
      ),
    );
  }
}
