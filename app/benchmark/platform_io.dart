import 'dart:io';

Future<void> report(String json) async {
  stdout.writeln('timeline-bench: $json');
  await stdout.flush();
  exit(0);
}
