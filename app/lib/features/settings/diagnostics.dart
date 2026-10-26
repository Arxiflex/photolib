import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:photolib_data/photolib_data.dart' show libraryStatistics;

import '../../core/feature_flags.dart';
import '../../core/logging.dart';
import '../../core/providers.dart';
import '../../core/replica.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/tokens.dart';
import 'save_native.dart' if (dart.library.js_interop) 'save_web.dart';
import 'settings.dart';

/// The diagnostic bundle of docs/19 §5 (ADR-0115): a zip of the log kept
/// across restarts, `photolib.log`, and `info.json`. A release build's log is
/// redacted once more, as the bundle leaves the device in the clear.
Uint8List diagnosticBundle({
  required List<String> log,
  required Map<String, Object?> info,
  required bool release,
}) {
  final lines = [
    for (final line in log)
      release ? LogRecord.fromJson(line).redacted().toJson() : line,
  ];
  return ZipEncoder().encodeBytes(
    Archive()
      ..add(ArchiveFile.string('photolib.log', '${lines.join('\n')}\n'))
      ..add(
        ArchiveFile.string(
          'info.json',
          const JsonEncoder.withIndent('  ').convert(info),
        ),
      ),
  );
}

/// Saves a bundle named so through the platform's save or share dialog, or as
/// a download; false when the user cancelled.
final bundleSaverProvider = Provider((ref) => saveBundle);

class DiagnosticsPage extends ConsumerStatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  ConsumerState<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends ConsumerState<DiagnosticsPage> {
  var _level = LogLevel.debug;
  String? _logger;

  List<LogRecord> _shown(List<LogRecord> records) => [
    for (final r in records.reversed)
      if (r.level.index >= _level.index && (_logger ?? r.logger) == r.logger) r,
  ];

  Future<void> _copy() async {
    final strings = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(
        text: [
          for (final r in _shown(ref.read(memoryLogProvider).records).reversed)
            r.toJson(),
        ].join('\n'),
      ),
    );
    messenger.showSnackBar(SnackBar(content: Text(strings.diagnosticsCopied)));
  }

  Future<void> _export() async {
    final strings = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    List<String> log;
    try {
      log = await ref.read(logStoreProvider).lines();
    } on Object catch (e) {
      const Logger('photolib.app').warning('no stored log', error: e);
      log = [for (final r in ref.read(memoryLogProvider).records) r.toJson()];
    }
    final db = ref.read(replicaProvider).value;
    final settings = ref.read(settingsProvider);
    final flags = ref.read(featureFlagsProvider);
    final bytes = diagnosticBundle(
      log: log,
      info: {
        'environment': environment(),
        'settings': {
          'theme': settings.themeMode.name,
          'diagnostics': settings.diagnostics,
          'flags': [
            for (final flag in Flag.values)
              if (flags.isOn(flag)) flag.name,
          ],
        },
        'library': db == null ? null : await libraryStatistics(db),
      },
      release: ref.read(releaseBuildProvider),
    );
    final now = DateTime.now().toIso8601String().replaceAll(RegExp(r'\D'), '');
    final name = 'photolib-diagnostics-${now.substring(0, 14)}.zip';
    if (await ref.read(bundleSaverProvider)(name, bytes)) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.diagnosticsExported)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final tokens = AppTokens.of(context);
    final theme = Theme.of(context);
    final log = ref.watch(memoryLogProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.diagnosticsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_outlined),
            tooltip: strings.diagnosticsCopy,
            onPressed: _copy,
          ),
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: strings.diagnosticsExport,
            onPressed: _export,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: log,
        builder: (context, _) {
          final loggers = {for (final r in log.records) r.logger}.toList()
            ..sort();
          final shown = _shown(log.records);
          final style = theme.textTheme.bodySmall!.copyWith(
            fontFamily: 'monospace',
          );
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: tokens.md),
                child: Row(
                  spacing: tokens.md,
                  children: [
                    Tooltip(
                      message: strings.diagnosticsLevel,
                      child: DropdownButton<LogLevel>(
                        value: _level,
                        items: [
                          for (final level in LogLevel.values)
                            DropdownMenuItem(
                              value: level,
                              child: Text(level.name),
                            ),
                        ],
                        onChanged: (level) => setState(() => _level = level!),
                      ),
                    ),
                    Expanded(
                      child: Tooltip(
                        message: strings.diagnosticsLogger,
                        child: DropdownButton<String?>(
                          isExpanded: true,
                          value: loggers.contains(_logger) ? _logger : null,
                          items: [
                            DropdownMenuItem(
                              child: Text(strings.diagnosticsAllLoggers),
                            ),
                            for (final logger in loggers)
                              DropdownMenuItem(
                                value: logger,
                                child: Text(logger),
                              ),
                          ],
                          onChanged: (logger) =>
                              setState(() => _logger = logger),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: Text(strings.diagnosticsEmpty))
                    : SelectionArea(
                        child: ListView.builder(
                          padding: EdgeInsets.all(tokens.md),
                          itemCount: shown.length,
                          itemBuilder: (context, i) {
                            final r = shown[i];
                            return Text(
                              [
                                r.time.toLocal().toIso8601String().substring(
                                  11,
                                  23,
                                ),
                                r.level.name,
                                '${r.logger}:',
                                r.message,
                                if (r.fields.isNotEmpty) '${r.fields}',
                                if (r.error != null) '— ${r.error}',
                              ].join(' '),
                              style: r.level.index >= LogLevel.warning.index
                                  ? style.copyWith(
                                      color: theme.colorScheme.error,
                                    )
                                  : style,
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
