import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/notice.dart';

final noticeBoard = NoticeBoard();

class NoticeBoard {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => _db.collection('notices');

  Stream<List<Notice>> watchAll() => _col.snapshots().map((q) {
        final list = q.docs.map(Notice.fromDoc).toList()
          ..sort((a, b) => a.ordine != b.ordine ? a.ordine.compareTo(b.ordine) : a.titolo.compareTo(b.titolo));
        return list;
      });

  /// Solo attivi: la regola Firestore consente questa query anche senza essere admin.
  Stream<List<Notice>> watchActive() => _col.where('attivo', isEqualTo: true).snapshots().map((q) => q.docs.map(Notice.fromDoc).toList());

  Future<void> save(Notice n) async {
    final ref = n.id.isEmpty ? _col.doc() : _col.doc(n.id);
    await ref.set(n.toMap());
  }

  Future<void> remove(String id) => _col.doc(id).delete();
}
