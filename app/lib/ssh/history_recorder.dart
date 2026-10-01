import '../vault/models.dart';
import '../vault/vault.dart';
import 'terminal_session.dart';

/// Writes [session] to the vault's history once it connects or fails, and
/// its end time when it closes. Nothing is written while the vault is
/// locked.
void recordHistory(Vault vault, TerminalSession session, {DateTime Function() now = DateTime.now}) {
  ConnectionLogEntry? entry;
  void onChange() {
    if (vault.status != VaultStatus.unlocked) return;
    if (entry == null && session.state != SessionState.connecting) {
      var first = ConnectionLogEntry(
        id: vault.newId(),
        hostId: session.target.hostId,
        label: session.target.label,
        startedAt: now(),
        device: vault.account?.deviceName,
      );
      if (session.state == SessionState.closed) first = first.ended(now(), failed: session.problem != null);
      entry = first;
      vault.logConnection(first);
    } else if (entry != null && entry!.endedAt == null && session.state == SessionState.closed) {
      final last = entry!.ended(now(), failed: session.problem != null);
      entry = last;
      vault.put(last);
      session.removeListener(onChange);
    }
  }

  session.addListener(onChange);
}
