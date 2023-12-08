import 'dart:io';

import 'package:auto_translator/src/main.dart';

void main(List<String> arguments) {
  const version = '2.0.0';
  stdout.writeln('auto_translator v$version');
  stdout.writeln('═════════════════════');
  runWithArguments(arguments).then((_) => exit(0)).catchError((error) {
    stderr.writeln(error);
    exit(1);
  });
}
