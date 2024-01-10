import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:auto_translator/src/exceptions.dart';
import 'package:auto_translator/src/transformer.dart';
import 'package:yaml/yaml.dart';

import 'translator.dart';

const _helpFlag = 'help';
const _configOption = 'config-file';

const _defaultConfigFile = 'l10n.yaml';
const _translatorKey = 'translator';
const _defaultKeyFile = 'translator_key';

/// Parses arguments from command line, providing help or generating translations.
Future<void> runWithArguments(List<String> arguments) async {
  final parser = ArgParser();
  parser
    ..addFlag(_helpFlag, abbr: 'h', help: 'Usage help', negatable: false)
    ..addOption(
      _configOption,
      abbr: 'f',
      help: 'Path to config file',
      defaultsTo: _defaultConfigFile,
    );
  final argResults = parser.parse(arguments);

  if (argResults[_helpFlag]) {
    stdout.writeln(helpMessage);
  } else {
    final configFile = File(argResults[_configOption] ?? _defaultConfigFile);
    try {
      final yamlString = configFile.readAsStringSync();
      final yamlMap = loadYaml(yamlString);

      if (yamlMap[_translatorKey] is! Map) {
        throw ConfigNotFoundException(
            '`$configFile` is missing `translator` section or it is configured incorrectly.');
      }

      final Map<String, dynamic> config =
          _mapConfigEntries((yamlMap as Map).entries);

      try {
        await _translate(config);
      } on FileSystemException {
        throw GoogleTranslateException('`${config['key_file']} not found.');
      }
    } on FileSystemException {
      throw ConfigNotFoundException('`$configFile` not found.');
    }
  }
}

Map<String, dynamic> _mapConfigEntries(Iterable<MapEntry> entries) {
  final Map<String, dynamic> config = <String, dynamic>{};
  for (final entry in entries) {
    if (entry.key == _translatorKey) {
      config.addAll(_mapConfigEntries(YamlMap.wrap(entry.value).entries));
    } else if (entry.value is YamlList) {
      config[entry.key] = (entry.value as YamlList).toList();
    } else {
      config[entry.key] = entry.value;
    }
  }
  config.putIfAbsent('key_file', () => _defaultKeyFile);
  return config;
}

