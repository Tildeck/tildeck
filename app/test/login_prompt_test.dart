import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tildeck/l10n/app_localizations.dart';
import 'package:tildeck/ssh/ssh_connector.dart';
import 'package:tildeck/theme.dart';
import 'package:tildeck/ui/login_prompt_dialog.dart';

SSHUserInfoRequest request(List<(String, bool)> prompts) =>
    SSHUserInfoRequest('', '', [for (final (text, echo) in prompts) SSHUserInfoPrompt(text, echo)]);

void main() {
  test('password prompts are told apart from one-time codes', () {
    for (final text in ['Password:', "deploy@web-01's password: ", 'Passcode:', '(ops@db) Password:']) {
      expect(SshConnector.isPasswordPrompt(text), isTrue, reason: text);
    }
    for (final text in [
      'Verification code:',
      'One-time password:',
      'OTP:',
      'Duo passcode or option (1-2):',
      'Token:',
    ]) {
      expect(SshConnector.isPasswordPrompt(text), isFalse, reason: text);
    }
  });

  test('the saved password answers the password prompt once; the user answers the code', () async {
    var used = false;
    final asked = <String>[];
    Future<List<String>?> ask(List<SSHUserInfoPrompt> prompts) async {
      asked.addAll(prompts.map((p) => p.promptText));
      return ['123456'];
    }

    // Password and code in one request (pam_unix then pam_google_authenticator).
    final both = await SshConnector.answerLogin(
      request([('Password: ', false), ('Verification code: ', false)]),
      password: 'secret',
      passwordUsed: used,
      onPasswordUsed: () => used = true,
      ask: ask,
    );
    expect(both, ['secret', '123456']);
    expect(asked, ['Verification code: ']);
    expect(used, isTrue);

    // The server asks for the password again: the saved one was refused, so
    // it is not sent again; the user is asked.
    asked.clear();
    final again = await SshConnector.answerLogin(
      request([('Password: ', false)]),
      password: 'secret',
      passwordUsed: used,
      onPasswordUsed: () => used = true,
      ask: ask,
    );
    expect(again, ['123456']);
    expect(asked, ['Password: ']);
  });

  test('without anyone to ask, only a password prompt is answered; a cancel answers nothing', () async {
    final noAsk = await SshConnector.answerLogin(
      request([('Verification code:', false)]),
      password: 'secret',
      passwordUsed: false,
      onPasswordUsed: () {},
    );
    expect(noAsk, isNull);

    final plain = await SshConnector.answerLogin(
      request([('Password:', false)]),
      password: 'secret',
      passwordUsed: false,
      onPasswordUsed: () {},
    );
    expect(plain, ['secret']);

    final cancelled = await SshConnector.answerLogin(
      request([('Verification code:', false)]),
      password: null,
      passwordUsed: false,
      onPasswordUsed: () {},
      ask: (_) async => null,
    );
    expect(cancelled, isNull);

    // A request with nothing to answer (an information message).
    expect(
      await SshConnector.answerLogin(request([]), password: null, passwordUsed: false, onPasswordUsed: () {}),
      isEmpty,
    );
  });

  testWidgets("the dialog shows the server's words and hides what it asks to hide", (tester) async {
    late BuildContext context;
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
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );
    final answer = showLoginPromptDialog(
      context,
      target: const ConnectionTarget(host: 'web-01.example.com', port: 22, username: 'deploy'),
      name: '',
      instruction: 'Open your authenticator app.',
      prompts: [SSHUserInfoPrompt('Verification code: ', false), SSHUserInfoPrompt('Remember me (yes/no): ', true)],
    );
    await tester.pumpAndSettle();
    expect(find.text('Signing in as deploy@web-01.example.com. The server asked:'), findsOneWidget);
    expect(find.text('Open your authenticator app.'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('loginPrompt-0'))).obscureText, isTrue);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('loginPrompt-1'))).obscureText, isFalse);
    await tester.enterText(find.byKey(const ValueKey('loginPrompt-0')), '654321');
    await tester.enterText(find.byKey(const ValueKey('loginPrompt-1')), 'no');
    await tester.tap(find.byKey(const ValueKey('loginPromptContinue')));
    await tester.pumpAndSettle();
    expect(await answer, ['654321', 'no']);
  });
}
