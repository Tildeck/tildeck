import 'dart:async';

import 'package:flutter/foundation.dart';

import '../vault/vault.dart';
import 'sync_server.dart';

/// Why the last sync did not finish. Each maps to a localized message.
enum SyncProblem {
  /// No answer from the server; it runs again later.
  unreachable,

  /// The account's email address is not confirmed yet.
  emailNotConfirmed,

  /// The device was revoked, or its token expired: sign in again.
  signedOut,

  /// This app and the server speak different sync protocols.
  unsupportedProtocol,

  /// Anything else the server refused.
  failed,
}

/// Keeps the vault in step with the sync server (docs/security-model.md,
/// "Sync"): it pulls before it pushes, after unlock, a few seconds after a
/// local change, every minute while the vault is open, and on request.
class SyncEngine extends ChangeNotifier {
  SyncEngine({
    required this.vault,
    SyncServer Function(String address)? serverFor,
    this.changeDelay = const Duration(seconds: 2),
    this.interval = const Duration(minutes: 1),
  }) : _serverFor = serverFor ?? SyncServer.new,
       _lastStatus = vault.status {
    vault.addListener(_onVault);
  }

  final Vault vault;
  final SyncServer Function(String address) _serverFor;
  final Duration changeDelay;
  final Duration interval;

  /// The most changes one push carries: the server's limit.
  static const pushLimit = 500;

  /// Rounds of pushing per sync: a conflict won locally is pushed again in
  /// the next round, so one round is rarely followed by more than one.
  static const _pushRounds = 3;

  bool _running = false;
  bool _again = false;
  bool _disposed = false;
  Timer? _changeTimer;
  Timer? _intervalTimer;
  VaultStatus _lastStatus;

  bool get running => _running;
  DateTime? lastSynced;
  SyncProblem? problem;

  SyncServer? _server;
  String? _serverAddress;

  SyncServer serverFor(String address) {
    if (_serverAddress != address) {
      _server = _serverFor(address);
      _serverAddress = address;
    }
    return _server!;
  }

  void _onVault() {
    final status = vault.status;
    final opened = status == VaultStatus.unlocked && _lastStatus != VaultStatus.unlocked;
    _lastStatus = status;
    if (status != VaultStatus.unlocked || vault.account == null) {
      _changeTimer?.cancel();
      _intervalTimer?.cancel();
      _intervalTimer = null;
      return;
    }
    _intervalTimer ??= Timer.periodic(interval, (_) => sync());
    if (opened) {
      sync();
    } else if (!_running && problem == null && vault.dirtyRecords.isNotEmpty) {
      // A failed sync waits for the next interval instead of retrying on
      // every change.
      _changeTimer?.cancel();
      _changeTimer = Timer(changeDelay, sync);
    }
  }

  /// Runs one sync. A request while one runs queues exactly one more, and
  /// completes when that one has run too.
  Future<void> sync() {
    final current = _current;
    if (current != null) {
      _again = true;
      return current;
    }
    if (_disposed) return Future.value();
    return _current = _run().whenComplete(() => _current = null);
  }

  Future<void>? _current;

  Future<void> _run() async {
    _running = true;
    _changeTimer?.cancel();
    notifyListeners();
    try {
      do {
        _again = false;
        await _syncOnce();
      } while (_again && !_disposed);
    } finally {
      _running = false;
      // Disposed while a request was on its way: nobody is listening.
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _syncOnce() async {
    final account = vault.account;
    if (vault.status != VaultStatus.unlocked || account == null) return;
    final server = serverFor(account.server);
    try {
      var more = true;
      while (more) {
        final page = await server.pull(account.token, vault.cursor);
        await vault.applyPulled(page.records, page.revision);
        more = page.more;
      }
      for (var round = 0; round < _pushRounds; round++) {
        final dirty = vault.dirtyRecords;
        if (dirty.isEmpty) break;
        for (var i = 0; i < dirty.length; i += pushLimit) {
          final chunk = dirty.sublist(i, i + pushLimit > dirty.length ? dirty.length : i + pushLimit);
          final result = await server.push(account.token, chunk);
          await vault.applyPushed(accepted: result.accepted, conflicts: result.conflicts);
        }
      }
      problem = null;
      lastSynced = DateTime.now();
    } on SyncFailure catch (e) {
      problem = switch ((e.status, e.code)) {
        (_, 'email_not_verified') => SyncProblem.emailNotConfirmed,
        (_, 'unsupported_protocol') => SyncProblem.unsupportedProtocol,
        (401, _) => SyncProblem.signedOut,
        _ when e.unreachable => SyncProblem.unreachable,
        _ => SyncProblem.failed,
      };
    } on StateError {
      // The vault locked while syncing; the next unlock syncs again.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    vault.removeListener(_onVault);
    _changeTimer?.cancel();
    _intervalTimer?.cancel();
    super.dispose();
  }
}
