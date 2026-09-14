import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Browsers load Flutter assets directly; they do not have a native temp-file
/// cache to invalidate.
Future<OrtSession> createWindowPolicySession(
  OnnxRuntime runtime,
  String assetKey,
) => runtime.createSessionFromAsset(assetKey);
