import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Browsers load Flutter assets directly; they do not have a native temp-file
/// cache to invalidate. Flutter's web build places a logical asset such as
/// `assets/models/window_policy.onnx` under the physical `assets/` directory,
/// so ONNX Runtime must receive the browser-visible path, not the logical key.
Future<OrtSession> createWindowPolicySession(
  OnnxRuntime runtime,
  String assetKey,
) => runtime.createSession('assets/$assetKey');
