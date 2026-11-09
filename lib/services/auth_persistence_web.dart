import 'dart:js_interop';

@JS('localStorage.getItem')
external JSString? _getItem(JSString key);

@JS('localStorage.setItem')
external void _setItem(JSString key, JSString value);

const _key = 'farmacia_stay_signed_in';

String? readStayFlag() => _getItem(_key.toJS)?.toDart;

void writeStayFlag(bool stay) {
  _setItem(_key.toJS, (stay ? '1' : '0').toJS);
}

@JS('localStorage')
external JSObject get _local;
@JS('sessionStorage')
external JSObject get _session;

extension type _Storage(JSObject o) implements JSObject {
  external int get length;
  external JSString? key(int i);
  external void removeItem(JSString k);
}

void _wipe(_Storage s) {
  final keys = <String>[];
  for (var i = 0; i < s.length; i++) {
    final k = s.key(i)?.toDart;
    if (k != null && (k.startsWith('firebase:') || k == _key)) keys.add(k);
  }
  for (final k in keys) { s.removeItem(k.toJS); }
}

/// farmacia-clear-session: cancella ogni traccia della sessione Firebase nel browser.
void clearStoredSession() {
  try { _wipe(_Storage(_local)); } catch (_) {}
  try { _wipe(_Storage(_session)); } catch (_) {}
  _setItem(_key.toJS, '0'.toJS);
}
