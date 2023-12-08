import 'dart:io';

import 'package:auto_translator/src/exceptions.dart';
import 'package:auto_translator/src/main.dart';
import 'package:auto_translator/src/transformer.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

void main() {
  group('exceptions', () {
    final testDir = join('.dart_tool', 'arb_translator', 'test');

    late String currentDirectory;
    void setCurrentDirectory(String path) {
      path = join(testDir, path);
      Directory(path).createSync(recursive: true);
      Directory.current = path;
    }

    setUp(() {
      currentDirectory = Directory.current.path;
      setCurrentDirectory('default');
    });

    tearDown(() {
      Directory.current.parent.parent.deleteSync(recursive: true);
      Directory.current = currentDirectory;
    });

    // Test ConfigNotFoundException
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

    // Test NoTargetsProvidedException
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

    // Test missing key file. A key file is required to use the Google Translation API
    test('missing key file', () async {
      File('l10n.yaml').writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en-US.arb
output-localization-file: app_localizations.dart

translator:
  targets:
    - es-ES
''');

      await expectLater(() async => await runWithArguments([]),
          throwsA(isA<GoogleTranslateException>()));
    });

    // Test InvalidFormatException
    test('invalid format', () async {
      File('l10n.yaml').writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en-US.arb
output-localization-file: app_localizations.dart

translator:
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
  });

  group('transform', () {
    test('transform', () {
      // Create the template file containing 4 values of varying complexity
      final arbTemplate = {
        "appTitle": "Demo App",
        "greeting": "Hello, {world}!",
        "birthday":
            "{sex, select, male{His birthday} female{Her birthday} other{Their birthday}}",
        "complexExample":
            "{mode, select, 0{Test with {variable_name_type1}} 1{Test with {variableNameType2}} 2{{oneMore_for_goodMeasure} at the start this time.} other{Test using the '{select placeholder'} as well: {mode}}}",
      };

      final transformedArb = <String, dynamic>{};
      final transformer = Transformer();
      for (final entry in arbTemplate.entries) {
        transformedArb[entry.key] = transformer.encode(entry.value);
      }
      final results = <String, String>{};
      for (final entry in transformedArb.entries) {
        final result = transformer.decode(entry.value);
        results[entry.key] =
            result.contains('[') ? transformer.decode(result) : result;
      }

      expect(results, arbTemplate);
    });
  });
}