Future<void> _translate(Map<String, dynamic> config) async {
  final targets = (config['targets'] as List?)?.cast<String>() ?? [];
  if (targets.isEmpty) {
    throw NoTargetsProvidedException(
        'No targets were provided. There\'s nothing for me to do.');
  }

  final arbDir = config['arb-dir'] as String? ?? "lib/l10n";
  final templateFilename =
      config['template-arb-file'] as String? ?? "app_en.arb";
  final Map<String, dynamic> preferTemplateLang =
      config['prefer-lang-templates']?.cast<String, dynamic>() ?? {};

  if (!RegExp(r'^[a-zA-Z0-9]+_[a-zA-Z0-9_\-]+\.arb$')
      .hasMatch(templateFilename)) {
    throw NoTargetsProvidedException(
        '[template-arb-file] should be in the format: '
        r'^[a-zA-Z0-9]+_[a-zA-Z0-9_\-]+\.arb$');
  }

  final defaultSource = templateFilename.substring(
      templateFilename.indexOf(RegExp(r'[-_]')) + 1,
      templateFilename.indexOf('.arb'));
  final name =
      templateFilename.substring(0, templateFilename.indexOf(RegExp(r'[-_]')));

  final encoder = JsonEncoder.withIndent('    ');

  final apiKey = File(config['key_file']).readAsStringSync();
  final transformer = Transformer();
  final translator = Translator(apiKey);

  // cached templates
  final originalTemplates = <String, Map<String, dynamic>>{};
  final modifiedTemplates = <String, Map<String, dynamic>>{};
  final templateMetadata = <String, Map<String, dynamic>>{};

  // examples to use instead of placeholder variables
  final examples = <String, String>{};

  // sort target order to account for preferred template languages
  for (final preferredTemplate in preferTemplateLang.entries) {
    final targetIndex = targets.indexOf(preferredTemplate.key),
        templateIndex = targets.indexOf(preferredTemplate.value);
    if (templateIndex > targetIndex) {
      targets.insert(targetIndex, targets.removeAt(templateIndex));
    }
  }

  // subtracted from language count to provide number of languages translated to
  var skippedLanguages = 0;

  for (final target in targets) {
    final source = preferTemplateLang[target] ?? defaultSource;
    final templatePath = '$arbDir/${name}_$source.arb';
    if (!modifiedTemplates.containsKey(templatePath)) {
      final templateFile = File(templatePath);
      final template =
          jsonDecode(templateFile.readAsStringSync()) as Map<String, dynamic>;
      templateMetadata[templatePath] = _getArbMetadata(template);
      final origTemplate = Map<String, dynamic>.from(template)
        ..removeWhere((key, value) => key.startsWith('@'));
      originalTemplates[templatePath] = origTemplate;
      modifiedTemplates[templatePath] = _buildTemplate(
        Map.from(origTemplate),
        transformer: transformer,
        arbMetadata: templateMetadata[templatePath]!,
        examples: examples,
      );
    }

    final translations = <String, String>{};
    final toTranslate =
        Map<String, dynamic>.from(modifiedTemplates[templatePath]!);
    final arbFile = File('$arbDir/${name}_$target.arb');
    var previousTranslationsCount = 0;
    if (arbFile.existsSync()) {
      // do not translate previously translated phrases unless marked [force]
      final Map<String, String> prevTranslations =
          jsonDecode(arbFile.readAsStringSync()).cast<String, String>();
      toTranslate.removeWhere((key, value) {
        if (key.startsWith('@')) {
          key = key.substring(1, key.lastIndexOf(RegExp(r'_.*_')));
        }
        return prevTranslations.containsKey(key) &&
            !(templateMetadata[templatePath]!['@$key']?['translator']
                    ?['force'] ??
                false);
      });
      previousTranslationsCount = prevTranslations.length;
      translations.addAll(prevTranslations);
    }

    if (toTranslate.isEmpty) {
      skippedLanguages++;
      stdout.writeln('No changes to ${name}_$target.arb');
      continue;
    }

    stdout.write('Translating from $source to $target...');

    final results = await translator.translate(
      toTranslate: toTranslate,
      source: source,
      target: target,
    );

    results.updateAll((key, result) {
      var decodedString = transformer.decode(result);
      final exampleMatches =
          RegExp(r'___*.*__').allMatches(decodedString).toList().reversed;
      for (final match in exampleMatches) {
        final originalVariable =
            examples[decodedString.substring(match.start, match.end)];
        if (originalVariable != null) {
          decodedString = decodedString.replaceRange(
              match.start, match.end, originalVariable);
        }
      }
      return decodedString;
    });
    translations.addAll(results);

    if (translations.isNotEmpty) {
      final complexEntries =
          List<MapEntry<String, String>>.from(translations.entries)
              .where((entry) => entry.key.startsWith('@'));
      translations.removeWhere((key, value) => key.startsWith('@'));

      final originalKeys = <String>{};
      for (final entry in complexEntries) {
        originalKeys.add(entry.key.substring(1).split('_').first);
      }

      for (final key in originalKeys) {
        final complexParts =
            complexEntries.where((entry) => entry.key.startsWith('@$key'));
        translations[key] = transformer.decode(Map.fromEntries(complexParts));
      }

      // match entry order to the original template file
      final output = {
        for (final key in originalTemplates[templatePath]!.keys)
          key: translations[key]
      };
      arbFile.writeAsStringSync(encoder.convert(output));
    }
    stdout.writeln('done.');
    final translationsCount = translations.length - previousTranslationsCount;
    stdout.writeln('Translated $translationsCount '
        'entr${translationsCount == 1 ? 'y' : 'ies'} from $source to $target.');
  }

  final targetsTranslated = targets.length - skippedLanguages;
  if (targetsTranslated == 0) {
    stdout.writeln('No languages translated');
  } else {
    stdout.writeln(
        'Finished translating to $targetsTranslated language${targetsTranslated > 1 ? 's' : ''}.');
  }
}

Map<String, dynamic> _getArbMetadata(Map<String, dynamic> arbTemplate) =>
    Map.from(arbTemplate)..removeWhere((key, value) => !key.startsWith('@'));

Map<String, dynamic> _buildTemplate(
  Map<String, dynamic> arbTemplate, {
  required Transformer transformer,
  required Map<String, dynamic> arbMetadata,
  required Map<String, String> examples,
}) {
  // remove strings that are marked ignore
  arbTemplate.removeWhere((key, value) =>
      (arbMetadata['@$key']?['translator']?['ignore'] ?? false));

  final entries = List<MapEntry<String, dynamic>>.from(arbTemplate.entries);
  for (final entry in entries) {
    try {
      var value = entry.value as String;
      final Map<String, Map<String, dynamic>> placeholders =
          Map.from(arbMetadata['@${entry.key}']?['placeholders'] ?? {});
      placeholders.removeWhere((key, value) => value['example'] == null);
      for (final placeholder in placeholders.entries) {
        var modifier = '_';
        String key;
        do {
          modifier += '_';
          key = '$modifier${placeholder.value['example']}__';
        } while (examples.containsKey(key) && examples[key] != placeholder.key);
        examples.putIfAbsent(key, () => '{${placeholder.key}}');
        value = value.replaceAll('{${placeholder.key}}', key);
      }
      final encodedValue = transformer.encode(value);
      if (encodedValue is String) {
        arbTemplate[entry.key] = encodedValue;
      } else {
        arbTemplate.remove(entry.key);
        for (final encodedEntry in (encodedValue as Map).entries) {
          arbTemplate['@${entry.key}_${encodedEntry.key}'] = encodedEntry.value;
        }
      }
    } on InvalidFormatException {
      throw InvalidFormatException(entry.key);
    }
  }

  return arbTemplate;
}
