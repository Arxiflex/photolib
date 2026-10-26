import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/folders/file_ops.dart';
import 'package:photolib/features/folders/folders.dart';
import 'package:photolib/features/folders/rename.dart';
import 'package:photolib/features/folders/sorting.dart';
import 'package:photolib/features/folders/views.dart';
import 'package:photolib/features/search/search.dart';
import 'package:photolib/features/trash/trash.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/formats.dart';
import 'package:photolib_data/photolib_data.dart';

/// The path of the desktop folder file [a].
String pathOf(LocalAssetData a) => itemOf(a).uri.toFilePath();

void _say(BuildContext context, String text, [SnackBarAction? action]) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text), action: action));

/// Asks for a name under [title]: null when the user cancels.
Future<String?> nameDialog(BuildContext context, String title) =>
    showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(title),
    );

class _NameDialog extends StatefulWidget {
  const new(this.title);

  final String title;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _text.text.trim();
    void done() => Navigator.pop(context, name);
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        autofocus: true,
        decoration: InputDecoration(
          labelText: AppLocalizations.of(context).nameLabel,
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: name.isEmpty ? null : (_) => done(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: name.isEmpty ? null : done,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

/// Asks before moving the items [ids] of the folder [name] to the trash,
/// saying how many there are and that they leave this device only, as one
/// request the snack bar undoes.
Future<void> deleteFolder(
  BuildContext context,
  WidgetRef ref,
  String name,
  List<Uint8List> ids,
) async {
  final strings = AppLocalizations.of(context);
  final sure = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(strings.folderDelete),
      content: Text(
        [
          strings.folderDeleteBody(name),
          strings.folderItems(ids.length),
          // The library keeps what was backed up (ADR-0267).
          strings.deleteTrashWhere('device'),
        ].join('\n'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(strings.actionTrash),
        ),
      ],
    ),
  );
  if (sure == true && context.mounted) await moveToTrash(context, ref, ids);
}

/// Renames [items], files of one folder, by a pattern whose preview shows
/// every new name and why one cannot be given; the rename can be undone.
Future<void> renameDialog(
  BuildContext context,
  List<LocalAssetData> items,
) async {
  final dir = parentOf(pathOf(items.first));
  final own = {for (final a in items) nameOf(a)};
  final others = {
    await for (final e in Directory(dir).list())
      if (!own.contains(baseName(e.path))) baseName(e.path),
  };
  if (!context.mounted) return;
  final renames = await showDialog<List<(String, String)>>(
    context: context,
    builder: (context) => _RenameDialog(items, others),
  );
  if (renames == null || !context.mounted) return;
  final strings = AppLocalizations.of(context);
  final done = await renameFiles([
    for (final (from, to) in renames) (joinPath(dir, from), joinPath(dir, to)),
  ]);
  if (!context.mounted) return;
  final renamed = [
    for (final r in done)
      if (r.target case final target?) (target, r.source),
  ];
  final failed = done.length - renamed.length;
  _say(
    context,
    failed > 0 ? strings.filesFailed(failed) : strings.renamed(renamed.length),
    SnackBarAction(
      label: strings.undo,
      onPressed: () => unawaited(renameFiles(renamed)),
    ),
  );
}

class _RenameDialog extends StatefulWidget {
  const new(this.items, this.others);

  final List<LocalAssetData> items;
  final Set<String> others;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  // i18n-ok: the pattern's token, as typed
  final _template = TextEditingController(text: '{name}');
  final _find = TextEditingController();
  final _replace = TextEditingController();

  @override
  void dispose() {
    for (final c in [_template, _find, _replace]) {
      c.dispose();
    }
    super.dispose();
  }

  List<PlannedName> _plan() => planRename(
    [for (final a in widget.items) (name: nameOf(a), taken: takenAt(a))],
    RenamePattern(
      template: _template.text,
      find: _find.text,
      replace: _replace.text,
    ),
    others: widget.others,
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final plan = _plan();
    Widget field(TextEditingController c, String label) => TextField(
      controller: c,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
    );
    return AlertDialog(
      title: Text(strings.actionRename),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field(_template, strings.renamePattern),
            Wrap(
              spacing: 4,
              children: [
                // i18n-ok: the pattern's tokens are syntax, as typed
                for (final token in ['{name}', '{nnn}', '{yyyy}-{MM}-{dd}'])
                  ActionChip(
                    label: Text(token),
                    onPressed: () => setState(() => _template.text += token),
                  ),
              ],
            ),
            field(_find, strings.renameFind),
            field(_replace, strings.renameReplace),
            const SizedBox(height: 8),
            Flexible(child: _Preview(widget.items, plan)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        TextButton(
          onPressed: isRenamable(plan)
              ? () => Navigator.pop(context, [
                  for (final (i, p) in plan.indexed)
                    if (p.name case final name?)
                      (nameOf(widget.items[i]), name),
                ])
              : null,
          child: Text(strings.actionRename),
        ),
      ],
    );
  }
}

/// Every file's name and its new one, or why it cannot have it.
class _Preview extends StatelessWidget {
  const new(this.items, this.plan);

