import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:tildeck_api/api.dart';

/// The sync protocol this app speaks. Must match the server's
/// PROTOCOL_VERSION (server/app/protocol.py) for sync to be allowed.
const int kProtocolVersion = 1;

/// Why a server check failed. Each one maps to a localized message.
enum ServerProblem {
  invalidAddress,
  insecureAddress,
  unreachable,
  notTildeck,
  unsupportedProtocol,
  databaseUnavailable,
}

sealed class ServerCheckResult {
  const ServerCheckResult();
}

class ServerReady extends ServerCheckResult {
  const ServerReady(this.info);
  final ServerInfo info;
}

class ServerFailed extends ServerCheckResult {
  const ServerFailed(this.problem);
  final ServerProblem problem;
}

/// Checks that an address is a reachable Tildeck server this app can sync
/// with: the identity endpoint answers, the protocol matches, and the server
/// can reach its database.
class ServerChecker {
  ServerChecker({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// The normalized base address, or null when the input is not an
  /// absolute http(s) address.
  static Uri? parseAddress(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) return null;
    final path = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
    return uri.replace(path: path, query: null, fragment: null);
  }

  /// Whether [address] may be used: https, or http only to this computer
  /// (a development server). Over plain http elsewhere, the keys that
  /// prove the master password and the account's tokens travel readable.
  static bool isSecure(Uri address) => address.scheme == 'https' || _isLoopback(address.host);

  static bool _isLoopback(String host) {
    final h = host.toLowerCase();
    if (h == 'localhost' || h == '::1' || h == '[::1]') return true;
    final ip = InternetAddress.tryParse(h);
    return ip != null && ip.isLoopback;
  }

  Future<ServerCheckResult> check(String address) async {
    final base = parseAddress(address);
    if (base == null) return const ServerFailed(ServerProblem.invalidAddress);
    if (!isSecure(base)) return const ServerFailed(ServerProblem.insecureAddress);

    final client = ApiClient(basePath: base.toString())..client = _client;
    final api = HealthApi(client);
    final ServerInfo? info;
    try {
      info = await api.getServerInfo();
    } on ApiException catch (e) {
      // The generated client reports a failed connection as an exception
      // with an inner cause; a server error means it is there but broken.
      final noAnswer = e.innerException != null || e.code >= 500;
      return ServerFailed(noAnswer ? ServerProblem.unreachable : ServerProblem.notTildeck);
    } catch (_) {
      // Something answered with a body that is not the identity document.
      return const ServerFailed(ServerProblem.notTildeck);
    }
    if (info == null || info.name != ServerInfoNameEnum.tildeck) {
      return const ServerFailed(ServerProblem.notTildeck);
    }
    if (info.protocolVersion != kProtocolVersion) {
      return const ServerFailed(ServerProblem.unsupportedProtocol);
    }

    // Readiness answers 503 with a stable error code when the database is
    // down; that is a state to report, so read the body at any status.
    Readiness? ready;
    try {
      final response = await api.getReadinessWithHttpInfo();
      ready = await client.deserializeAsync(response.body, 'Readiness') as Readiness?;
    } catch (_) {
      ready = null;
    }
    if (ready?.error == ErrorCode.databaseUnavailable) {
      return const ServerFailed(ServerProblem.databaseUnavailable);
    }
    return ServerReady(info);
  }
}
