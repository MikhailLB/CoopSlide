import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/route_decision.dart';

class SessionStore {
  static const _modeKey = 'route_mode';
  static const _portalKey = 'portal_u';
  static const _expiryKey = 'portal_exp';
  static const _alertsGrantedKey = 'alerts_granted';
  static const _alertsSnoozeKey = 'alerts_snooze_ts';
  static const _alertsBlockedKey = 'alerts_os_blocked';
  static const _pushTargetKey = 'push_target_u';

  late SharedPreferences _prefs;
  final FlutterSecureStorage _vault = const FlutterSecureStorage();

  Future<void> warmUp() async {
    _prefs = await SharedPreferences.getInstance();
  }

  RouteDecision readRoute() =>
      RouteDecision.parse(_prefs.getString(_modeKey));

  Future<void> writeRoute(RouteDecision mode) async {
    await _prefs.setString(_modeKey, mode.persistToken());
  }

  Future<String?> readPortalUrl() => _vault.read(key: _portalKey);

  Future<void> writePortalUrl(String url) async {
    await _vault.write(key: _portalKey, value: url);
  }

  int? readPortalExpiry() => _prefs.getInt(_expiryKey);

  Future<void> writePortalExpiry(int ts) async {
    await _prefs.setInt(_expiryKey, ts);
  }

  bool portalExpired() {
    final exp = readPortalExpiry();
    if (exp == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= exp;
  }

  bool alertsAlreadyGranted() =>
      _prefs.getBool(_alertsGrantedKey) ?? false;

  Future<void> markAlertsGranted(bool value) async {
    await _prefs.setBool(_alertsGrantedKey, value);
  }

  bool alertsBlockedByOs() =>
      _prefs.getBool(_alertsBlockedKey) ?? false;

  Future<void> markAlertsBlockedByOs() async {
    await _prefs.setBool(_alertsBlockedKey, true);
  }

  int? readAlertsSnoozeUntil() => _prefs.getInt(_alertsSnoozeKey);

  Future<void> writeAlertsSnoozeUntil(int ts) async {
    await _prefs.setInt(_alertsSnoozeKey, ts);
  }

  bool shouldPromptForAlerts() {
    if (alertsAlreadyGranted()) return false;
    if (alertsBlockedByOs()) return false;
    final snooze = readAlertsSnoozeUntil();
    if (snooze == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return now >= snooze;
  }

  Future<String?> peekPushTarget() => _vault.read(key: _pushTargetKey);

  Future<void> stashPushTarget(String? url) async {
    if (url == null || url.isEmpty) {
      await _vault.delete(key: _pushTargetKey);
    } else {
      await _vault.write(key: _pushTargetKey, value: url);
    }
  }

  Future<String?> takePushTarget() async {
    final url = await peekPushTarget();
    if (url != null) await _vault.delete(key: _pushTargetKey);
    return url;
  }
}
