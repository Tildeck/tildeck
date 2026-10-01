import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ui/hosts_page.dart';
import 'package:tildeck/vault/models.dart';
import 'package:tildeck/vault/vault.dart';
import 'package:tildeck/vault/vault_crypto.dart';

const web = HostEntry(
  id: 'h1',
  name: 'Web 01',
  group: 'Production',
  host: 'web-01.example.com',
  username: 'deploy',
  tags: ['nginx', 'eu-west'],
);

void main() {
  test('search matches every word, in name, address, user, group, or tag', () {
    expect(hostMatches(web, ''), isTrue);
    expect(hostMatches(web, 'web'), isTrue);
    expect(hostMatches(web, 'PRODUCTION nginx'), isTrue);
    expect(hostMatches(web, 'eu-west deploy'), isTrue);
    expect(hostMatches(web, 'nginx staging'), isFalse);
  });

  test('environment variables are written one per line as NAME=value', () {
    expect(parseEnv(''), isEmpty);
    expect(parseEnv('LANG=en_US.UTF-8\n\nEDITOR=vim -u NONE'), {'LANG': 'en_US.UTF-8', 'EDITOR': 'vim -u NONE'});
    expect(parseEnv('A=b=c'), {'A': 'b=c'}, reason: 'only the first = separates');
    expect(parseEnv('no equals sign'), isNull);
    expect(parseEnv('1BAD=x'), isNull);
    expect(parseEnv(formatEnv({'X': '1', 'Y': ''})), {'X': '1', 'Y': ''});
  });

  testWidgets('a host leaves fields empty and takes its group settings', (tester) async {
    final dir = (await tester.runAsync(() => Directory.systemTemp.createTemp('tildeck-hosts')))!;
    addTearDown(() => dir.delete(recursive: true));
    final vault = (await tester.runAsync(() async {
      final v = Vault(crypto: VaultCrypto.load(), resolveFile: () async => File('${dir.path}/vault.json'));
      await v.load();
      await v.create('orange-kettle-winter-42');
      await v.put(const KeyEntry(id: 'k1', name: 'Ops key', privateKey: 'KEY-MATERIAL'));
      await v.put(const SnippetEntry(id: 's1', name: 'Hello', command: 'echo hi'));
      await v.put(
        const GroupEntry(
          id: 'g1',
          name: 'Production',
          username: 'ops',
          keyId: 'k1',
          startupSnippetId: 's1',
          env: {'LANG': 'C', 'TEAM': 'infra'},
        ),
      );
      return v;
    }))!;
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );

    const bare = HostEntry(
      id: 'h2',
      name: 'Db',
      group: 'Production',
      host: 'db.example.com',
      username: '',
      auth: HostAuth.key,
      env: {'LANG': 'he_IL.UTF-8'},
    );
    final target = (await connectionTargetFor(context, vault, bare))!;
    expect(target.username, 'ops');
    expect(target.privateKey, 'KEY-MATERIAL');
    expect(target.startupCommand, 'echo hi');
    expect(target.environment, {'LANG': 'he_IL.UTF-8', 'TEAM': 'infra'}, reason: "the host's own value wins");

    const own = HostEntry(
      id: 'h3',
      name: 'Own',
      group: 'Production',
      host: 'own.example.com',
      username: 'root',
      auth: HostAuth.key,
      keyId: 'k1',
    );
    expect((await connectionTargetFor(context, vault, own))!.username, 'root');
  });
}
