import 'dart:io';

import 'package:args/args.dart';
import 'package:auto_translator/auto_translator.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

const String _helpFlag = 'help';

/// Yaml file used to configure Translator.
const String configFile = 'l10n.yaml';
const String _translatorKey = 'translator';
const String _defaultKeyFile = 'translator_key';

/// Parses arguments from command line, providing help or running [Translator].
Future<void> runWithArguments(List<String> arguments) async {
  final ArgParser parser = ArgParser();
  parser.addFlag(_helpFlag, abbr: 'h', help: 'Usage help', negatable: false);
  final ArgResults argResults = parser.parse(arguments);

  if (argResults[_helpFlag]) {
    stdout.writeln(helpMessage);
  } else {
    Translator(config).translate(http.Client());
  }
}

/// Converts Yaml file to a Map.
Map<String, dynamic> get config {
  final File file = File(configFile);
  final String yamlString = file.readAsStringSync();
  final Map yamlMap = loadYaml(yamlString);

  if (yamlMap[_translatorKey] is! Map) {
    stderr.writeln(
      ConfigNotFoundException(
          '`$configFile` is missing `translator` section or it is configured incorrectly.'),
    );
    exit(1);
  }

  // `YamlMap`s can have unwanted side effects, so convert to Map
  return _mapConfigEntries(yamlMap.entries);
}

Map<String, dynamic> _mapConfigEntries(Iterable<MapEntry> entries) {
  final Map<String, dynamic> config = <String, dynamic>{};
  for (final entry in entries) {
    if (entry.key == _translatorKey) {
      config.addAll(_mapConfigEntries(YamlMap.wrap(entry.value).entries));
    } else if (entry.value is YamlList) {
      config[entry.key] = entry.value.toList();
    } else {
      config[entry.key] = entry.value;
    }
  }
  if (!config.containsKey('key_file')) config['key_file'] = _defaultKeyFile;
  return config;
}
