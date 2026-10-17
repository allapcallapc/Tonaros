import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Whether this browser has `navigator.vibrate` (Chrome on Android does;
/// Safari doesn't).
bool webCanVibrate() => (web.window.navigator as JSObject).has('vibrate');

/// [pattern] in the browser's convention: see toBrowserPattern.
void webVibrate(List<int> pattern) {
  if (pattern.isEmpty) return;
  web.window.navigator.vibrate([for (final ms in pattern) ms.toJS].toJS);
}
