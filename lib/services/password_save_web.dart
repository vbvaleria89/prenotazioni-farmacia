import 'dart:js_interop';

@JS('farmaciaStorePassword')
external JSPromise<JSBoolean> _store(JSString email, JSString password);

@JS('farmaciaGetSavedPassword')
external JSPromise<JSAny?> _get();

extension type _SavedCred(JSObject o) implements JSObject {
  external JSString? get email;
  external JSString? get password;
}

Future<bool> storeBrowserPassword(String email, String password) async {
  final trimmed = email.trim();
  if (trimmed.isEmpty || password.isEmpty) return false;
  try {
    final result = await _store(trimmed.toJS, password.toJS).toDart;
    return result.toDart;
  } catch (_) {
    return false;
  }
}

Future<({String email, String password})?> getSavedBrowserPassword() async {
  try {
    final raw = await _get().toDart;
    if (raw == null) return null;
    final cred = _SavedCred(raw as JSObject);
    final mail = cred.email?.toDart.trim() ?? '';
    if (mail.isEmpty) return null;
    return (email: mail, password: cred.password?.toDart ?? '');
  } catch (_) {
    return null;
  }
}
