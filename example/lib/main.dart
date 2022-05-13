import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  var locale = const Locale('en');
  var _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: Builder(builder: (context) {
        final localizedText = AppLocalizations.of(context)!;
        return Scaffold(
          appBar: AppBar(
            title: FittedBox(child: Text(localizedText.homePageTitle)),
            actions: [
              PopupMenuButton<Locale>(
                itemBuilder: (context) => AppLocalizations.supportedLocales
                    .map(
                      (locale) => PopupMenuItem(
                        value: locale,
                        child: Text(locale.languageCode),
                      ),
                    )
                    .toList(),
                onSelected: (locale) => setState(() => this.locale = locale),
              )
            ],
          ),
          body: Center(
            child: Text(
              localizedText.buttonPresses(_counter),
              style: const TextStyle(fontSize: 28.0),
              textAlign: TextAlign.center,
              softWrap: true,
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _incrementCounter,
            tooltip: localizedText.tooltip,
            child: const Icon(Icons.add),
          ),
        );
      }),
    );
  }
}
