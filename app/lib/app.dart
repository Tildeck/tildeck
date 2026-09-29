import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'home_page.dart';
import 'l10n/app_localizations.dart';
import 'server_check.dart';
import 'theme.dart';

class TildeckApp extends StatefulWidget {
  const TildeckApp({super.key, this.checker, this.initialLocale, this.initialThemeMode = ThemeMode.system});

  final ServerChecker? checker;

  /// Null follows the device language.
  final Locale? initialLocale;
  final ThemeMode initialThemeMode;

  @override
  State<TildeckApp> createState() => _TildeckAppState();
}

class _TildeckAppState extends State<TildeckApp> {
  late Locale? _locale = widget.initialLocale;
  late ThemeMode _themeMode = widget.initialThemeMode;
  late final ServerChecker _checker = widget.checker ?? ServerChecker();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: _themeMode,
      locale: _locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) {
          final current = Localizations.localeOf(context);
          final dark = Theme.of(context).brightness == Brightness.dark;
          return HomePage(
            checker: _checker,
            onToggleLocale: () => setState(() {
              _locale = current.languageCode == 'he' ? const Locale('en') : const Locale('he');
            }),
            onToggleTheme: () => setState(() => _themeMode = dark ? ThemeMode.light : ThemeMode.dark),
          );
        },
      ),
    );
  }
}
