import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PairingService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Generates a 6-digit pairing code
  static String generatePairingCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  /// Save pairing code for parent
  static Future<String> createParentPairingCode() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final code = generatePairingCode();

    await _firestore.collection('parents').doc(user.uid).set({
      'email': user.email,
      'pairingCode': code,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return code;
  }

  /// Child uses code to link to parent
  static Future<void> linkChildToParent(
    String pairingCode,
    String deviceName,
  ) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Child not logged in');

    final query = await _firestore
        .collection('parents')
        .where('pairingCode', isEqualTo: pairingCode)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      throw Exception('Invalid pairing code');
    }

    final parentId = query.docs.first.id;

    await _firestore.collection('children').doc(user.uid).set({
      'parentUid': parentId,
      'deviceName': deviceName,
      'linkedAt': FieldValue.serverTimestamp(),
    });
  }
}
