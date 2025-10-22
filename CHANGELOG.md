## 2.4.0 - 2025-10-22 - @rickypid

Added support for DeepL pro.

## 2.3.5

Improve compatibility with ARB variable names that contain underscores.
Handle edge cases where translated placeholder example may be returned by API.

## 2.3.4

Fixed a bug that would add translation results to incorrect ARB string if they shared a prefix.

## 2.3.3

Improved error handling from DeepL Translation API.
Added link to API docs in error messages from translation services.

## 2.3.2

Fixed bug that used wrong placeholder name if multiple the same example was used.

## 2.3.1

Fixed bug that set value of ignored translations to `null`.

## 2.3.0+1

- Documentation fixes.

## 2.3.0

- Added support for DeepL Translation.
- Added `service` configuration option to support different translation services.
- Added `prefer-service` configuration option to support multiple translator services on a per-language basis.
- Added `MissingTranslatorKeyException` and `MalformedTranslatorKeyFileException` for key file errors.
- Fixed bugs that could occur when translating placeholders with examples.
- Bumped minimum Dart SDK to 3.0.0.

## 2.2.0

- Add support for ARB comments.
- Translation entries are now removed when corresponding entries are removed from the template.

## 2.1.0

- Use placeholder example string if available for more accurate translations.
- Fixed a bug that incorrectly removed whitespace following a word that was moved from the end of a string.

## 2.0.0

- Migrated to the latest ARB format.

## 1.1.0

- Added support for preferred language templates per target language.
- Added support for regional language codes (en-US, en-GB, es-ES, etc).
- Default values now conform to the latest internationalization guidelines.

## 1.0.2

- Always match translated ARB files' definition order to the template ARB file.
- Handle escaped curly brace characters.
- Handle whitespace that is sometimes introduced by Google Cloud Translate.
- Provide more information in `InvalidFormatException`

## 1.0.1

- Fixed bug affecting simple strings that begin & end with a variable.
- Added `InvalidFormatException` for mismatched curly braces.

## 1.0.0

- Initial version.
