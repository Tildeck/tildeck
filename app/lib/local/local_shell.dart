import 'dart:io';

import 'package:flutter/foundation.dart';

enum LocalShellKind { pwsh, windowsPowerShell, cmd, wsl, posix }

/// A shell on this computer that a local terminal can run.
class LocalShell {
  const LocalShell(this.kind, this.executable, [this.arguments = const []]);

  final LocalShellKind kind;
  final String executable;
  final List<String> arguments;
}

/// Whether this platform has local terminals: the desktop ones. Widget
/// tests run as Android unless they say otherwise.
bool get localTerminalsSupported => switch (defaultTargetPlatform) {
  TargetPlatform.windows || TargetPlatform.linux || TargetPlatform.macOS => true,
  _ => false,
};

/// The shells found on this computer, the preferred one first. On Windows:
/// PowerShell 7, Windows PowerShell, Command Prompt, and WSL when installed.
/// Elsewhere: the user's login shell.
List<LocalShell> findLocalShells({
  bool? windows,
  Map<String, String>? environment,
  bool Function(String path)? exists,
}) {
  final env = environment ?? Platform.environment;
  final isFile = exists ?? (path) => File(path).existsSync();
  if (!(windows ?? Platform.isWindows)) {
    final shell = env['SHELL'];
    final path = shell != null && isFile(shell) ? shell : '/bin/sh';
    // A login shell reads the user's profile, as a terminal app's does.
    return [
      LocalShell(LocalShellKind.posix, path, const ['-l']),
    ];
  }

  // Windows keys are case-insensitive; the map from Dart is not.
  String? get(String name) {
    for (final e in env.entries) {
      if (e.key.toUpperCase() == name) return e.value;
    }
    return null;
  }

  final systemRoot = get('SYSTEMROOT') ?? r'C:\Windows';
  final system32 = '$systemRoot\\System32';
  final shells = <LocalShell>[];

  String? pwsh;
  for (final dir in (get('PATH') ?? '').split(';')) {
    if (dir.trim().isEmpty) continue;
    final candidate = '${dir.trim().replaceAll(RegExp(r'\\+$'), '')}\\pwsh.exe';
    if (isFile(candidate)) {
      pwsh = candidate;
      break;
    }
  }
  final programFiles = get('PROGRAMFILES');
  if (pwsh == null && programFiles != null && isFile('$programFiles\\PowerShell\\7\\pwsh.exe')) {
    pwsh = '$programFiles\\PowerShell\\7\\pwsh.exe';
  }
  if (pwsh != null) shells.add(LocalShell(LocalShellKind.pwsh, pwsh, const ['-NoLogo']));

  final powershell = '$system32\\WindowsPowerShell\\v1.0\\powershell.exe';
  if (isFile(powershell)) shells.add(LocalShell(LocalShellKind.windowsPowerShell, powershell, const ['-NoLogo']));

  final cmd = get('COMSPEC') ?? '$system32\\cmd.exe';
  if (isFile(cmd)) shells.add(LocalShell(LocalShellKind.cmd, cmd));

  final wsl = '$system32\\wsl.exe';
  if (isFile(wsl)) shells.add(LocalShell(LocalShellKind.wsl, wsl));
  return shells;
}

/// Where a local terminal starts: the user's home folder.
String? localHome([Map<String, String>? environment]) {
  final env = environment ?? Platform.environment;
  return env['USERPROFILE'] ?? env['HOME'];
}
