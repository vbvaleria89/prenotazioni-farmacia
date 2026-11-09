import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// Web-only options (registered from Firebase console). Run `flutterfire configure` to add Android/iOS.
class DefaultFirebaseOptions {
  static const FirebaseOptions currentPlatform = web;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDgAhnDHt3Kt-8j6HHmREGFfVncJLTsoUA',
    appId: '1:444833221252:web:7e81ce47ca825fc01750d1',
    messagingSenderId: '444833221252',
    projectId: 'farmacia-san-ciro-prenota',
    authDomain: 'farmacia-san-ciro-prenota.firebaseapp.com',
    storageBucket: 'farmacia-san-ciro-prenota.firebasestorage.app',
  );
}
