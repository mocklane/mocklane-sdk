// Platform labels for dart:io runtimes (Flutter mobile/desktop, CLI).

import 'dart:io';

Map<String, String> platformDefaultLabels() {
  final os = Platform.operatingSystem;
  if (os == 'android' || os == 'ios') {
    return {'os': os, 'deviceName': os == 'android' ? 'Android' : 'iOS'};
  }
  final host = Platform.localHostname.trim();
  return {'os': os, 'deviceName': host.isEmpty ? os : host};
}
