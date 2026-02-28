import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'parent_entry_screen.dart';
import 'child_entry_screen.dart';

class RoleRedirectScreen extends StatelessWidget {
  const RoleRedirectScreen({super.key});

  Future<String?> _resolveRole() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRole = prefs.getString('userRole');
    if (savedRole == 'parent' || savedRole == 'child') return savedRole;

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final childDoc =
        await FirebaseFirestore.instance.collection('children').doc(uid).get();

    final childData = childDoc.data();
    final parentId = (childData?['parentId'] ?? childData?['parentUid']) as String?;

    if (childDoc.exists && parentId != null && parentId.isNotEmpty) {
      return 'child';
    }

    return 'parent';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _resolveRole(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: Text('Unable to determine user role')),
          );
        }

        final role = snapshot.data!;

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
