import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Creates a native session from a content-addressed temporary model file.
///
/// `flutter_onnxruntime.createSessionFromAsset` caches solely by filename.
/// That kept an old `window_policy.onnx` alive after a new build. The compact
/// fingerprint below changes whenever the bundled bytes change, so Windows,
/// Android, and iOS always load the deployed model version.
Future<OrtSession> createWindowPolicySession(
  OnnxRuntime runtime,
  String assetKey,
) async {
  final ByteData data = await rootBundle.load(assetKey);
  final Uint8List bytes = data.buffer.asUint8List(
    data.offsetInBytes,
    data.lengthInBytes,
  );
  final String fingerprint = _fingerprint(bytes);
  final File modelFile = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'window_policy_$fingerprint.onnx',
  );
  if (!await modelFile.exists() || await modelFile.length() != bytes.length) {
    final File temporary = File('${modelFile.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await modelFile.exists()) await modelFile.delete();
    await temporary.rename(modelFile.path);
  }
  return runtime.createSession(modelFile.path);
}

String _fingerprint(Uint8List bytes) {
  // FNV-1a 64-bit: sufficient for cache identity, without another package.
  int value = 0xcbf29ce484222325;
  for (final int byte in bytes) {
    value ^= byte;
    value = (value * 0x100000001b3) & 0xffffffffffffffff;
  }
  return '${bytes.length.toRadixString(16)}-${value.toRadixString(16)}';
}
