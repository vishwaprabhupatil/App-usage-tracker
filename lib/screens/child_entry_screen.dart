import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'child_pairing_screen.dart';
import 'child_home.dart';

class ChildEntryScreen extends StatelessWidget {
  const ChildEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ❗ Document does not exist yet
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const ChildPairingScreen();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;

        // ❗ Data is null or parent not linked
        if (data == null || data['parentId'] == null) {
          return const ChildPairingScreen();
        }

        // ✅ Child already paired
        return const ChildHomeScreen();
      },
    );
  }
}
