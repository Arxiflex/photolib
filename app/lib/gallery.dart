import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/features/library/timeline/selection.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/ui/commands.dart';
import 'package:photolib/ui/media_grid.dart';
import 'package:photolib/ui/selection_bar.dart';
import 'package:photolib/ui/source_tree.dart';
import 'package:photolib/ui/swipe_to_dismiss.dart';
import 'package:photolib/ui/theme.dart';
import 'package:photolib/ui/tokens.dart';
import 'package:photolib_data/photolib_data.dart'
    show SourceKind, SourceNode, SourceVisibility;

/// The component gallery: every component and gesture of the design system on
/// one page, in either theme and any locale, pseudo-locales included. Run it
/// with `flutter run -t lib/gallery.dart`.
void main() => runApp(const GalleryApp());

class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key, this.themeMode = ThemeMode.system});

  final ThemeMode themeMode;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  late var _themeMode = widget.themeMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context).galleryTitle,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    highContrastTheme: appTheme(Brightness.light, highContrast: true),
    highContrastDarkTheme: appTheme(Brightness.dark, highContrast: true),
    themeMode: _themeMode,
    home: Builder(
      builder: (context) => _GalleryPage(
        onToggleTheme: () => setState(
          () => _themeMode = Theme.of(context).brightness == Brightness.dark
              ? ThemeMode.light
              : ThemeMode.dark,
        ),
      ),
    ),
  );
}

const _photos = 60;
const _levels = [1, 3, 5, 9];

SourceNode _folder(
  String key,
  int items, {
  List<SourceNode> children = const [],
  SourceVisibility own = SourceVisibility.inherit,
  bool shown = true,
}) => SourceNode(
  source: 'mediastore:external_primary',
  volume: 'external_primary',
  key: key,
  name: key.isEmpty ? '' : key.split('/').reversed.skip(1).first,
  kind: key.isEmpty ? SourceKind.volume : SourceKind.folder,
  items: items,
  itemsBelow: children.fold(items, (n, c) => n + c.itemsBelow),
  newest: 20240512,
  visibility: own,
  shown: shown,
  partly: !shown && children.any((c) => c.shown),
  appOwned: key.startsWith('Android/'),
  children: children,
);

/// A phone's folders: one hidden with one shown below it, and an app's.
final _sources = SourceNode(
  source: '',
  volume: '',
  key: '',
  name: '',
  kind: SourceKind.device,
  itemsBelow: 1452,
  visibility: SourceVisibility.shown,
  children: [
    _folder(
      '',
      0,
      children: [
        _folder('Android/', 0, children: [_folder('Android/media/', 120)]),
        _folder('DCIM/', 0, children: [_folder('DCIM/Camera/', 1200)]),
        _folder(
          'Pictures/',
          12,
          own: SourceVisibility.hidden,
          shown: false,
          children: [
            _folder('Pictures/Screenshots/', 120, own: SourceVisibility.shown),
          ],
        ),
      ],
    ),
  ],
);

class _GalleryPage extends StatefulWidget {
  const _GalleryPage({required this.onToggleTheme});

  final VoidCallback onToggleTheme;

