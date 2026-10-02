import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/ssh/mobaxterm_sessions.dart';
import 'package:tildeck/vault/host_csv.dart';

final sessions = [
  r'[Bookmarks]',
  r'SubRep=',
  r'ImgNum=42',
  r'Router=#98#1%10.0.0.1%23%admin%%2%%%%%0%0%%1080%#MobaFont%10%0%0%-1%15%236,236,236%30,30,30%180,180,192%0%-1%0%%xterm%-1%-1%_Std_Colors_0_%80%24%0%1%-1%<none>%%0%1%-1#0# #-1',
  r'',
  r'[Bookmarks_1]',
  r'SubRep=Production\Web',
  r'ImgNum=41',
  r'web01=#109#0%web01.example.com%22%deploy%%-1%-1%%%22%%0%0%0%_ProfileDir_\.ssh\id_ed25519%%-1%0%0%0%%1080%%0%0%1#MobaFont%10%0%0%-1%15%236,236,236%30,30,30%180,180,192%0%-1%0%%xterm%-1%-1%_Std_Colors_0_%80%24%0%1%-1%<none>%%0%1%-1#0# #-1',
  r'web02=#109#0%web02.example.com%2222%%%-1%-1%%%22%%0%0%0%%%-1%0%0%0%%1080%%0%0%1#MobaFont%10#0# #-1',
  r'Desktop=#91#4%10.0.0.9%3389%%-1%0%0%0%-1%0%0%-1#MobaFont%10#0# #-1',
  r'',
  r'[Bookmarks_2]',
  r'SubRep=Lab',
  r'ImgNum=41',
  r'web01=#109#0%lab-web.local%22%root%%-1%-1#MobaFont%10#0# #-1',
].join('\n');

void main() {
  test("MobaXterm's sessions are recognized, and not taken for a CSV", () {
    expect(looksLikeMobaXterm(sessions), isTrue);
    expect(looksLikeMobaXterm('[Bookmarks]\nSubRep=\n'), isFalse, reason: 'no sessions');
    expect(looksLikeMobaXterm('Host web\n  HostName web.example.com\n'), isFalse);
    expect(looksLikeMobaXterm('name,host,port\nweb,web.example.com,22\n'), isFalse);
    expect(looksLikeHostsCsv(sessions), isFalse);
  });

  test('SSH and Telnet sessions come with their folders; other kinds are left out', () {
    final hosts = parseMobaXterm(sessions);
    expect(
      [for (final h in hosts) (h.alias, h.address, h.port, h.user, h.group, h.telnet)],
      [
        ('Router', '10.0.0.1', 23, 'admin', '', true),
        ('web01', 'web01.example.com', 22, 'deploy', 'Production/Web', false),
        ('web02', 'web02.example.com', 2222, null, 'Production/Web', false),
        ('web01 (2)', 'lab-web.local', 22, 'root', 'Lab', false),
      ],
      reason: 'no RDP; the same name twice gets a number',
    );
    expect(hosts.every((h) => h.identityFiles.isEmpty), isTrue, reason: "MobaXterm's key paths are its own");
  });
}
