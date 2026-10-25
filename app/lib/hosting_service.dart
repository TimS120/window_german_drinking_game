import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The UI isolate validates moves even while its Android activity is paused.
/// A foreground service keeps that process eligible for background execution.
class HostingService {
  static bool _running = false;
  static const _channel = MethodChannel('window/hosting');
  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<void> start(String roomCode) async {
    if (_supported) {
      await _channel.invokeMethod<void>('start', {'roomCode': roomCode});
      _running = true;
    }
  }

  static Future<void> stop() async {
    if (_supported && _running) {
      await _channel.invokeMethod<void>('stop');
      _running = false;
    }
  }
}
