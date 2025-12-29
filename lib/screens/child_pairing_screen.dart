import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ChildPairingScreen extends StatefulWidget {
  const ChildPairingScreen({super.key});

  @override
  State<ChildPairingScreen> createState() => _ChildPairingScreenState();
}

class _ChildPairingScreenState extends State<ChildPairingScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;

  Future<void> _pairDevice() async {
    setState(() => _loading = true);

    final code = _codeController.text.trim();
    final childId = FirebaseAuth.instance.currentUser!.uid;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('pairing_codes')
          .doc(code)
          .get();

      if (!doc.exists) {
        throw 'Invalid code';
      }

      final parentId = doc['parentId'];

      await FirebaseFirestore.instance.collection('children').doc(childId).set({
        'parentId': parentId,
        'childId': childId,
        'pairedAt': Timestamp.now(),
      });

      await FirebaseFirestore.instance
          .collection('pairing_codes')
          .doc(code)
          .delete();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device paired successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid or expired code')),
      );
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair with Parent')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Enter pairing code from parent device',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '6-digit code',
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _pairDevice,
                child: _loading
                    ? const CircularProgressIndicator()
                    : const Text('Pair Device'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
