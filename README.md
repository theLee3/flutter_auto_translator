# Auto Translator

A command-line tool that simplifies translation of an ARB template file to selected languages. This package is designed to work seamlessly with the `flutter_localizations` and `intl` packages, Flutter's preferred internationalization approach.

## Features

- Seamless integration with `flutter_localizations` and `intl` packages.
- Works with Google Cloud Translate & DeepL Translate.
- Minimal quota usage.
- Works with simple & complex ARB strings, conditions, and variables.
- Uses placeholder examples for more accurate translations involving proper nouns and other unique cases.
- Specify translator service and/or source language for individual target languages.

## Support the developer

If you found this package useful, please consider contribuitng to it's continued development. Or just show the developer a little love & support. Every little bit helps!

[![Buy me a coffee](https://img.shields.io/badge/Buy%20me%20a%20coffee-grey?logo=buymeacoffee&logoColor=yellow)](https://ko-fi.com/M4M4G97OV)

## Getting Started

### 1. Setup Translation Service(s)

Auto Translator supports Google Cloud Translate and DeepL out of the box. You may specify either one as your primary service in the `l10n.yaml` config file. If neither is provided, the default (Google) is used. You may also specify different translators on a per-language basis, as seen in [Preferred Services](#preferred-services).

If you are configuring only one service, you can save the API key in a file in the project root directory called `translator_key` or as a json map in `translator_keys`. If configuring both services, you must use the json map approach.

:warning: **DO NOT** publish your key file to Github or similar VCS.

You can also specify an [alternate key file](#alternate-key-file) path.

#### Google Cloud Translate

If you do not have a Google Cloud Project with the Cloud Translation API enabled, follow the guide [here](https://cloud.google.com/translate/docs/setup).

#### DeepL Translate

If you do not have DeepL API access, follow DeepL's guide to creating an account and obtaining API access [here](https://www.deepl.com/pro/change-plan?cta=apiDocsHeader#developer)

### 2. Add auto_translator to your project

Add `auto_translator` under `dev_dependencies` in `pubspec.yaml`

```yaml
dev_dependencies:
  auto_translator: ^2.3.2
```

### 3. Setup the config files

`auto_translator` uses the same config file as the `intl` package, Flutter's recommended package for internationalizing your app, as explained [here](https://docs.flutter.dev/development/accessibility-and-localization/internationalization).

If you have not already created the `l10n.yaml` file, do so now.

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart

translator:
  #Defaults to Google Translate.
  service: Google

  targets:
    - es-ES
    - fr
    - ja
```

The first three parameters are used by `intl` as well as `auto_translator`. The `translator` section is specific to `auto_translator`.

The `targets` parameter is required and tells `auto_translator` which languages to translate the template file to. Available languages can be found [here](https://cloud.google.com/translate/docs/languages).

You can also configure [preferred source templates](#preferred-templates) for any given target language.

#### Regional Designations

You can use 2-letter language codes and regional designations (en-US, en-GB, es-Es, etc.).

### 4. Run the package

Once configured, run the package from the command line.

```bash
flutter pub get
dart run auto_translator
```

All translations will be placed in the defined location and be compatible with `flutter_localizations` and `intl`.

## Additional Usage

### Placeholder Examples

Some translations are more accurate when using an example in place of a generic placeholder variable name. `auto_translator` now passes a placeholder's example if provided to ensure better quality translations.

```json
"viewingArtwork": "Now viewing {artworkTitle}.",
  "@viewingArtwork": {
      "placeholders": {
          "artworkTitle": {
              "type": "String",
              "example": "Mona Lisa"
          }
      }
  }
```

### Force Translation

To prevent unecessary Google Cloud Translate quota usage, messages that already exist in a target ARB file are not retranslated. You can force a translation by adding the `force` parameter to `translator` options in a message's metadata in the template file.

```json
"title": "New Title",
"@title": {
  "description": "...",
  "translator": {
    "force": true
  }
}
```

### Ignore ARB String

You can also tell the translator to ignore a particular message with the `ignore` tag.

```json
"doNotTranslate": "DO NOT TRANSLATE THIS STRING!!!",
"@doNotTranslate": {
  "description": "...",
  "translator": {
    "ignore": true
  }
}
```

### Preferred Templates

Sometimes, you may wish to specify a language that translates more accurately to a target than the language used in the `template-arb-file`. For that, you can provide a `prefer-lang-templates` map to specify a preferred source language to use as a template for any target language.

```yaml
translator:
  # use es-ES template for fr translation ja for ko
  # all other translations will use [template-arb-file]
  prefer-lang-templates:
    fr: es
    ko: ja
```

### Preferred Services

As one service may outperform the other in a given language you may wish to specify a service an a per-language basis. This can be done by providing a `prefer-service` map in the config file.

```yaml
translator:
  # use DeepL for tr and uk
  # all other translations will use the primary service
  # (presumably Google in this case)
  prefer-service:
    # capitilization does not matter for service name
    DeepL:
      - tr
      - uk
```

Each API key must be provided in the key file (service name capitalization does not matter).

```json
{
  "google": "CLOUD_TRANSLATE_API_KEY",
  "deepL": "DEEP_L_API_KEY"
}
```

### Alternate config file

By default, the config file is named `l10n.yaml` and is located in the project's root directory. You can pass in an alternate file path when running on the command line using the `--config-file` option.

### Alternate key file

By default, `auto_translator` looks for keys in the project root at `translator_keys` or `translator_key`. You may specify a different location in the config file.

```yaml
translator:
  key_file: path/to/key/file
```
