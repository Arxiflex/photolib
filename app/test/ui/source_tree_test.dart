import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/l10n/app_localizations.dart';
import 'package:photolib/l10n/formats.dart';
import 'package:photolib/ui/source_tree.dart';
import 'package:photolib_data/photolib_data.dart';

/// A folder at [key] of [volume], holding [items] of its own.
SourceNode _folder(
  String key, {
  List<SourceNode> children = const [],
  int items = 1,
  bool shown = true,
  SourceVisibility own = SourceVisibility.inherit,
  bool partly = false,
  bool app = false,
  String volume = 'external_primary',
}) => SourceNode(
  source: 'mediastore:$volume',
  volume: volume,
  key: key,
  name: key.split('/').reversed.skip(1).first,
  kind: SourceKind.folder,
  items: items,
  itemsBelow: children.fold(items, (n, c) => n + c.itemsBelow),
  shown: shown,
  visibility: own,
  partly: partly,
  appOwned: app,
  children: children,
);

SourceNode _top(
  String source,
  SourceKind kind,
  List<SourceNode> children, {
  SourceState state = SourceState.present,
}) {
  final volume = source.substring(source.indexOf(':') + 1);
  return SourceNode(
    source: source,
    volume: volume,
    key: '',
    name: volume,
    kind: kind,
    itemsBelow: children.fold(0, (n, c) => n + c.itemsBelow),
    state: state,
    children: children,
  );
}

SourceNode _device(List<SourceNode> tops, {bool shown = true}) => SourceNode(
  source: '',
  volume: '',
  key: '',
  name: '',
  kind: SourceKind.device,
  itemsBelow: tops.fold(0, (n, c) => n + c.itemsBelow),
  shown: shown,
  visibility: shown ? SourceVisibility.shown : SourceVisibility.hidden,
  children: tops,
);

const _whatsApp = 'Android/media/com.whatsapp/WhatsApp/Media/';

