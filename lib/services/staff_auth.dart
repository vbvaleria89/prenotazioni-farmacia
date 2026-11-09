import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/settings.dart';
import 'auth_persistence.dart';

/// Login dipendenti (email/password). Il ruolo arriva da `employees/{uid}`.
class StaffAuth {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Future<Employee> signIn(String email, String password) async {
    authLoginInProgress = true;
    final UserCredential cred;
    try {
      cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
    } finally {
      authLoginInProgress = false;
    }
    try {
      final doc = await _db.doc('employees/${cred.user!.uid}').get();
      if (!doc.exists) {
        throw StateError('Accesso riservato al personale. Per le tue prenotazioni usa Area personale.');
      }
      final e = Employee.fromDoc(doc);
      if (!e.attivo) { throw StateError('Account disattivato'); }
      return e;
    } on FirebaseException catch (e) {
      // Errore transitorio di lettura: non cancelliamo la sessione appena creata.
      if (e.code == 'permission-denied') {
        throw StateError('Accesso riservato al personale. Per le tue prenotazioni usa Area personale.');
      }
      throw StateError('Accesso non riuscito (${e.code})');
    }
  }

  Future<Employee?> profile() async {
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) throw StateError('Accedi al tuo account');
    final doc = await _db.doc('employees/${current.uid}').get();
    return doc.exists ? Employee.fromDoc(doc) : null;
  }

  /// Nessun parametro uid/ruolo: il dipendente può cambiare solo il proprio nome.
  Future<void> updateProfile({required String nome}) async {
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) throw StateError('Accedi al tuo account');
    final name = nome.trim();
    if (name.isEmpty || name.length >= 100) throw StateError('Nome non valido');
    await _db.doc('employees/${current.uid}').update({'nome': name});
  }

  Future<void> signOut() => hardSignOut();

  Stream<List<Employee>> employees() =>
      _db.collection('employees').snapshots().map((q) => q.docs.map(Employee.fromDoc).toList()..sort((a, b) => a.nome.compareTo(b.nome)));
}
