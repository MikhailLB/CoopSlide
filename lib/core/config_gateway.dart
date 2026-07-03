import 'dart:convert';

import '../data/server_payload.dart';
import '../setup/project_constants.dart';
import 'outbound_http.dart';
import 'session_store.dart';

class ConfigGateway {
  final SessionStore _store;

  ConfigGateway(this._store);

  Future<ServerPayload> requestShell(Map<String, dynamic> body) async {
    final endpoint = ProjectConstants.configEndpoint;
    if (endpoint.isEmpty) {
      return ServerPayload.failure('Endpoint missing');
    }

    try {
      final uri = Uri.parse(endpoint);
      final response = await outboundHttp
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final map = jsonDecode(response.body) as Map<String, dynamic>;
        final payload = ServerPayload.fromMap(map);
        if (payload.accepted && payload.targetUrl != null) {
          await _store.writePortalUrl(payload.targetUrl!);
          if (payload.validUntil != null) {
            await _store.writePortalExpiry(payload.validUntil!);
          }
        }
        return payload;
      }
      return ServerPayload.failure('HTTP ${response.statusCode}');
    } catch (e) {
      return ServerPayload.failure('$e');
    }
  }

  Future<String?> cachedPortalUrl() => _store.readPortalUrl();
}
