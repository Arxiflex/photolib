import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/errors.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/features/download/download.dart';
import 'package:photolib/features/download/download_action.dart';
import 'package:photolib/features/servers/servers.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/formats.dart';
import 'package:photolib/ui/adaptive.dart';
import 'package:photolib_data/photolib_data.dart';

/// The server's files that are no photo or video, newest first: kept, never
/// shown in the timeline, downloaded only as files (ADR-0066).
final StreamProvider<List<OtherFilesResult>> otherFilesProvider =
    StreamProvider.autoDispose((ref) async* {
      yield* (await ref.watch(replicaProvider.future)).otherFiles().watch();
    });

/// The other files, each with its size and, where this platform saves
/// downloads, a download of its original from the server.
class OtherFilesPage extends ConsumerWidget {
  /// The page of [otherFilesProvider].
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AppLocalizations.of(context);
    final formats = Formats(strings);
    final session = ref.watch(sessionProvider);
    final saves = ref.watch(destinationProvider) != null;
    Download download(Link session, OtherFilesResult file) => Download(
      file.name,
      () async {
        final media = await session.media('media/${uuidOf(file.id)}/original');
        return DownloadFile(
          media.bytes,
          modified: DateTime.fromMillisecondsSinceEpoch(file.createdAt),
          size: media.length,
        );
      },
    );
    return Scaffold(
      appBar: AppBar(title: Text(strings.otherFiles)),
      // A failed store or query says so over any list it showed before.
      body: switch (ref.watch(otherFilesProvider)) {
        AsyncError() => StoreErrorView(
          retry: () => ref.invalidate(otherFilesProvider),
        ),
        final files => ContentWidth(
          child: ListView(
            children: [
              for (final file in files.value ?? const <OtherFilesResult>[])
                ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(file.name),
                  subtitle: switch (file.size) {
                    final size? => Text(formats.fileSize(size)),
                    null => null,
                  },
                  trailing: session == null || !saves
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.download_outlined),
                          tooltip: strings.download,
                          onPressed: () => downloadFile(
                            context,
                            ref,
                            download(session, file),
                          ),
                        ),
                ),
            ],
          ),
        ),
      },
    );
  }
}
