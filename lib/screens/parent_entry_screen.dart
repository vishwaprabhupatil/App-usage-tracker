import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import '../services/pairing_service.dart';

import 'parent_pairing_code_screen.dart';
import 'parent_children_screen.dart';

class ParentEntryScreen extends StatefulWidget {
  const ParentEntryScreen({super.key});

  @override
  State<ParentEntryScreen> createState() => _ParentEntryScreenState();
}

class _ParentEntryScreenState extends State<ParentEntryScreen> {
  late Future<List<Map<String, dynamic>>> _entryFuture;

  @override
  void initState() {
    super.initState();
    _entryFuture = _loadParentState();
  }

  Future<List<Map<String, dynamic>>> _loadParentState() async {
    final uid = SupabaseConfig.client.auth.currentUser!.id;

    // Ensure pairing code exists for every logged-in parent account.
    await PairingService.ensureParentPairingCode();

    return SupabaseConfig.client
        .from('children')
        .select()
        .eq('parent_id', uid)
        .limit(1);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
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

        final children = snapshot.data ?? [];

        if (children.isEmpty) {
          return const ParentPairingCodeScreen();
        }

        return const ParentChildrenScreen();
      },
    );
  }
}
