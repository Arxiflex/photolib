import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib/core/keystore.dart';
import 'package:photolib/l10n/app_localizations.dart';

/// Shows each passphrase the keystore asks for over [child], a dialog that
/// only an answer closes (ADR-0154).
class PassphraseGate extends ConsumerStatefulWidget {
  /// The prompts over [child].
  const new({required this.child, super.key});

  /// The page under the prompts.
  final Widget child;

  @override
  ConsumerState<PassphraseGate> createState() => _PassphraseGateState();
}

class _PassphraseGateState extends ConsumerState<PassphraseGate> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(passphrasePromptProvider, (_, prompt) {
      if (prompt == null) return;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _PassphraseDialog(prompt),
        ),
      );
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PassphraseDialog extends StatefulWidget {
  const new(this.prompt);

  final PassphrasePrompt prompt;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _passphrase = TextEditingController();
  final _repeat = TextEditingController();
  late String? _error = widget.prompt.retry
      ? AppLocalizations.of(context).passphraseWrong
      : null;

  @override
  void dispose() {
    _passphrase.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    final strings = AppLocalizations.of(context);
    final passphrase = _passphrase.text;
    final error = switch (widget.prompt.create) {
      // docs/21 §7: without hardware binding, at least 10 characters.
      true when passphrase.characters.length < 10 => strings.passphraseTooShort,
      true when _repeat.text != passphrase => strings.passphraseMismatch,
      false when passphrase.isEmpty => strings.passphraseWrong,
      _ => null,
    };
    if (error != null) return setState(() => _error = error);
    Navigator.pop(context);
    widget.prompt.answer.complete(passphrase);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final create = widget.prompt.create;
    return AlertDialog(
      title: Text(strings.appTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(create ? strings.passphraseCreate : strings.passphraseUnlock),
            TextField(
              controller: _passphrase,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                labelText: strings.passphraseLabel,
                errorText: _error,
              ),
              onSubmitted: create ? null : (_) => _submit(),
            ),
            if (create)
              TextField(
                controller: _repeat,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: strings.passphraseRepeat,
                ),
                onSubmitted: (_) => _submit(),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _submit,
          child: Text(MaterialLocalizations.of(context).continueButtonLabel),
        ),
      ],
    );
  }
}
