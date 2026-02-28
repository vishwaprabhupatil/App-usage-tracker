import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'child/parent_link_screen.dart';
import 'child/child_home_screen.dart';

class ChildEntryScreen extends StatelessWidget {
  const ChildEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('children').doc(uid).get(),
      builder: (context, snapshot) {
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Child is not linked to a parent yet
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const ParentLinkScreen();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final parentId = (data?['parentId'] ?? data?['parentUid']) as String?;

        // Child doc exists but no parent assigned
        if (data == null || parentId == null || parentId.isEmpty) {
          return const ParentLinkScreen();
        }

        // Child already paired
        return const ChildHomeScreen();
      },
    );
  }
}