  @override
  State<_GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPage> {
  final ValueNotifier<Selection> _selection = ValueNotifier(
    Selection.none.add(1, 3).add(4, 5),
  );
  var _columns = 5;
  var _chip = 0;

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  void _zoom(int by) =>
      setState(() => _columns = MediaGrid.step(_levels, _columns, by));

  Widget _photo(int i, {double size = 24}) => ColoredBox(
    color: i.isEven
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.tertiaryContainer,
    child: Icon(Icons.photo_outlined, size: size),
  );

  void _open(int i) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      pageBuilder: (context, _, _) => SwipeToDismiss(
        onDismissed: () => Navigator.pop(context),
        child: Stack(
          children: [
            Center(
              child: AspectRatio(aspectRatio: 1, child: _photo(i, size: 96)),
            ),
            const SafeArea(child: CloseButton()),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final actions = [
      (Icons.share_outlined, strings.actionShare),
      (Icons.favorite_border, strings.actionFavourite),
      (Icons.library_add_outlined, strings.actionAddToAlbum),
      (Icons.delete_outline, strings.actionTrash),
    ];
    Widget heading(String text) => Padding(
      padding: EdgeInsetsDirectional.only(top: tokens.lg, bottom: tokens.sm),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
    Widget wrap(List<Widget> children) =>
        Wrap(spacing: tokens.sm, runSpacing: tokens.sm, children: children);

    final zoom = [
      Command(
        strings.zoomOut,
        () => _zoom(1),
        shortcut: primary(LogicalKeyboardKey.minus),
        icon: Icons.zoom_out,
      ),
      Command(
        strings.zoomIn,
        () => _zoom(-1),
        shortcut: primary(LogicalKeyboardKey.equal),
        icon: Icons.zoom_in,
      ),
    ];

    return Commands(
      commands: zoom,
      child: Scaffold(
        appBar: AppBar(
          title: Text(strings.galleryTitle),
          actions: [
            IconButton(
              icon: Icon(dark ? Icons.light_mode : Icons.dark_mode),
              tooltip: dark ? strings.themeLight : strings.themeDark,
              onPressed: widget.onToggleTheme,
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.symmetric(horizontal: tokens.md),
          children: [
            heading(strings.galleryButtons),
            wrap([
              FilledButton.icon(
                onPressed: () {},
                icon: Icon(actions[0].$1),
                label: Text(actions[0].$2),
              ),
              FilledButton.tonal(onPressed: () {}, child: Text(actions[1].$2)),
              OutlinedButton(onPressed: () {}, child: Text(actions[2].$2)),
              TextButton(onPressed: () {}, child: Text(actions[3].$2)),
              IconButton.filled(
                onPressed: () {},
                icon: Icon(actions[1].$1),
                tooltip: actions[1].$2,
              ),
            ]),
            heading(strings.galleryChips),
            wrap([
              for (final (i, kind) in [
                strings.collectionAlbums,
                strings.collectionPeople,
                strings.collectionPlaces,
                strings.collectionTags,
              ].indexed)
                FilterChip(
                  label: Text(kind),
                  selected: _chip == i,
                  onSelected: (_) => setState(() => _chip = i),
                ),
            ]),
            heading(strings.galleryMenus),
            wrap([
              OutlinedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => ListView(
                    shrinkWrap: true,
                    children: [
                      for (final (icon, label) in actions)
                        ListTile(
                          leading: Icon(icon),
                          title: Text(label),
                          onTap: () => Navigator.pop(context),
                        ),
                    ],
                  ),
                ),
                child: Text(strings.galleryShowSheet),
              ),
              MenuAnchor(
                menuChildren: [
                  for (final (icon, label) in actions)
                    MenuItemButton(
                      leadingIcon: Icon(icon),
                      onPressed: () {},
                      child: Text(label),
                    ),
                ],
                builder: (context, menu, _) => IconButton(
                  icon: const Icon(Icons.more_vert),
                  tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                  onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                ),
              ),
            ]),
            Row(
              children: [
                Expanded(child: heading(strings.galleryGrid)),
                for (final command in zoom)
                  IconButton(
                    icon: Icon(command.icon),
                    tooltip: command.label,
                    onPressed: command.run,
                  ),
              ],
            ),
            ValueListenableBuilder(
              valueListenable: _selection,
              builder: (context, selected, _) => selected.isEmpty
                  ? const SizedBox.shrink()
                  : SelectionBar(
                      count: selected.count,
                      onClear: () => _selection.value = Selection.none,
                      onSelectAll: () =>
                          _selection.value = Selection.none.add(0, _photos),
                      onDownload: () {},
                      actions: [
                        for (final (icon, label) in actions.skip(1).take(1))
                          IconButton(
                            icon: Icon(icon),
                            tooltip: label,
                            onPressed: () {},
                          ),
                      ],
                    ),
            ),
            SizedBox(
              height: 400,
              child: MediaGrid(
                count: _photos,
                columns: _columns,
                levels: _levels,
                onColumns: (columns) => setState(() => _columns = columns),
                selection: _selection,
                onOpen: _open,
                itemBuilder: (context, i) => Semantics(
                  label: strings.photoPosition(i + 1, _photos),
                  child: _photo(i),
                ),
              ),
            ),
            heading(strings.settingsFolders),
            SizedBox(
              height: 480,
              child: SourceTree(
                root: _sources,
                onShow: (_, {required shown}) {},
                onAction: (_, _) {},
              ),
            ),
            SizedBox(height: tokens.md),
          ],
        ),
      ),
    );
  }
}