/// Android: MediaStore's volumes and buckets, and the folders above them.
final SourceNode android = _device([
  _top('mediastore:external_primary', SourceKind.volume, [
    _folder(
      'Android/',
      items: 0,
      app: true,
      children: [
        _folder(
          'Android/media/',
          items: 0,
          app: true,
          children: [
            _folder(
              'Android/media/com.whatsapp/',
              items: 0,
              app: true,
              shown: false,
              own: SourceVisibility.hidden,
              partly: true,
              children: [
                _folder(
                  '${_whatsApp}WhatsApp Images/',
                  items: 40,
                  app: true,
                  own: SourceVisibility.shown,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    _folder('DCIM/', items: 0, children: [_folder('DCIM/Camera/', items: 312)]),
    _folder(
      'Pictures/',
      items: 0,
      children: [
        _folder(
          'Pictures/Screenshots/',
          items: 9,
          shown: false,
          own: SourceVisibility.hidden,
        ),
      ],
    ),
  ]),
  _top('mediastore:0000-0000', SourceKind.volume, [
    _folder('DCIM/', items: 0, children: [_folder('DCIM/Camera/', items: 7)]),
  ]),
]);

const _pictures = '/home/me/Pictures';

/// A desktop: roots the user added and the folders the index found in them.
final SourceNode desktop = _device([
  _top('folder:/home/me/Pictures', SourceKind.root, [
    _folder(
      '2024/',
      items: 0,
      volume: _pictures,
      children: [
        _folder(
          '2024/May/',
          volume: _pictures,
          children: [_folder('2024/May/Party/', items: 5, volume: _pictures)],
        ),
      ],
    ),
  ]),
  _top(
    'folder:/media/me/Drive',
    SourceKind.root,
    [],
    state: SourceState.offline,
  ),
]);

/// Chromium: folders kept with File System Access.
final SourceNode chromium = _device([
  _top('fsa:Photos', SourceKind.root, [
    _folder('Trip/', items: 3, volume: 'Photos'),
  ]),
  _top('fsa:Away', SourceKind.root, [], state: SourceState.lost),
]);

void main() {
  final eyes = <String>[];
  final actions = <String>[];
  setUp(() {
    eyes.clear();
    actions.clear();
  });

  Future<void> pump(
    WidgetTester tester,
    SourceNode root, {
    Size size = const Size(400, 800),
    void Function(SourceNode node)? onPick,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SourceTree(
            root: root,
            onPick: onPick,
            onShow: (node, {required shown}) => eyes.add(
              '${shown ? 'show' : 'hide'} ${node.volume}:${node.key}',
            ),
            onAction: (node, action) =>
                actions.add('${action.name} ${node.volume}:${node.key}'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The rows on show, each its name indented by its depth.
  List<String> rows(WidgetTester tester) => [
    for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
      _indented(tile),
  ];

  testWidgets('one widget renders Android, desktop and Chromium sources as '
      'nested trees: volumes and roots open, folders closed with their '
      'counts', (tester) async {
    await pump(tester, android);
    expect(rows(tester), [
      'This device',
      ' Internal storage',
      '  Android',
      '  DCIM',
      '  Pictures',
      ' SD card',
      '  DCIM',
    ]);
    expect(find.text('40 items'), findsOneWidget, reason: "Android's count");
    await tester.tap(find.byTooltip('Expand').at(1));
    await tester.pumpAndSettle();
    expect(rows(tester).sublist(3, 5), ['  DCIM', '   Camera']);
    expect(find.text('312 items'), findsNWidgets(2));

    await pump(tester, desktop);
    expect(rows(tester), [
      'This device',
      ' ${isolated('/home/me/Pictures')}',
      '  2024',
      ' ${isolated('/media/me/Drive')}',
    ]);
    expect(find.text('Offline, 0 items'), findsOneWidget);

    await pump(tester, chromium);
    expect(rows(tester), [
      'This device',
      ' ${isolated('Photos')}',
      '  Trip',
      ' ${isolated('Away')}',
    ]);
    expect(find.text('No access'), findsOneWidget);
  });

  testWidgets('a root shows its folder off only while its files cannot be '
      'read: a scanning root is read', (tester) async {
    const states = {
      SourceState.present: Icons.folder_special_outlined,
      SourceState.scanning: Icons.folder_special_outlined,
      SourceState.offline: Icons.folder_off_outlined,
      SourceState.lost: Icons.folder_off_outlined,
    };
    await pump(
      tester,
      _device([
        for (final state in states.keys)
          _top('folder:/${state.name}', SourceKind.root, [], state: state),
      ]),
    );
    for (final MapEntry(key: state, value: icon) in states.entries) {
      final row = find.widgetWithText(ListTile, isolated('/${state.name}'));
      expect(
        find.descendant(of: row, matching: find.byIcon(icon)),
        findsOneWidget,
        reason: state.name,
      );
    }
  });

  testWidgets('siblings line up whether they open or not, at the compact '
      'density of desktops and browsers', (tester) async {
    await pump(
      tester,
      _device([
        _top('mediastore:external_primary', SourceKind.volume, [
          _folder('Open/', children: [_folder('Open/In/')]),
          _folder('Leaf/'),
        ]),
      ]),
    );
    expect(
      tester.getTopLeft(find.text('Leaf')).dx,
      tester.getTopLeft(find.text('Open')).dx,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('every node has an eye: shown, hidden, or partly shown under a '
      'hidden node with a shown one below, faint when it inherits; a tap '
      'asks for the opposite, and a hidden subtree stays, dimmed', (
    tester,
  ) async {
    await pump(tester, android);
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Expand').first);
      await tester.pumpAndSettle();
    }
    Icon eye(String name) => tester.widget<Icon>(
      find.descendant(
        of: find.ancestor(
          of: find.byTooltip(RegExp('^(Show|Hide) $name\$')),
          matching: find.byType(IconButton),
        ),
        matching: find.byType(Icon),
      ),
    );
    final scheme = Theme.of(tester.element(find.byType(SourceTree)))
        .colorScheme;
    expect(
      (eye('com.whatsapp').icon, eye('com.whatsapp').color),
      (Icons.visibility_off_outlined, null),
      reason: 'partly shown, its own',
    );
    expect(
      (eye('WhatsApp Images').icon, eye('WhatsApp Images').color),
      (Icons.visibility, null),
    );
    expect(
      (eye('media').icon, eye('media').color),
      (Icons.visibility, scheme.outline),
      reason: 'inherited',
    );
    expect(find.text('40 items · Partly shown'), findsOneWidget);
    final dimmed = tester.widget<Text>(find.text('com.whatsapp'));
    expect(dimmed.style?.color, scheme.onSurfaceVariant);
    expect(tester.widget<Text>(find.text('media')).style?.color, isNull);

    await tester.tap(find.byTooltip('Show com.whatsapp'));
    await tester.tap(find.byTooltip('Hide media'));
    await tester.tap(find.byTooltip('Hide This device'));
    expect(eyes, [
      'show external_primary:Android/media/com.whatsapp/',
      'hide external_primary:Android/media/',
      'hide :',
    ]);
  });

  testWidgets('a long press or a right click offers Show only this, Show '
      'everything here and Hide everything else here; the device only '
      'Show everything here', (tester) async {
    await pump(tester, android);
    await tester.longPress(find.text('DCIM').first);
    await tester.pumpAndSettle();
    expect(find.text('Show only this'), findsOneWidget);
    expect(find.text('Hide everything else here'), findsOneWidget);
    await tester.tap(find.text('Show everything here'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pictures'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide everything else here'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SD card'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show only this'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('This device'));
    await tester.pumpAndSettle();
    expect(find.text('Show only this'), findsNothing);
    await tester.tap(find.text('Show everything here'));
    await tester.pumpAndSettle();
    expect(actions, [
      'showEverything external_primary:DCIM/',
      'hideOthers external_primary:Pictures/',
      'showOnly 0000-0000:',
      'showEverything :',
    ]);
  });

  testWidgets('arrows move and open, space flips the eye, Enter picks, and '
      'typing jumps to a name', (tester) async {
    final picked = <String>[];
    await pump(
      tester,
      android,
      onPick: (n) => picked.add('${n.volume}:${n.key}'),
    );
    await tester.tap(find.text('This device'));
    await tester.pump();
    picked.clear();
    String focused() =>
        (tester
                    .widget<ListTile>(
                      find.byWidgetPredicate(
                        (w) => w is ListTile && w.selected,
                      ),
                    )
                    .title!
                as Text)
            .data!;
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.arrowDown);
    expect(focused(), 'Android');
    await press(LogicalKeyboardKey.arrowRight);
    expect(rows(tester)[3], '   media', reason: 'opened');
    await press(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'media');
    await press(LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'Android', reason: 'to the node above');
    await press(LogicalKeyboardKey.arrowLeft);
    expect(rows(tester)[3], '  DCIM', reason: 'closed');
    await press(LogicalKeyboardKey.space);
    expect(eyes, ['hide external_primary:Android/']);

    await press(LogicalKeyboardKey.keyP);
    expect(focused(), 'Pictures');
    await press(LogicalKeyboardKey.keyD);
    expect(focused(), 'Pictures', reason: 'no name starts with pd');
    await tester.pump(const Duration(seconds: 1));
    await press(LogicalKeyboardKey.keyD);
    expect(focused(), 'DCIM', reason: 'the next starting with d');
    await press(LogicalKeyboardKey.arrowUp);
    await press(LogicalKeyboardKey.enter);
    expect(picked, ['0000-0000:']);
  });

  testWidgets('a search keeps the nodes above what it finds', (tester) async {
    await pump(tester, android);
    await tester.enterText(find.byType(TextField), 'camera');
    await tester.pumpAndSettle();
    expect(rows(tester), [
      'This device',
      ' Internal storage',
      '  DCIM',
      '   Camera',
      ' SD card',
      '  DCIM',
      '   Camera',
    ]);
    expect(
      find.byTooltip('Collapse'),
      findsNWidgets(5),
      reason: 'every node with what was found below it shows it open',
    );
    await tester.enterText(find.byType(TextField), 'nothing like it');
    await tester.pumpAndSettle();
    expect(rows(tester), isEmpty);
  });

  testWidgets('on a wide window the node in focus shows beside the tree, its '
      'menu as buttons', (tester) async {
    await pump(tester, desktop, size: const Size(1280, 800));
    await tester.tap(find.text('2024'));
    await tester.pumpAndSettle();
    expect(find.text('2024'), findsNWidgets(2));
    expect(find.text('1 item · \u20662024\u2069'), findsNothing);
    await tester.tap(
      find.widgetWithText(TextButton, 'Hide everything else here'),
    );
    expect(actions, ['hideOthers /home/me/Pictures:2024/']);

    await tester.tap(
      find.text(isolated('/media/me/Drive')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(
      find.text(isolated('/media/me/Drive')),
      findsNWidgets(2),
      reason: 'a right click focuses what it opens the menu of',
    );
    expect(find.byType(PopupMenuItem<SourceAction>), findsNWidgets(3));
  });

  testWidgets('5,000 folders on 3 volumes, 6 deep, build only the rows on '
      'screen as they scroll', (tester) async {
    var n = 0;
    SourceNode level(String volume, String key, int depth) => _folder(
      key,
      volume: volume,
      children: [
        if (depth < 6)
          for (var i = 0; i < (depth == 1 ? 13 : 2) && n < 5000; i++)
            if (++n > 0) level(volume, '${key}f$n/', depth + 1),
      ],
    );
    final root = _device([
      for (final v in ['external_primary', '1111-2222', '3333-4444'])
        _top('mediastore:$v', SourceKind.volume, [
          for (var i = 0; i < 9 && n < 5000; i++)
            if (++n > 0) level(v, 'f$n/', 1),
        ]),
    ]);
    expect(flatten(root).length, greaterThan(5000));
    await pump(tester, root);
    await tester.enterText(find.byType(TextField), 'f');
    await tester.pumpAndSettle();
    final list = tester.state<ScrollableState>(find.byType(Scrollable).last);
    var most = 0;
    var frames = 0;
    while (list.position.pixels < list.position.maxScrollExtent) {
      list.position.jumpTo(
        min(list.position.pixels + 800, list.position.maxScrollExtent),
      );
      await tester.pump();
      frames++;
      most = max(most, find.byType(ListTile).evaluate().length);
    }
    expect(frames, greaterThan(300), reason: 'every folder is a row');
    expect(most, inInclusiveRange(1, 20));
    expect(find.text('f5000'), findsOneWidget, reason: 'the last row');
  });
}

/// The name of [tile], a row of the source tree, indented by its depth.
String _indented(ListTile tile) {
  final depth = (tile.contentPadding! as EdgeInsetsDirectional).start ~/ 16;
  return '${' ' * depth}${(tile.title! as Text).data}';
}
