import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/logging.dart';
import 'package:photolib/core/replica.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/formats.dart';
import 'package:photolib_data/photolib_data.dart';

const _log = Logger('photolib.folders');

/// The native folder picker of desktops, whose libraries are folders
/// (docs/10-client-app.md §8.1), opening in `initialDirectory`; null
/// elsewhere.
final folderPickerProvider =
    Provider<Future<String?> Function({String? initialDirectory})?>(
      (ref) =>
          !kIsWeb &&
              const {
                TargetPlatform.linux,
                TargetPlatform.macOS,
                TargetPlatform.windows,
              }.contains(defaultTargetPlatform)
          ? ({initialDirectory}) =>
                FileSelectorPlatform.instance.getDirectoryPathWithOptions(
                  FileDialogOptions(initialDirectory: initialDirectory),
                )
          : null,
    );

/// What the macOS sandbox lets the app read of the folders the user picked:
/// a security-scoped bookmark of each (FolderAccess.swift), resolved before
/// the app's Dart starts.
abstract interface class FolderAccess {
  /// Keeps a bookmark of [root], which the user has just picked.
  Future<void> keep(String root);

  /// Drops the bookmark of [root], which left the library.
  Future<void> forget(String root);

  /// The folders of [roots] the app can no longer read.
  Future<Set<String>> lost(Iterable<String> roots);
}

class _Bookmarks implements FolderAccess {
  const new();

  static const _channel = MethodChannel('org.photolib/folders');

  @override
  Future<void> keep(String root) => _call('keep', root);

  @override
  Future<void> forget(String root) => _call('forget', root);

  /// Resolved at start: those whose bookmarks did not resolve, or not to a
  /// folder the app can read.
  @override
  Future<Set<String>> lost(Iterable<String> roots) async => {
    ...?(await _call<List<Object?>>('lost', roots.toList()))?.cast<String>(),
  };

  static Future<T?> _call<T>(String method, Object folders) async {
    try {
      final result = await _channel.invokeMethod<T>(method, folders);
      _log.info(
        'bookmark $method',
        fields: {'folders': folders, 'lostFolders': ?result},
      );
      return result;
    } on PlatformException catch (e) {
      _log.error(
        'bookmark $method failed',
        fields: {'folders': folders},
        error: e,
      );
      rethrow;
    }
  }
}

/// The bookmarks of macOS; null elsewhere, where a picked folder stays
/// readable.
final folderAccessProvider = Provider<FolderAccess?>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS
      ? const _Bookmarks()
      : null,
);

/// The library's folders the app can no longer read, while shown; asked anew
/// when they change, not as a scan writes its checkpoint after each directory.
final StreamProvider<List<String>> lostFoldersProvider =
    StreamProvider.autoDispose((ref) async* {
      final access = ref.watch(folderAccessProvider);
      if (access == null) {
        yield const [];
        return;
      }
      final db = await ref.watch(replicaProvider.future);
      await for (final roots
          in watchFolders(db)
              .map((folders) => [for (final f in folders) f.root])
              .distinct(listEquals)) {
        final lost = await access.lost(roots);
        yield [
          for (final root in roots)
            if (lost.contains(root)) root,
        ];
      }
    });

/// Asks the user to pick the folder [root] again, which gives the app back
/// its access, and keeps a new bookmark of it if they did.
Future<void> allowFolder(WidgetRef ref, String root) async {
  final picked = await ref
      .read(folderPickerProvider)
      ?.call(initialDirectory: root);
  _log.info('folder picked again', fields: {'folder': root, 'picked': ?picked});
  if (picked == root) {
    await ref.read(folderAccessProvider)?.keep(root);
    ref.invalidate(lostFoldersProvider);
  }
}

/// File System Access, with which Chromium on computers keeps folders
/// (docs/10-client-app.md §7.1); null in other browsers and outside browsers.
final browserFoldersProvider = Provider<BrowserFolders?>(
  (ref) => browserFolders,
);

/// Whether this is a browser that cannot keep folders, which it then says.
final foldersUnsupportedProvider = Provider<bool>(
  (ref) => kIsWeb && ref.watch(browserFoldersProvider) == null,
);

/// Whether this platform adds folders: desktops, and browsers with File
/// System Access; not while the store is shut (StoreBanner).
bool canAddFolders(WidgetRef ref) =>
    (ref.watch(folderPickerProvider) != null ||
        ref.watch(browserFoldersProvider) != null) &&
    !ref.watch(vaultProvider).hasError;

/// The library's folders with their state and item count while shown, anew
/// on a change to the library but at most once a second.
final StreamProvider<List<FolderSummaryResult>> foldersProvider =
    StreamProvider.autoDispose((ref) async* {
      yield* everySecond(
        (await ref.watch(replicaProvider.future)).folderSummary().watch(),
      );
    });

/// Adds the folder the user picks to the library, which scans it from then on.
Future<void> pickFolder(BuildContext context, WidgetRef ref) async {
  final pick = ref.read(folderPickerProvider);
  if (pick != null) {
    final root = await pick();
    _log.info('folder picked', fields: {'folder': ?root});
    if (root != null && context.mounted) {
      await addPickedFolder(context, ref, root);
    }
    return;
  }
  final browser = ref.read(browserFoldersProvider);
  if (browser == null) return;
  final added = await browser.pick(await ref.read(replicaProvider.future));
  if (context.mounted) _added(context, added);
}

/// Adds the folder [root], which the user picked or dropped on the window, to
/// the library; says so when it overlaps one of the library's.
Future<void> addPickedFolder(
  BuildContext context,
  WidgetRef ref,
  String root,
) async {
  final added = await addFolder(await ref.read(replicaProvider.future), root);
  if (added) await ref.read(folderAccessProvider)?.keep(root);
  if (context.mounted) _added(context, added);
}

void _added(BuildContext context, bool? added) {
  _log.info('folder added', fields: {'added': added});
  if (added == false) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).folderOverlaps)),
    );
  }
}

/// Removes the library's folder [root], with its items, once the user confirms.
Future<void> removeFolderOnceConfirmed(
  BuildContext context,
  WidgetRef ref,
  String root,
) async {
  final strings = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.folderRemove),
      content: Text(strings.folderRemoveBody(isolated(root))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(strings.folderRemoveConfirm),
        ),
      ],
    ),
  );
  if (confirmed ?? false) {
    _log.info('folder removed', fields: {'folder': root});
    await removeFolder(await ref.read(replicaProvider.future), root);
    await ref.read(folderAccessProvider)?.forget(root);
  }
}
