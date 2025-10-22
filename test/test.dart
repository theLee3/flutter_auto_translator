import 'dart:io';
import 'package:test/test.dart';
import 'package:auto_translator/src/exceptions.dart';
import 'package:auto_translator/src/main.dart';
import 'package:auto_translator/src/transformer.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('auto_translator_test_');
    Directory.current = tempDir;
  });

  tearDown(() {
    Directory.current = Directory.systemTemp;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('config:', () {
    test('missing config file', () async {
      await expectLater(() async => await runWithArguments([]),
          throwsA(isA<ConfigNotFoundException>()));
    });

    test('missing translator config in l10n.yaml', () async {
      File('l10n.yaml').writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en-US.arb
output-localization-file: app_localizations.dart
''');
      await expectLater(() async => await runWithArguments([]),
          throwsA(isA<ConfigNotFoundException>()));
    });

    test('no targets', () async {
      File('l10n.yaml').writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en-US.arb
output-localization-file: app_localizations.dart
translator:
  targets:
''');
      await expectLater(() async => await runWithArguments([]),
          throwsA(isA<NoTargetsProvidedException>()));
    });
  });

  group('keys:', () {
    test('missing key file', () async {
      File('l10n.yaml').writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en-US.arb
output-localization-file: app_localizations.dart
translator:
  key_file: path/to/key/file
  targets:
    - es-ES
''');

      await expectLater(() async => await runWithArguments([]),
          throwsA(isA<MissingTranslatorKeyException>()));
    });

    test('invalid key file format', () async {
      File('l10n.yaml').writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en-US.arb
output-localization-file: app_localizations.dart
translator:
  targets:
    - es-ES
''');

      File('translator_keys').writeAsStringSync('{s0meArb1tr4ryK3yV4lu3:}');

      await expectLater(() async => await runWithArguments([]),
          throwsA(isA<MalformedTranslatorKeyFileException>()));
    });

    test('missing key in key file', () async {
      File('l10n.yaml').writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en-US.arb
output-localization-file: app_localizations.dart
translator:
  targets:
    - es-ES
''');

      File('translator_keys')
          .writeAsStringSync('{"deepL": "s0meArb1tr4ryK3yV4lu3"}');

      await expectLater(() async => await runWithArguments([]),
          throwsA(isA<MissingTranslatorKeyException>()));
    });
  });

  group('arb:', () {
    test('invalid format', () async {
      File('l10n.yaml').writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en-US.arb
output-localization-file: app_localizations.dart
translator:
  key_file: translator_key
  targets:
    - es-ES
''');
      File('translator_key').writeAsStringSync('s0meArb1tr4ryK3yV4lu3');

      File('lib/l10n/app_en-US.arb')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
{
  "invalid": "{This string {breaks}"
}
''');

      await expectLater(() async => await runWithArguments([]),
          throwsA(isA<InvalidFormatException>()));
    });

    test('transform', () {
      final arbTemplate = {
        'appTitle': 'Demo App',
        'greeting': 'Hello, {world}!',
        'birthday':
            '{sex, select, male{His birthday} female{Her birthday} other{Their birthday}}',
        'complexExample':
            "{mode, select, 0{Test with {variable_name_type1}} 1{Test with {variableNameType2}} 2{{oneMore_for_goodMeasure} at the start this time.} other{Test using the '{select placeholder'} as well: {mode}}}",
      };

      final transformedArb = <String, dynamic>{};
      final transformer = Transformer();
      for (final entry in arbTemplate.entries) {
        transformedArb[entry.key] = transformer.encode(entry.value);
      }
    });
  });
}
