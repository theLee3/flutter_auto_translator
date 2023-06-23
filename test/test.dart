import 'dart:convert';
import 'dart:io';

import 'package:auto_translator/auto_translator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/annotations.dart';
import 'package:path/path.dart';
import 'package:test/test.dart';

@GenerateMocks([http.Client])
void main() {
  group('config', () {
    final testDir = join('.dart_tool', 'arb_translator', 'test');

    late String currentDirectory;
    void setCurrentDirectory(String path) {
      path = join(testDir, path);
      Directory(path).createSync(recursive: true);
      Directory.current = path;
    }

    setUp(() {
      currentDirectory = Directory.current.path;
    });

    tearDown(() {
      Directory.current = currentDirectory;
    });

    // Test with default key file location & preferred languages
    test('default', () {
      setCurrentDirectory('default');
      File('l10n.yaml').writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en-US.arb
output-localization-file: app_localizations.dart

translator:
  targets:
    - es-ES
    - ja
  prefer-lang-templates: {
    'fr': 'es-ES',
    'ja': 'en-US'
  }
''');
      File('translator_key').writeAsStringSync('s0meArb1tr4ryK3yV4lu3');
      expect(config, isNotNull);
      expect(config['arb-dir'], 'lib/l10n');
      expect(config['template-arb-file'], 'app_en-US.arb');
      expect(config['key_file'], 'translator_key');
      expect(config['targets'], ['es-ES', 'ja']);
      expect(config['prefer-lang-templates'], {'fr': 'es-ES', 'ja': 'en-US'});
      expect(
          File(config['key_file']).readAsStringSync(), 's0meArb1tr4ryK3yV4lu3');
    });

    // Test with custom key file location
    test('custom key file location', () {
      setCurrentDirectory('custom-key-file');
      File('l10n.yaml').writeAsStringSync('''
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart

translator:
  key_file: path/to/key_file
  targets:
    - es
    - ja
''');

      expect(config, isNotNull);
      expect(config['arb-dir'], 'lib/l10n');
      expect(config['template-arb-file'], 'app_en.arb');
      expect(config['key_file'], 'path/to/key_file');
      expect(config['targets'], ['es', 'ja']);
    });

    // config file is required
    test('missing config file', () {
      setCurrentDirectory('empty');
      expect(() => config, throwsA(const TypeMatcher<FileSystemException>()));
    });

    // a key file is required to use the Google Translation API
    test('missing key file', () {
      setCurrentDirectory('custom');
      expect(() => File(config['key_file']).readAsStringSync(),
          throwsA(const TypeMatcher<FileSystemException>()));
    });
  });

  group('translate', () {
    final testDir = join('.dart_tool', 'arb_translator', 'test');
    final l10nDir = join('lib', 'l10n');
    final enArbFile = File(join(l10nDir, 'app_en-US.arb'));
    final esArbFile = File(join(l10nDir, 'app_es-ES.arb'));
    final jaArbFile = File(join(l10nDir, 'app_ja.arb'));

    late String currentDirectory;
    void setCurrentDirectory(String path) {
      path = join(testDir, path);
      Directory(path).createSync(recursive: true);
      Directory.current = path;
    }

    setUp(() {
      currentDirectory = Directory.current.path;
    });

    tearDown(() {
      Directory.current = currentDirectory;
    });

    test('translate', () async {
      setCurrentDirectory('default');

      // Create the template file containing 4 values of varying complexity
      enArbFile
        ..createSync(recursive: true)
        ..writeAsStringSync('''
{
    "appTitle": "Demo App",
    "@appTitle": {
        "description": "Name of app."
    },
    "greeting": "Hello, {world}!",
    "@greeting": {
        "description": "Traditional greeting used by programmers.",
        "translator": {
          "force": true
        }
    },
    "birthday": "{sex, select, male{His birthday} female{Her birthday} other{Their birthday}}",
    "@birthday": {
        "description": "Birthday message based on sexual identitity.",
        "placeholders": {
            "sex": {}
        }
    },
    "complexExample": "{mode, select, 0{Test with \$variable_name_type1} 1{Test with \$variableNameType2} 2{Test with \$oneMore_for_goodMeasure}}",
    "@complexExample": {
        "description": "A complex string using other arb defined strings as variables.",
        "placeholders": {
            "mode": {
                "type": "int"
            }
        }
    },
    "ignoreThisString": "Blah, blah, blah...",
    "@ignoreThisString": {
      "translator": {
        "ignore": true
      }
    }
}
''');

      // Create a file containing a value that should not be retranslated
      esArbFile.writeAsStringSync('''
{
    "appTitle": "Título de la aplicación anterior"
}
''');
      if (jaArbFile.existsSync()) jaArbFile.deleteSync();

      // Map mock values that would be returned from Google Translate for
      // all possible template values
      final esTranslations = {
        "Demo App": "Aplicación de demostración",
        "Hello, [VAR_0]!": "¡Hola, [VAR_0]!",
        "[CVAR_0] [CVAR_1]{His birthday} [CVAR_2]{Her birthday} [CVAR_3]{Their birthday}":
            "[CVAR_0] [CVAR_1]{Su cumpleaños} [CVAR_2]{Su cumpleaños} [CVAR_3]{Su cumpleaños}",
        "[CVAR_4] [CVAR_5]{Test with [CVAR_10]} [CVAR_6]{Test with [CVAR_9]} [CVAR_7]{Test with [CVAR_8]}":
            "[CVAR_4] [CVAR_5]{Prueba con [CVAR_10]} [CVAR_6]{Prueba con [CVAR_9]} [CVAR_7]{Prueba con [CVAR_8]}",
      };
      final jaTranslations = {
        "Demo App": "デモアプリ",
        "Hello, [VAR_0]!": "こんにちは、[VAR_0]！",
        "[CVAR_0] [CVAR_1]{His birthday} [CVAR_2]{Her birthday} [CVAR_3]{Their birthday}":
            "[CVAR_0][CVAR_1]{彼の誕生日}[CVAR_2]{彼女の誕生日}[CVAR_3]{彼らの誕生日}",
        "[CVAR_4] [CVAR_5]{Test with [CVAR_10]} [CVAR_6]{Test with [CVAR_9]} [CVAR_7]{Test with [CVAR_8]}":
            "[CVAR_4][CVAR_5]{[CVAR_10]でテスト}[CVAR_6]{[CVAR_9]でテスト}[CVAR_7]{[CVAR_8]でテスト}",
      };

      // Mock request/response from Google Translate
      final client = MockClient(((request) async {
        final req = jsonDecode(request.body);
        final query = req['q'].cast<String>();
        final results = <String>[];
        final translations =
            req['target'] == 'es-ES' ? esTranslations : jaTranslations;
        for (final s in query) {
          if (translations[s] != null) results.add(translations[s]!);
        }
        return http.Response(
            jsonEncode(
              {
                'data': {
                  'translations':
                      results.map((text) => {'translatedText': text}).toList(),
                },
              },
            ),
            200,
            headers: {
              HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
            });
      }));

      await Translator(config).translate(client);

      // Check that the correct files are written to
      // and contain the correct translations
      expect(esArbFile.readAsStringSync(), '''
{
    "appTitle": "Título de la aplicación anterior",
    "greeting": "¡Hola, {world}!",
    "birthday": "{sex, select, male{Su cumpleaños} female{Su cumpleaños} other{Su cumpleaños}}",
    "complexExample": "{mode, select, 0{Prueba con \$variable_name_type1} 1{Prueba con \$variableNameType2} 2{Prueba con \$oneMore_for_goodMeasure}}"
}''');
      expect(jaArbFile.readAsStringSync(), '''
{
    "appTitle": "デモアプリ",
    "greeting": "こんにちは、{world}！",
    "birthday": "{sex, select, male{彼の誕生日} female{彼女の誕生日} other{彼らの誕生日}}",
    "complexExample": "{mode, select, 0{\$variable_name_type1でテスト} 1{\$variableNameType2でテスト} 2{\$oneMore_for_goodMeasureでテスト}}"
}''');
    });
  });
}
