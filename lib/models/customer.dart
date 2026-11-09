import 'package:cloud_firestore/cloud_firestore.dart';

/// Profilo `customers/{uid}` del cliente (non è un dipendente).
class CustomerProfile {
  final String id;
  final String email;
  final String nome;
  final String telefono;
  final String codiceFiscale;

  const CustomerProfile({required this.id, required this.email, required this.nome, required this.telefono, required this.codiceFiscale});

  factory CustomerProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return CustomerProfile(
      id: d.id,
      email: (m['email'] ?? '') as String,
      nome: (m['nome'] ?? '') as String,
      telefono: (m['telefono'] ?? '') as String,
      codiceFiscale: (m['codiceFiscale'] ?? '') as String,
    );
  }
}
