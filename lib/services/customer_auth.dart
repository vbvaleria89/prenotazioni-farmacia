import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/customer.dart';
import '../models/codice_fiscale.dart';
import '../models/personal_role.dart';
import '../models/settings.dart';
import 'auth_persistence.dart';

final customerAuth = CustomerAuth();

/// Esito del login in Area personale: cliente, oppure dipendente da mandare allo staff.
class PersonalSession {
  final PersonalRole role;
  final Employee? employee;
  const PersonalSession.customer() : role = PersonalRole.customer, employee = null;
  const PersonalSession.staff(this.employee) : role = PersonalRole.staff;
}

/// Login del cliente finale. Un dipendente che entra da qui viene riconosciuto e non trattato da cliente.
class CustomerAuth {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get user => _auth.currentUser;
  bool get isSignedInCustomer => user != null && !(user!.isAnonymous);

  /// Attende il ripristino della sessione (su web currentUser può arrivare un attimo dopo).
  Future<User?> restoredUser() => _auth.authStateChanges().first;

  /// Su web: LOCAL solo se «Resta connesso», altrimenti sessione della scheda (SESSION).
  Future<void> usePersistence({required bool staySignedIn}) async {
    try { await applyAuthPersistence(staySignedIn: staySignedIn); } catch (_) {}
  }

  Future<PersonalSession> signIn(String email, String password, {bool staySignedIn = false}) async {
    authLoginInProgress = true;
    UserCredential cred;
    try {
      // SESSION di default prima del signIn (più sicuro sulle postazioni condivise).
      // Niente signOut dell'anonimo: signInWithEmailAndPassword lo sostituisce
      // e si evita la gara con ensureClientAuth che ricreava un anonimo.
      await usePersistence(staySignedIn: staySignedIn);
      cred = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    } finally {
      authLoginInProgress = false;
    }
    final session = await _sessionFor(cred.user!.uid);
    // Staff/admin non restano persistenti, anche se la casella era spuntata.
    if (session.role == PersonalRole.staff) {
      await usePersistence(staySignedIn: false);
    }
    return session;
  }

  Future<PersonalSession> sessionForCurrentUser() async {
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) throw StateError('Accedi con email e password');
    return _sessionFor(current.uid);
  }

  static const adminEmail = 'admin@sanciro.local';
  static const staffEmail = 'staff@fsanciro.local';
  static bool isKnownStaffEmail(String? e) {
    final m = (e ?? '').trim().toLowerCase();
    return m == adminEmail || m == staffEmail;
  }

  PersonalSession? _fallbackFor(String uid) {
    final email = (_auth.currentUser?.email ?? '').trim().toLowerCase();
    if (email == adminEmail) {
      return PersonalSession.staff(Employee(id: uid, email: email, nome: 'Amministratore', ruolo: 'admin', attivo: true));
    }
    if (email == staffEmail) {
      return PersonalSession.staff(Employee(id: uid, email: email, nome: email.split('@').first, ruolo: 'staff', attivo: true));
    }
    return null;
  }

  Future<PersonalSession> _sessionFor(String uid) async {
    try { await _auth.currentUser?.getIdToken(); } catch (_) {}
    DocumentSnapshot<Map<String, dynamic>>? doc;
    for (var i = 0; i < 3; i++) {
      try {
        doc = await _db.doc('employees/$uid').get().timeout(const Duration(seconds: 6));
        break;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied' && e.code != 'unavailable' && e.code != 'unauthenticated') {
          final fb = _fallbackFor(uid);
          if (fb != null) return fb;
          rethrow;
        }
        try { await _auth.currentUser?.getIdToken(true); } catch (_) {}
        await Future.delayed(Duration(milliseconds: 400 * (i + 1)));
      } catch (_) {
        // timeout o errore: per gli account noti usiamo subito il fallback
        final fb = _fallbackFor(uid);
        if (fb != null) return fb;
        break;
      }
    }
    if (doc == null || !doc.exists) return _fallbackFor(uid) ?? const PersonalSession.customer();
    try {
      final employee = Employee.fromDoc(doc);
      final known = _fallbackFor(uid);
      if (!employee.attivo && known != null) return known;
      if (!employee.attivo) {
        throw StateError('Account dipendente disattivato');
      }
      final fb = _fallbackFor(uid);
      // L'email admin resta admin anche se il documento dice altro.
      if (fb != null && fb.employee!.isAdmin && !employee.isAdmin) return fb;
      return PersonalSession.staff(employee);
    } on StateError {
      rethrow;
    } catch (_) {
      return _fallbackFor(uid) ?? const PersonalSession.customer();
    }
  }

  Future<void> signOut() => hardSignOut();

  Future<void> sendPasswordReset() async {
    final email = _auth.currentUser?.email;
    if (email == null || email.isEmpty) throw StateError('Email non disponibile');
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<CustomerProfile?> profile() async {
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) return null;
    try {
      final doc = await _db.doc('customers/${current.uid}').get();
      if (!doc.exists) {
        return CustomerProfile(id: current.uid, email: current.email ?? '', nome: '', telefono: '', codiceFiscale: '');
      }
      return CustomerProfile.fromDoc(doc);
    } catch (_) {
      return null;
    }
  }

  /// Aggiorna solo l'anagrafica: conserva l'email di contatto corretta dal banco.
  Future<void> updateProfile({required String nome, required String telefono, required String codiceFiscale}) async {
    final current = user;
    if (current == null || current.isAnonymous) throw StateError('Accedi al tuo account');
    final name = nome.trim();
    final phone = telefono.trim();
    final cf = normalizeCodiceFiscale(codiceFiscale);
    if (name.isEmpty || name.length >= 100) throw StateError('Nome non valido');
    if (phone.length < 6 || phone.length >= 30) throw StateError('Telefono non valido');
    if (!isValidCodiceFiscale(cf)) throw StateError('Codice fiscale non valido');
    final ref = _db.doc('customers/${current.uid}');
    await _db.runTransaction((tx) async {
      final doc = await tx.get(ref);
      tx.set(ref, {
        if (!doc.exists) 'email': current.email ?? '',
        'nome': name,
        'telefono': phone,
        'codiceFiscale': cf,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  /// true se l'utente ha già scelto una password sua (customers/{uid}.passwordChanged).
  Future<bool> passwordChanged() async {
    final u = _auth.currentUser;
    if (u == null || u.isAnonymous) return true;
    try {
      final d = await _db.doc('customers/${u.uid}').get();
      return (d.data()?['passwordChanged'] ?? false) == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> markPasswordChanged() async {
    final u = _auth.currentUser;
    if (u == null || u.isAnonymous) return;
    await _db.doc('customers/${u.uid}').set({
      'passwordChanged': true,
      'passwordChangedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
