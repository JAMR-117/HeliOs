export 'mqtt_client_stub.dart'
    if (dart.library.io) 'mqtt_client_native.dart'
    if (dart.library.js_interop) 'mqtt_client_browser.dart'
    if (dart.library.html) 'mqtt_client_browser.dart';
