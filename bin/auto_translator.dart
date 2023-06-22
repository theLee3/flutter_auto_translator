import 'dart:io';

import 'package:auto_translator/auto_translator.dart';

void main(List<String> arguments) {
  const version = '1.1.0';
  stdout.writeln('auto_translator v$version');
  stdout.writeln('═════════════════════');
  runWithArguments(arguments);
}
