import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/pairing_service.dart';

import 'parent_pairing_code_screen.dart';
import 'parent_children_screen.dart';

class ParentEntryScreen extends StatefulWidget {
  const ParentEntryScreen({super.key});

  @override
  State<ParentEntryScreen> createState() => _ParentEntryScreenState();
}

class _ParentEntryScreenState extends State<ParentEntryScreen> {
  late final Future<QuerySnapshot> _entryFuture;

  @override
  void initState() {
    super.initState();
    _entryFuture = _loadParentState();
  }

  Future<QuerySnapshot> _loadParentState() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // Ensure pairing code exists for every logged-in parent account.
    await PairingService.ensureParentPairingCode();

    return FirebaseFirestore.instance
        .collection('children')
        .where('parentId', isEqualTo: uid)
        .limit(1)
        .get();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot>(
      future: _entryFuture,
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
