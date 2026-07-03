import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

class NetSensor {
  final Connectivity _plugin = Connectivity();

  static const _liveInterfaces = {
    ConnectivityResult.wifi,
    ConnectivityResult.mobile,
    ConnectivityResult.ethernet,
    ConnectivityResult.vpn,
    ConnectivityResult.bluetooth,
    ConnectivityResult.other,
  };

  Stream<List<ConnectivityResult>> get statusStream =>
      _plugin.onConnectivityChanged;

  Future<bool> isOnline() async {
    final results = await _plugin.checkConnectivity();
    if (!results.any(_liveInterfaces.contains)) return false;

    try {
      final answer = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(seconds: 7));
      return answer.isNotEmpty && answer.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
