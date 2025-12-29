import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'parent_entry_screen.dart';
import 'child_entry_screen.dart';

class RoleRedirectScreen extends StatelessWidget {
  const RoleRedirectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(
            body: Center(child: Text('User data not found')),
          );
        }

        final role = snapshot.data!['role'];

        if (role == 'parent') {
          return const ParentEntryScreen();
        }

        if (role == 'child') {
          return const ChildEntryScreen();
        }

        return const Scaffold(
          body: Center(child: Text('Invalid user role')),
        );
      },
    );
  }
}
