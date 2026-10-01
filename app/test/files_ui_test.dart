import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/file_browser.dart';
import 'package:tildeck/ssh/local_files.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/files_page.dart';

/// The browser's server side, recorded instead of performed.
class RecordingBrowser extends FileBrowser {
  RecordingBrowser() : super(() => throw UnimplementedError());

  final opened = <String>[];
  final uploaded = <(String, String)>[];

  @override
  Future<void> start() async {
    path = '/home/deploy';
    entries = const [
      RemoteEntry(name: 'logs', path: '/home/deploy/logs', isDirectory: true, isLink: false),
      RemoteEntry(name: 'notes.txt', path: '/home/deploy/notes.txt', isDirectory: false, isLink: false, size: 5),
    ];
    notifyListeners();
  }

  @override
  Future<void> open(String folder) async {
    opened.add(folder);
  }

  @override
  Future<Transfer> download(RemoteEntry entry, File target) async {
    await target.writeAsString('hello');
    final t = Transfer(entry.name, TransferDirection.download, 5)
      ..done = 5
      ..state = TransferState.done;
    transfers.insert(0, t);
    notifyListeners();
    return t;
  }

  @override
  Future<void> upload(Stream<List<int>> source, String name, int? size) async {
    uploaded.add((name, utf8.decode(await source.expand((c) => c).toList())));
  }
}

class TempFiles implements LocalFiles {
  TempFiles(this.dir);
  final Directory dir;
  final kept = <String>[];

  @override
  Future<List<PickedFile>> pickToUpload() async => [
    PickedFile('script.sh', 9, () => Stream.value(utf8.encode('echo hi\n'))),
  ];

  @override
  Future<File> downloadTarget(String name) async => File('${dir.path}/$name');

  @override
  Future<String?> keep(File downloaded, String name) async {
    kept.add(await downloaded.readAsString());
    return downloaded.path;
  }
}

/// Real file work completes outside the test clock: let it run between
/// frames until [done], for up to ten seconds.
Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

void main() {
  testWidgets('a folder opens, a file downloads where the user keeps files, and uploads go to the folder', (
    tester,
  ) async {
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-files')))!;
    addTearDown(() => dir.delete(recursive: true));
    final browser = RecordingBrowser();
    final local = TempFiles(dir);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: FilesPage(browser: browser, title: 'deploy@example.com', local: local),
      ),
    );
    await tester.pump();
    expect(find.text('/home/deploy'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('entry-logs')));
    await tester.pump();
    expect(browser.opened, ['/home/deploy/logs']);

    await tester.tap(find.byKey(const ValueKey('entry-notes.txt')));
    await waitFor(tester, () => local.kept.isNotEmpty);
    expect(local.kept, ['hello']);
    expect(find.textContaining('Saved to'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('filesUpload')));
    await waitFor(tester, () => browser.uploaded.isNotEmpty);
    expect(browser.uploaded, [('script.sh', 'echo hi\n')]);
  });
}
