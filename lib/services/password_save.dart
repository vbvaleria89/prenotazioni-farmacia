import 'password_save_stub.dart'
    if (dart.library.html) 'password_save_web.dart' as impl;

/// Dopo un login riuscito: chiede al browser di salvare email e password.
/// Su Chrome/Edge usa la Credential Management API; altrove un form HTML nativo.
Future<bool> storeBrowserPassword(String email, String password) =>
    impl.storeBrowserPassword(email, password);

/// All'apertura del login, tenta di precompilare le credenziali salvate.
Future<({String email, String password})?> getSavedBrowserPassword() =>
    impl.getSavedBrowserPassword();
