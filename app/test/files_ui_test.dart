import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      RemoteEntry(
        name: 'notes.txt',
        path: '/home/deploy/notes.txt',
        isDirectory: false,
        isLink: false,
        size: 5,
        permissions: 0x1a4,
      ),
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

  final actions = <String>[];

  @override
  Future<void> rename(RemoteEntry entry, String name) async => actions.add('rename ${entry.name} to $name');

  @override
  Future<void> delete(RemoteEntry entry) async => actions.add('delete ${entry.name}');

  @override
  Future<void> setPermissions(RemoteEntry entry, int mode) async =>
      actions.add('chmod ${entry.name} ${mode.toRadixString(8)}');

  @override
  Future<void> deleteAll(List<RemoteEntry> list) async => actions.add('delete ${list.map((e) => e.name).join(', ')}');
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

  @override
  bool get folders => true;

  @override
  Future<Directory> folderTarget(String name) async => Directory('${dir.path}/$name');

  @override
  Future<Directory?> pickFolderToUpload() async => null;
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

    // Where folders can move, Upload asks: files or a folder.
    await tester.tap(find.byKey(const ValueKey('filesUpload')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('filesUploadFolder')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('filesUploadFiles')));
    await waitFor(tester, () => browser.uploaded.isNotEmpty);
    expect(browser.uploaded, [('script.sh', 'echo hi\n')]);
  });

  testWidgets('rename, permissions, copy the path, and delete after asking', (tester) async {
    final browser = RecordingBrowser();
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: FilesPage(browser: browser, title: 'deploy@example.com', local: TempFiles(Directory.systemTemp)),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> menu(String entry, String item) async {
      await tester.tap(find.byKey(ValueKey('entryMenu-$entry')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(item)));
      await tester.pumpAndSettle();
    }

    // Rename: the name is offered, its stem selected.
    await menu('notes.txt', 'entryRename');
    final field = tester.widget<TextField>(find.byKey(const ValueKey('folderName')));
    expect(field.controller!.text, 'notes.txt');
    expect(field.controller!.selection, const TextSelection(baseOffset: 0, extentOffset: 5));
    await tester.enterText(find.byKey(const ValueKey('folderName')), 'todo.txt');
    await tester.tap(find.byKey(const ValueKey('nameDialogOk')));
    await tester.pumpAndSettle();

    // Permissions: 0644 shown, group write added.
    await menu('notes.txt', 'entryPermissions');
    expect(find.text('644  rw-r--r--'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('permission-4')));
    await tester.pumpAndSettle();
    expect(find.text('664  rw-rw-r--'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('savePermissions')));
    await tester.pumpAndSettle();

    await menu('notes.txt', 'entryCopyPath');
    expect(clipboard, '/home/deploy/notes.txt');

    // Delete asks first; a cancel deletes nothing.
    await menu('logs', 'entryDelete');
    expect(find.textContaining('and everything in it'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await menu('logs', 'entryDelete');
    await tester.tap(find.byKey(const ValueKey('confirmDelete')));
    await tester.pumpAndSettle();

    expect(browser.actions, ['rename notes.txt to todo.txt', 'chmod notes.txt 664', 'delete logs']);
  });

  testWidgets('a long press selects several, and they are deleted together after asking', (tester) async {
    final browser = RecordingBrowser();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: FilesPage(browser: browser, title: 'deploy@example.com', local: TempFiles(Directory.systemTemp)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('entry-logs')));
    await tester.pumpAndSettle();
    // While selecting, a tap selects instead of opening.
    await tester.tap(find.byKey(const ValueKey('entry-notes.txt')));
    await tester.pumpAndSettle();
    expect(browser.opened, isEmpty);
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('selectionDelete')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 items will be deleted'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirmDelete')));
    await tester.pumpAndSettle();
    expect(browser.actions, ['delete logs, notes.txt']);
    expect(find.text('2 selected'), findsNothing, reason: 'the selection is done');
  });

  testWidgets('a running transfer is cancelled from the list', (tester) async {
    final browser = RecordingBrowser();
    final transfer = _CancelRecorder('backup.tar', TransferDirection.download, 1000)..done = 300;
    browser.transfers.add(transfer);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: FilesPage(browser: browser, title: 'deploy@example.com', local: TempFiles(Directory.systemTemp)),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('cancelTransfer-backup.tar')));
    await tester.pump();
    expect(transfer.cancelled, isTrue);
  });
}

class _CancelRecorder extends Transfer {
  _CancelRecorder(super.name, super.direction, super.total);
  var cancelled = false;

  @override
  Future<void> cancel() async => cancelled = true;
}
