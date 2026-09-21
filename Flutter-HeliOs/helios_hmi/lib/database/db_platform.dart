export 'db_platform_stub.dart'
    if (dart.library.io) 'db_platform_native.dart'
    if (dart.library.js_interop) 'db_platform_web.dart';