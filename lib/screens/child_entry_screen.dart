import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';

import 'child/parent_link_screen.dart';
import 'child/child_home_screen.dart';

class ChildEntryScreen extends StatelessWidget {
  const ChildEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = SupabaseConfig.client.auth.currentUser!.id;

    return FutureBuilder<Map<String, dynamic>?>(
      future: SupabaseConfig.client
          .from('children')
          .select()
          .eq('id', uid)
          .maybeSingle(),
      builder: (context, snapshot) {
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data;

        // Child is not linked to a parent yet
        if (data == null) {
          return const ParentLinkScreen();
        }

        final parentId = data['parent_id'] as String?;

        // Child doc exists but no parent assigned
        if (parentId == null || parentId.isEmpty) {
          return const ParentLinkScreen();
        }

        // Child already paired
        return const ChildHomeScreen();
      },
    );
  }
}
