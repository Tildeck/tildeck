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
  });

  test('remote paths are POSIX on every platform', () {
    expect(joinRemote('/', 'a'), '/a');
    expect(joinRemote('/home/x', 'a'), '/home/x/a');
    expect(parentOf('/home/x'), '/home');
    expect(parentOf('/home'), '/');
    expect(parentOf('/'), '/');
  });
}
