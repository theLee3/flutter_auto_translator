// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Localization Demo App';

  @override
  String get homePageTitle => 'Localization Demo Home Page';

  @override
  String buttonPresses(int count) {
    return 'You have pushed the button this many times: $count';
  }

  @override
  String get ignoredString => 'Ignore this string!';

  @override
  String birthday(String sex) {
    String _temp0 = intl.Intl.selectLogic(
      sex,
      {
        'male': 'His birthday',
        'female': 'Her birthday',
        'other': 'Their birthday',
      },
    );
    return '$_temp0';
  }

  @override
  String get tooltip => 'Increment';

  @override
  String viewingArtwork(String artworkTitle) {
    return 'Now viewing $artworkTitle.';
  }
}
