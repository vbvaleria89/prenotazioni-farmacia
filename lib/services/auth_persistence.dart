import 'package:firebase_auth/firebase_auth.dart';
import 'auth_persistence_stub.dart'
    if (dart.library.html) 'auth_persistence_web.dart' as stay_store;

/// Default sì. Solo il valore esplicito `0` spegne «Resta connesso».
bool preferLocalPersistence(String? stored) => stored != '0';

bool readStaySignedIn() => preferLocalPersistence(stay_store.readStayFlag());

void rememberStaySignedIn(bool stay) => stay_store.writeStayFlag(stay);

/// Esci = sessione cancellata del tutto (Firebase + storage del browser).
Future<void> hardSignOut() async {
  try { await FirebaseAuth.instance.signOut(); } catch (_) {}
  stay_store.clearStoredSession();
  // ignore: avoid_print
  print('farmacia-clear-session');
}

/// true mentre è in corso un login email/password: blocca l'accesso anonimo automatico.
bool authLoginInProgress = false;
