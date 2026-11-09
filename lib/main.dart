import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app.dart';
import 'models/room.dart';
import 'firebase_options.dart';
import 'services/auth_persistence.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(readStaySignedIn() ? Persistence.LOCAL : Persistence.SESSION);
  }
  Room.listen();
  runApp(const FarmaciaApp());
}
