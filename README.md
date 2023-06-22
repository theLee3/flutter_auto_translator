# Auto Translator

A command-line tool that simplifies translation of an ARB template file to selected languages using Google Cloud Translate. Designed to work seamlessly with the `flutter_localizations` and `intl` packages, Flutter's preferred internationalization approach.

## Features

- Seamless integration with `flutter_localizations` and `intl` packages.
- Minimal Cloud Translate quota usage.
- Works with simple & complex ARB strings, conditions, and variables.

## Getting Started

### 1. Setup Google Cloud Translate

If you do not have a Google Cloud Project with the Cloud Translation API enabled, follow the guide [here](https://cloud.google.com/translate/docs/setup).

Then save your API key to a file in your project root called `translator_key`.

NOTE: This is the default location. You will see how to specify a different location later in this guide.

### 2. Add auto_translator to your project

Add auto_translator under dev_dependencies in `pubspec.yaml`

```yaml
dev_dependencies:
  auto_translator: "^1.1.0"
```

### 3. Setup the config files

`auto_translator` uses the same config file as the `intl` package, Flutter's recommended package for internationalizing your app, as explained [here](https://docs.flutter.dev/development/accessibility-and-localization/internationalization).

If you have not already created the `l10n.yaml` file, do so now.

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart

translator:
  targets:
    - es
    - fr
    - ja
```

The first three parameters are used by `intl` as well as `auto_translator`. The `translator` section is specific to `auto_translator`.

 The `targets` parameter is required and tells `auto_translator` which languages to translate the template file to. Available languages can be found [here](https://cloud.google.com/translate/docs/languages).

### Regional Designations

 You can use 2-letter language codes or include regional designations (en-US, en-GB, es-Es, etc.).

An optional `key_file` parameter can be provided if you wish to store your Google Translate API key somehwere other than the default location.

:warning: **DO NOT** publish your key file to Github or similar VCS.

### 4. Run the package

Once configured, run the package from the command line.

```bash
flutter pub get
flutter pub run auto_translator
```

All translations will be placed in the defined location and be compatible with `flutter_localizations` and `intl`.

## Additional Usage

To prevent unecessary Google Cloud Translate quota usage, messages that already exist in a target ARB file are not retranslated. You can force a translation by adding the `force` parameter to `translator` options in a message's metadata in the template file.

```yaml
{
  "title": "New Title",
  "@title": {
    "description": "...",
    "translator": {
      "force": true
    }
  }
}
```

You can also tell the translator to ignore a particular message with the `ignore` tag.

```yaml
{
  "doNotTranslate": "{mode, select, 0{$title1} 1{$title2} 2{$title3}}",
  "@doNotTranslate": {
    "description": "...",
    "translator": {
      "ignore": true
    }
  }
}
```

### Preferred Templates

Sometimes, you may wish to specify a language that translates more accurately to a target than the language used in the `template-arb-file`. For that, you can now provide a `prefer-lang-templates` map to specify a preferred language to use as a template for any target language.

```yaml
translator:
  # use es template for fr translation ja for ko
  # all other translations will use [template-arb-file]
  prefer-lang-templates: {
    'fr': 'es',
    'ko': 'ja',
  }
```

### Alternate config file

By default, the config file is named `l10n.yaml` and is located in the project's root directory. You can pass in an alternate file path when running on the command line using the `--config-file` option.
