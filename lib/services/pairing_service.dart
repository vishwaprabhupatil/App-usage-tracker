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

  /// Ensures the current parent has a permanent unique 6-digit pairing code.
  /// Returns the existing code if present, otherwise generates and stores a new one.
  static Future<String> ensureParentPairingCode({String? parentName}) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final parentRef = _firestore.collection('parents').doc(user.uid);
    final parentSnapshot = await parentRef.get();
    final existingCode = parentSnapshot.data()?['pairingCode']?.toString();

    if (_isValidPairingCode(existingCode)) {
      return existingCode!;
    }

    // Retry bounded times to avoid an infinite loop on unexpected failures.
    for (var attempt = 0; attempt < 20; attempt++) {
      final code = generatePairingCode();
      final existing = await _firestore
          .collection('parents')
          .where('pairingCode', isEqualTo: code)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) continue;

      await parentRef.set({
        'pairingCode': code,
        'name': parentName ?? user.displayName ?? 'Parent',
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!parentSnapshot.exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return code;
    }

    throw Exception('Could not generate a unique pairing code. Please try again.');
  }

  static bool _isValidPairingCode(String? code) {
    if (code == null) return false;
    return RegExp(r'^\d{6}$').hasMatch(code);
  }

  /// Save pairing code for parent
  static Future<String> createParentPairingCode() async {
    return ensureParentPairingCode();
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
