import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/file_browser.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/file_editor_page.dart';

/// Saves into memory; the first save finds the file changed on the server.
class ChangedOnceBrowser extends FileBrowser {
  ChangedOnceBrowser() : super(() => throw UnimplementedError());

  final saves = <(String, bool)>[];

  @override
  Future<bool> saveText(EditedFile file, String text, {bool overwrite = false}) async {
    if (saves.isEmpty && !overwrite) {
      saves.add((text, overwrite));
      problem = FileProblem.changed;
      return false;
    }
    saves.add((text, overwrite));
    problem = null;
    return true;
  }
}

void main() {
  testWidgets('edit and save; a change on the server asks; leaving unsaved asks', (tester) async {
    final browser = ChangedOnceBrowser();
    final file = EditedFile(path: '/etc/app/app.conf', text: 'port=80\n', modified: 1, size: 8, crlf: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const ValueKey('openEditor'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => FileEditorPage(browser: browser, file: file),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('openEditor')));
    await tester.pumpAndSettle();

    bool canSave() => tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('saveFile'))).enabled;
    expect(canSave(), isFalse, reason: 'nothing to save yet');
    await tester.enterText(find.byKey(const ValueKey('editorText')), 'port=8080\n');
    await tester.pump();
    expect(find.text('app.conf *'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('saveFile')));
    await tester.pumpAndSettle();
    expect(find.text('Changed on the server'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('saveAnyway')));
    await tester.pumpAndSettle();
    expect(browser.saves, [('port=8080\n', false), ('port=8080\n', true)]);
    expect(find.text('app.conf'), findsOneWidget, reason: 'saved: no longer marked');

    // Unsaved changes: back asks, and keeping them stays.
    await tester.enterText(find.byKey(const ValueKey('editorText')), 'port=9090\n');
    await tester.pump();
    final back = find.byType(BackButton);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(find.text('Discard your changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('editorText')), findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discardChanges')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('openEditor')), findsOneWidget, reason: 'left without saving');
    expect(browser.saves, hasLength(2));
  });
}
