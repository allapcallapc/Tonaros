// The browser's Vibration API, for the web build (the vibration package has
// no web implementation). A no-op stub everywhere else.
export 'web_vibration_stub.dart'
    if (dart.library.js_interop) 'web_vibration_web.dart';
