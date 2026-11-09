import 'dart:js_interop';

@JS('window.open')
external void _open(JSString url, JSString target);

void openExternal(String url) => _open(url.toJS, '_blank'.toJS);
