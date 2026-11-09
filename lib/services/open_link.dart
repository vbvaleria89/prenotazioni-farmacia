import 'open_link_stub.dart' if (dart.library.html) 'open_link_web.dart' as launcher;

void openExternal(String url) => launcher.openExternal(url);