  final List<LocalAssetData> items;
  final List<PlannedName> plan;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final error = Theme.of(context).colorScheme.error;
    return ListView.builder(
      shrinkWrap: true,
      itemCount: plan.length,
      itemBuilder: (context, i) {
        final (:name, :problem) = plan[i];
        return ListTile(
          dense: true,
          title: Text(nameOf(items[i])),
          subtitle: Text(
            problem != null
                ? '${name ?? ''}\n${strings.renameProblem(problem.name)}'
                : name ?? nameOf(items[i]),
            style: problem == null ? null : TextStyle(color: error),
          ),
        );
      },
    );
  }
}

/// Moves or copies the files [paths] into a folder the user chooses, starting
/// in [from], with each file's progress, a cancel, each file's outcome and an
/// undo.
Future<void> transferDialog(
  BuildContext context,
  WidgetRef ref,
  List<String> paths, {
  required String from,
  required bool move,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _TransferDialog(paths, from, move: move),
);

class _TransferDialog extends ConsumerStatefulWidget {
  const new(this.paths, this.from, {required this.move});

  final List<String> paths;
  final String from;
  final bool move;

  @override
  ConsumerState<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<_TransferDialog> {
  late String _dir = widget.from;
  String? _opening;
  List<String> _subfolders = [];
  Transfer? _transfer;
  var _running = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open(_dir));
  }

  @override
  void dispose() {
    _transfer?.dispose();
    super.dispose();
  }

  // Shows [dir] once listed, unless another folder was opened meanwhile.
  Future<void> _open(String dir) async {
    _opening = dir;
    final subfolders = [
      await for (final e in Directory(dir).list())
        if (e is Directory && !baseName(e.path).startsWith('.')) e.path,
    ]..sort(naturalCompare);
    if (mounted && _opening == dir) {
      setState(() {
        _dir = dir;
        _subfolders = subfolders;
      });
    }
  }

  Future<void> _newFolder() async {
    final strings = AppLocalizations.of(context);
    final name = await nameDialog(context, strings.folderNew);
    if (name == null) return;
    final problem = await createFolder(_dir, name);
    if (!mounted) return;
    if (problem != null) {
      _say(context, strings.transferProblem(problem));
      return;
    }
    await _open(joinPath(_dir, name));
  }

  Future<void> _start() async {
    final transfer = _transfer = Transfer(widget.paths, _dir, move: widget.move)
      ..addListener(() => setState(() {}));
    setState(() => _running = true);
    await transfer.run();
    if (transfer.files.any((f) => f.target != null)) {
      ref.read(folderViewsProvider.notifier).addRecent(_dir);
    }
    if (mounted) setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final transfer = _transfer;
    return AlertDialog(
      title: Text(widget.move ? strings.actionMoveTo : strings.actionCopyTo),
      content: SizedBox(
        width: 480,
        child: transfer == null ? _chooser() : _Progress(transfer),
      ),
      actions: [
        if (transfer == null) ...[
          TextButton(onPressed: _newFolder, child: Text(strings.folderNew)),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(material.cancelButtonLabel),
          ),
          FilledButton(
            onPressed: _dir == widget.from ? null : _start,
            child: Text(strings.transferHere('${widget.move}')),
          ),
        ] else if (_running)
          TextButton(
            onPressed: transfer.cancel,
            child: Text(material.cancelButtonLabel),
          )
        else ...[
          if (transfer.files.any((f) => f.target != null))
            TextButton(
              onPressed: () async {
                await transfer.undo();
                if (context.mounted) Navigator.pop(context);
              },
              child: Text(strings.undo),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(material.closeButtonLabel),
          ),
        ],
      ],
    );
  }

  Widget _chooser() {
    final strings = AppLocalizations.of(context);
    final roots = [
      for (final f
          in ref.watch(foldersProvider).value ?? <FolderSummaryResult>[])
        f.root,
    ];
    final recent = ref.watch(folderViewsProvider).recent;
    Widget place(String dir, IconData icon, [String? name]) => ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(name ?? isolated(dir)),
      selected: dir == _dir,
      onTap: () => _open(dir),
    );
    return ListView(
      shrinkWrap: true,
      children: [
        ListTile(
          leading: roots.contains(_dir)
              ? const Icon(Icons.folder_open)
              : IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => _open(parentOf(_dir)),
                ),
          title: Text(isolated(_dir)),
        ),
        for (final dir in _subfolders)
          place(dir, Icons.folder_outlined, baseName(dir)),
        if (recent.isNotEmpty) ListTile(title: Text(strings.transferRecent)),
        for (final dir in recent) place(dir, Icons.history),
        ListTile(title: Text(strings.settingsFolders)),
        for (final root in roots) place(root, Icons.storage_outlined),
      ],
    );
  }
}

const _known = {'exists', 'changed', 'cancelled'};

/// Each file of [transfer] with its progress, then its outcome.
class _Progress extends StatelessWidget {
  const new(this.transfer);

  final Transfer transfer;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final error = Theme.of(context).colorScheme.error;
    return ListView(
      shrinkWrap: true,
      children: [
        for (final f in transfer.files)
          ListTile(
            dense: true,
            leading: f.target != null
                ? const Icon(Icons.check)
                : f.error != null
                ? Icon(Icons.error_outline, color: error)
                : null,
            title: Text(baseName(f.source)),
            subtitle: switch (f.error) {
              final reason? => Text(
                _known.contains(reason)
                    ? strings.transferProblem(reason)
                    : '${strings.transferProblem(reason)}: $reason',
              ),
              null when f.target == null => LinearProgressIndicator(
                value: f.done,
              ),
              null => null,
            },
          ),
      ],
    );
  }
}
