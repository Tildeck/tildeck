import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/putty_sessions.dart';
import 'package:tildeck/ssh/ssh_connector.dart' show ConnectionProtocol;
import 'package:tildeck/vault/host_csv.dart';
import 'package:tildeck/vault/host_import.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

void main() {
  test('CSV fields may be quoted, hold commas, quotes, and line breaks', () {
    expect(parseCsv('a,"b,c","say ""hi""","two\nlines"\r\n\r\nx,y\n'), [
      ['a', 'b,c', 'say "hi"', 'two\nlines'],
      ['x', 'y'],
    ]);
  });

  test("hosts from a CSV with other tools' headers; a row without a host is skipped", () {
    const text =
        'Label,Groups,Tags,Hostname/IP,Protocol,Port,Username\n'
        'Web,Production,"nginx,eu",web.example.com,ssh,2222,deploy\n'
        'Switch,Network,,10.0.0.2,telnet,,\n'
        'Nothing,,,,,,\n'
        'Web,,,web2.example.com,,,\n';
    expect(looksLikeHostsCsv(text), isTrue);
    expect(looksLikeHostsCsv('Host web\n  HostName w\n'), isFalse);
    final hosts = parseHostsCsv(text);
    expect(hosts.map((h) => h.alias), ['Web', 'Switch', 'Web (2)']);
    final web = hosts.first;
    expect(
      (web.address, web.port, web.user, web.group, web.telnet),
      ('web.example.com', 2222, 'deploy', 'Production', false),
    );
    expect(web.tags, ['nginx', 'eu']);
    expect(hosts[1].telnet, isTrue);
  });

  test('exported hosts read back the same, without secrets', () async {
    final dir = await Directory.systemTemp.createTemp('tildeck-csv');
    addTearDown(() => dir.delete(recursive: true));
    final vault = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/v.json'));
    await vault.load();
    await vault.create('orange-kettle-winter-42');
    await vault.put(
      const HostEntry(
        id: 'h1',
        name: 'Web, primary',
        host: 'web.example.com',
        port: 2222,
        username: 'deploy',
        password: 'SECRET-PASSWORD',
        group: 'Production',
        tags: ['nginx', 'eu'],
      ),
    );
    await vault.put(
      const HostEntry(
        id: 'h2',
        name: 'Switch',
        host: '10.0.0.2',
        port: 23,
        username: '',
        protocol: ConnectionProtocol.telnet,
      ),
    );
    final csv = hostsToCsv(vault.hosts);
    expect(csv, isNot(contains('SECRET-PASSWORD')));

    final other = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/o.json'));
    await other.load();
    await other.create('orange-kettle-winter-42');
    await importSshHosts(other, parseHostsCsv(csv), readFile: (_) async => null, defaultUser: 'local');
    final byName = {for (final h in other.hosts) h.name: h};
    final web = byName['Web, primary']!;
    expect((web.host, web.port, web.username, web.group), ('web.example.com', 2222, 'deploy', 'Production'));
    expect(web.tags, ['nginx', 'eu']);
    expect(
      (byName['Switch']!.protocol, byName['Switch']!.port, byName['Switch']!.username),
      (ConnectionProtocol.telnet, 23, ''),
    );
  });

  test("PuTTY's sessions from the registry: names decoded, user@host split, defaults left out", () {
    const output = r'''
HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\Default%20Settings
    HostName    REG_SZ
    PortNumber    REG_DWORD    0x16

HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\Web%20server
    HostName    REG_SZ    deploy@web.example.com
    PortNumber    REG_DWORD    0x8ae
    Protocol    REG_SZ    ssh
    UserName    REG_SZ
    PublicKeyFile    REG_SZ    C:\Users\me\keys\web.ppk

HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\Old%20switch
    HostName    REG_SZ    10.0.0.2
    PortNumber    REG_DWORD    0x17
    Protocol    REG_SZ    telnet

HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\Sessions\Console
    HostName    REG_SZ    COM3
    Protocol    REG_SZ    serial
''';
    final hosts = parsePuttyRegistry(output);
    expect(hosts.map((h) => h.alias), ['Web server', 'Old switch'], reason: 'no defaults, no serial line');
    final web = hosts.first;
    expect((web.address, web.user, web.port, web.telnet), ('web.example.com', 'deploy', 2222, false));
    expect(web.identityFiles, [r'C:\Users\me\keys\web.ppk']);
    expect((hosts[1].port, hosts[1].telnet), (23, true));
  });
}
