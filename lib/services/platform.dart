import 'package:flutter/foundation.dart';

/// Whether this is the Android app, where the native platform channels
/// (updates, background session - see android/.../MainActivity.kt) exist.
bool get isAndroidApp =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
