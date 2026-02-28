import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/pairing_service.dart';

import 'parent_children_screen.dart';

/// Screen that displays the parent's permanent pairing code.
/// Code is generated once and stored permanently in Firestore.
class ParentPairingCodeScreen extends StatefulWidget {
  const ParentPairingCodeScreen({super.key});

  @override
  State<ParentPairingCodeScreen> createState() => _ParentPairingCodeScreenState();
}

class _ParentPairingCodeScreenState extends State<ParentPairingCodeScreen> {
  String _pairingCode = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOrGenerateCode();
  }

  /// Load existing code or generate a new permanent one
  Future<void> _loadOrGenerateCode() async {
    setState(() => _loading = true);

    try {
      final code = await PairingService.ensureParentPairingCode(
        parentName: FirebaseAuth.instance.currentUser?.displayName,
      );
      if (mounted) {
        setState(() {
          _pairingCode = code;
        });
      }
    } catch (e) {
      debugPrint('Error loading/generating code: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair Child Device'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.link,
              size: 64,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            Text(
              'Your Pairing Code',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Enter this code on your child\'s device to link',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 32),

            // Pairing code display
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 40),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).primaryColor,
                  width: 2,
                ),
              ),
              child: _loading
                  ? const CircularProgressIndicator()
                  : Text(
                      _pairingCode,
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 12,
                      ),
                    ),
            ),

            const SizedBox(height: 16),
            
            Text(
              'This code is permanent and won\'t expire',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),

            const SizedBox(height: 48),

            // Continue to children screen
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ParentChildrenScreen(),
                    ),
                  );
                },
                child: const Text('View Linked Children'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
