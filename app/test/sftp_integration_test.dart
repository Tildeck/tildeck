// SFTP against the throwaway OpenSSH server of scripts/verify.sh --area app
// (see ssh_integration_test.dart for the environment). Skipped without it,
// unless TILDECK_REQUIRE_SSH_TESTS is set.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/file_browser.dart';
import 'package:tildeck/ssh/known_hosts.dart';
import 'package:tildeck/ssh/ssh_connector.dart';

final env = Platform.environment;
final host = env['TILDECK_TEST_SSH_HOST'];
final port = int.tryParse(env['TILDECK_TEST_SSH_PORT'] ?? '') ?? 2222;
final user = env['TILDECK_TEST_SSH_USER'] ?? 'tildeck';
final password = env['TILDECK_TEST_SSH_PASSWORD'];

void main() {
  final skip = host == null
      ? (env['TILDECK_REQUIRE_SSH_TESTS'] == null ? 'no test SSH server in the environment' : null)
      : null;

  group('SFTP', skip: skip, () {
    late SSHClient client;
    late Directory local;
    late String folder;

    setUp(() async {
      if (host == null) fail('TILDECK_REQUIRE_SSH_TESTS is set but no test SSH server was provided.');
      client = await SshConnector(knownHosts: MemoryKnownHosts()).connect(
        ConnectionTarget(host: host!, port: port, username: user, password: password),
        promptHostKey: ({required target, required presented, required status, previous}) async => true,
      );
      local = await Directory.systemTemp.createTemp('tildeck-sftp');
      folder = 'tildeck-sftp-${Random().nextInt(1 << 32)}';
    });

    tearDown(() async {
      await client.run('rm -rf ~/$folder');
      client.close();
      await local.delete(recursive: true);
    });

    test('browse, create a folder, upload, download, and refuse to overwrite', () async {
      final browser = FileBrowser(client.sftp);
      addTearDown(browser.dispose);
      await browser.start();
      expect(browser.problem, isNull);
      final home = browser.path!;
      expect(home, startsWith('/'));

      await browser.createFolder(folder);
      expect(browser.entries.where((e) => e.name == folder).single.isDirectory, isTrue);
      await browser.open(joinRemote(home, folder));
      expect(browser.entries, isEmpty);

      // Larger than one SFTP packet, so it goes in several chunks.
      final content = List<int>.generate(300 * 1024, (i) => (i * 31) % 251);
      final upload = Stream.fromIterable([content.sublist(0, 100000), content.sublist(100000)]);
      await browser.upload(upload, 'report.bin', content.length);
      expect(browser.transfers.first.state, TransferState.done);
      final listed = browser.entries.single;
      expect((listed.name, listed.size, listed.isDirectory), ('report.bin', content.length, false));

      final target = File('${local.path}/report.bin');
      final download = await browser.download(listed, target);
      expect(download.state, TransferState.done);
      expect(download.done, content.length);
      expect(await target.readAsBytes(), content);

      await browser.upload(Stream.value(utf8.encode('other')), 'report.bin', 5);
      expect(browser.transfers.first.problem, FileProblem.exists, reason: 'an upload never replaces a file');
      expect((await browser.download(listed, target)).state, TransferState.done);
      expect(await target.readAsBytes(), content, reason: 'the first file is untouched');

      await browser.up();
      expect(browser.path, home);
      await browser.open(joinRemote(home, 'no-such-folder-here'));
      expect(browser.problem, FileProblem.notFound);
    });

    test('a folder without permission is reported, not thrown', () async {
      final browser = FileBrowser(client.sftp);
      addTearDown(browser.dispose);
      await browser.start();
      await browser.open('/root');
      expect(browser.problem, FileProblem.denied);
    });

    test('rename, permissions, hidden files, sorting, going to a path, and deleting a folder tree', () async {
      // A tree made by the shell: a folder inside, a hidden file, a link.
      await client.run(
        'mkdir -p ~/$folder/tree/inner && printf 12345 > ~/$folder/big.txt && printf 1 > ~/$folder/a.txt && '
        'printf x > ~/$folder/tree/inner/deep.txt && touch ~/$folder/.hidden && '
        'ln -s ~/$folder/tree ~/$folder/link-to-tree && touch -d 2020-01-01 ~/$folder/a.txt',
      );
      final browser = FileBrowser(client.sftp);
      addTearDown(browser.dispose);
      await browser.start();
      await browser.goTo(folder);
      expect(browser.problem, isNull);
      expect(browser.path, endsWith('/$folder'));

      List<String> names() => browser.entries.map((e) => e.name).toList();
      expect(names(), ['link-to-tree', 'tree', 'a.txt', 'big.txt'], reason: 'folders first; dotfiles hidden');
      browser.setShowHidden(true);
      expect(names(), contains('.hidden'));
      browser.setShowHidden(false);
      browser.setSortBy(SortBy.size);
      expect(names().sublist(2), ['big.txt', 'a.txt'], reason: 'largest first');
      browser.setSortBy(SortBy.modified);
      expect(names().last, 'a.txt', reason: 'oldest last');

      RemoteEntry entry(String name) => browser.entries.firstWhere((e) => e.name == name);
      await browser.rename(entry('a.txt'), 'b.txt');
      expect(names(), contains('b.txt'));
      await browser.rename(entry('b.txt'), 'big.txt');
      expect(browser.problem, FileProblem.exists, reason: 'a rename never replaces another file');
      await browser.rename(entry('b.txt'), '../escape.txt');
      expect(browser.problem, FileProblem.failed, reason: 'a name, not a path');

      await browser.setPermissions(entry('big.txt'), 0x1c0); // 0700
      expect(entry('big.txt').permissions, 0x1c0);
      expect(permissionString(entry('big.txt').permissions!), 'rwx------');
      expect((await client.run('stat -c %a ~/$folder/big.txt').then(utf8.decode)).trim(), '700');

      // Deleting the link removes the link, not what it points to.
      await browser.delete(entry('link-to-tree'));
      expect(names(), isNot(contains('link-to-tree')));
      expect((await client.run('cat ~/$folder/tree/inner/deep.txt').then(utf8.decode)), 'x');

      await browser.delete(entry('tree'));
      expect(browser.problem, isNull);
      expect(names(), ['big.txt', 'b.txt'], reason: 'still by date: the renamed file kept its old one');
      expect((await client.run('ls -A ~/$folder').then(utf8.decode)).split('\n').where((l) => l.isNotEmpty).toSet(), {
        '.hidden',
        'b.txt',
        'big.txt',
      });
    });
  });

  group('editing over SFTP', skip: skip, () {
    late SSHClient client;
    late String folder;
    setUp(() async {
      client = await SshConnector(knownHosts: MemoryKnownHosts()).connect(
        ConnectionTarget(host: host!, port: port, username: user, password: password),
        promptHostKey: ({required target, required presented, required status, previous}) async => true,
      );
      folder = 'tildeck-edit-${Random().nextInt(1 << 32)}';
      await client.run(
        r"mkdir -p ~/$F && printf 'a\r\nb\r\n' > ~/$F/win.conf && head -c 3000000 /dev/zero | tr '\0' x > ~/$F/big.txt && "
                r"printf 'x\0y' > ~/$F/bin.dat && printf 'caf\351' > ~/$F/latin1.txt"
            .replaceAll(r'$F', folder),
      );
    });
    tearDown(() async {
      await client.run('rm -rf ~/$folder');
      client.close();
    });

    Future<String> remote(String name) async => utf8.decode(await client.run('cat ~/$folder/$name'));

    test('a text file is edited, its line ends kept, and a change on the server is not overwritten unasked', () async {
      final browser = FileBrowser(client.sftp);
      addTearDown(browser.dispose);
      await browser.start();
      await browser.goTo(folder);
      RemoteEntry entry(String name) => browser.entries.firstWhere((e) => e.name == name);

      final file = (await browser.openText(entry('win.conf')))!;
      expect(file.text, 'a\nb\n');
      expect(file.crlf, isTrue);
      expect(await browser.saveText(file, 'a\nc\n'), isTrue);
      expect(await remote('win.conf'), 'a\r\nc\r\n', reason: 'Windows line ends stay');

      // Someone else writes to it; saving again is refused, then forced.
      await client.run('printf "theirs\\r\\n" >> ~/$folder/win.conf');
      expect(await browser.saveText(file, 'mine\n'), isFalse);
      expect(browser.problem, FileProblem.changed);
      expect(await remote('win.conf'), contains('theirs'), reason: 'their change is kept');
      expect(await browser.saveText(file, 'mine\n', overwrite: true), isTrue);
      expect(await remote('win.conf'), 'mine\r\n');

      expect(await browser.openText(entry('big.txt')), isNull);
      expect(browser.problem, FileProblem.tooLarge);
      expect(await browser.openText(entry('bin.dat')), isNull);
      expect(browser.problem, FileProblem.notText);
      expect(await browser.openText(entry('latin1.txt')), isNull);
      expect(browser.problem, FileProblem.notText, reason: 'only UTF-8 is edited, so nothing is mangled');
    });
  });

  test('permissions read as ls shows them', () {
    expect(permissionString(0x1ed), 'rwxr-xr-x'); // 0755
    expect(permissionString(0x1a4), 'rw-r--r--'); // 0644
    expect(permissionString(0), '---------');
  });

  test('remote paths are POSIX on every platform', () {
    expect(joinRemote('/', 'a'), '/a');
    expect(joinRemote('/home/x', 'a'), '/home/x/a');
    expect(parentOf('/home/x'), '/home');
    expect(parentOf('/home'), '/');
    expect(parentOf('/'), '/');
  });
}
