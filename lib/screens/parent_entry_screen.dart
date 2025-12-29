import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'parent_pairing_code_screen.dart';
import 'parent_children_screen.dart';

class ParentEntryScreen extends StatelessWidget {
  const ParentEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('children')
          .where('parentId', isEqualTo: uid)
          .limit(1)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text('Something went wrong')),
          );
        }

        if (snapshot.data!.docs.isEmpty) {
          return const ParentPairingCodeScreen();
        }

        return const ParentChildrenScreen();
      },
    );
  }
}
