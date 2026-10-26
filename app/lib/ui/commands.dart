import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';

/// A user action, reachable by its shortcut, the shortcut sheet and the
/// command palette (DSK-04).
@immutable
class Command {
  const Command(this.label, this.run, {this.shortcut, this.icon, this.on});

  final String label;
  final VoidCallback run;
  final ShortcutActivator? shortcut;
  final IconData? icon;

  /// Whether what it toggles is on, for a command that toggles a mode.
  final bool? on;
}

bool get _apple => const {
  TargetPlatform.iOS,
  TargetPlatform.macOS,
}.contains(defaultTargetPlatform);

/// [key] with the platform's primary modifier: Cmd on Apple systems, else Ctrl.
SingleActivator primary(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(key, control: !_apple, meta: _apple, shift: shift);

/// Control, Alt, Shift, Meta and the key of [activator].
(bool, bool, bool, bool, String) _keys(ShortcutActivator activator) =>
    switch (activator) {
      SingleActivator a => (
        a.control,
        a.alt,
        a.shift,
        a.meta,
        a.trigger.keyLabel,
      ),
      CharacterActivator a => (a.control, a.alt, false, a.meta, a.character),
      _ => throw ArgumentError.value(activator),
    };

/// How the shortcut sheet shows [activator], as `Ctrl+Shift+Z`.
String keysLabel(ShortcutActivator activator, AppLocalizations strings) {
  final (control, alt, shift, meta, key) = _keys(activator);
  return [
    if (control) strings.keyControl,
    if (alt) strings.keyAlt,
    if (shift) strings.keyShift,
    if (meta) strings.keyMeta,
    key,
  ].join('+');
}

/// Runs [commands] on their shortcuts from anywhere below it; `?` shows the
/// shortcut sheet and Ctrl/Cmd+K the command palette. While a text field has
/// focus, only shortcuts with Ctrl, Cmd or Alt run, so typing stays typing.
class Commands extends StatelessWidget {
  const Commands({super.key, required this.commands, required this.child});

  final List<Command> commands;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    late final List<Command> all;
    final sheet = Command(
      strings.shortcutsTitle,
      () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.shortcutsTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final command in all)
                  if (command.shortcut case final shortcut?)
                    ListTile(
                      title: Text(command.label),
                      trailing: Text(keysLabel(shortcut, strings)),
                    ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(MaterialLocalizations.of(context).closeButtonLabel),
            ),
          ],
        ),
      ),
      shortcut: const CharacterActivator('?'),
      icon: Icons.keyboard_outlined,
    );
    all = [
      ...commands,
      sheet,
      Command(
        strings.commandPalette,
        () => showDialog<void>(
          context: context,
          builder: (_) => _Palette([...commands, sheet]),
        ),
        shortcut: primary(LogicalKeyboardKey.keyK),
      ),
    ];
    assert(() {
      final keys = [
        for (final c in all)
          if (c.shortcut case final shortcut?) _keys(shortcut),
      ];
      return keys.toSet().length == keys.length;
    }(), 'two commands share a shortcut, which only the first would run');

    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        final typing =
            FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<EditableText>() !=
            null;
        for (final command in all) {
          final shortcut = command.shortcut;
          if (shortcut == null ||
              !shortcut.accepts(event, HardwareKeyboard.instance)) {
            continue;
          }
          final (control, alt, _, meta, _) = _keys(shortcut);
          if (typing && !(control || alt || meta)) {
            return KeyEventResult.ignored;
          }
          command.run();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

class _Palette extends StatefulWidget {
  const _Palette(this.commands);

  final List<Command> commands;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  var _query = '';

  List<Command> get _matches => [
    for (final command in widget.commands)
      if (command.label.toLowerCase().contains(_query.toLowerCase())) command,
  ];

  void _run(Command command) {
    Navigator.pop(context);
    command.run();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Dialog(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: strings.commandPaletteHint,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (query) => setState(() => _query = query),
              onSubmitted: (_) {
                if (_matches.firstOrNull case final first?) _run(first);
              },
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final command in _matches)
                    ListTile(
                      leading: Icon(command.icon),
                      title: Text(command.label),
                      trailing: switch (command.shortcut) {
                        final shortcut? => Text(keysLabel(shortcut, strings)),
                        null => null,
                      },
                      onTap: () => _run(command),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
