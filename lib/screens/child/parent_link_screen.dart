import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Screen for child to enter parent's 6-digit code to link accounts.
class ParentLinkScreen extends StatefulWidget {
  const ParentLinkScreen({super.key});

  @override
  State<ParentLinkScreen> createState() => _ParentLinkScreenState();
}

class _ParentLinkScreenState extends State<ParentLinkScreen> {
  final _codeController = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _linked = false;
  String? _linkedParentName;

  @override
  void initState() {
    super.initState();
    _checkExistingLink();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// Check if already linked to a parent
  Future<void> _checkExistingLink() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final childDoc = await FirebaseFirestore.instance
          .collection('children')
          .doc(uid)
          .get();

      if (childDoc.exists && childDoc.data()?['parentId'] != null) {
        // Already linked - get parent name
        final parentId = childDoc.data()!['parentId'];
        final parentDoc = await FirebaseFirestore.instance
            .collection('parents')
            .doc(parentId)
            .get();

        setState(() {
          _linked = true;
          _linkedParentName = parentDoc.data()?['name'] ?? 'Parent';
        });
      }
    } catch (e) {
      debugPrint('Error checking link: $e');
    }
  }

  /// Verify code and link to parent
  Future<void> _linkToParent() async {
    final code = _codeController.text.trim();
    
    if (code.length != 6) {
      setState(() => _error = 'Please enter a 6-digit code');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Find parent with this code
      final parentQuery = await FirebaseFirestore.instance
          .collection('parents')
          .where('pairingCode', isEqualTo: code)
          .limit(1)
          .get();

      if (parentQuery.docs.isEmpty) {
        setState(() {
          _error = 'Invalid code. Please check and try again.';
          _loading = false;
        });
        return;
      }

      final parentDoc = parentQuery.docs.first;
      final parentId = parentDoc.id;
      final parentName = parentDoc.data()['name'] ?? 'Parent';

      // Create child entry
      final childUid = FirebaseAuth.instance.currentUser!.uid;
      final childName = FirebaseAuth.instance.currentUser!.displayName ?? 'Child';

      await FirebaseFirestore.instance.collection('children').doc(childUid).set({
        'parentId': parentId,
        'childName': childName,
        'linkedAt': FieldValue.serverTimestamp(),
      });

      // Initialize screentime document
      await FirebaseFirestore.instance.collection('screentime').doc(childUid).set({
        'totalTime': '0m',
        'apps': [],
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      setState(() {
        _linked = true;
        _linkedParentName = parentName;
        _loading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Linked to $parentName successfully!')),
        );
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  /// Unlink from parent
  Future<void> _unlinkFromParent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unlink from Parent?'),
        content: const Text('Your screen time will no longer be visible to this parent.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unlink', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);

    try {
      final childUid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('children').doc(childUid).delete();
      await FirebaseFirestore.instance.collection('screentime').doc(childUid).delete();

      setState(() {
        _linked = false;
        _linkedParentName = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error unlinking: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Link to Parent')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _linked ? _buildLinkedView() : _buildLinkForm(),
      ),
    );
  }

  Widget _buildLinkedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          Text(
            'Linked to $_linkedParentName',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your screen time is being shared',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 32),
          TextButton(
            onPressed: _loading ? null : _unlinkFromParent,
            child: const Text('Unlink', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.link, size: 64, color: Colors.blue),
        const SizedBox(height: 24),
        const Text(
          'Enter 6-digit code from parent device',
          style: TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, letterSpacing: 8),
          decoration: InputDecoration(
            hintText: '● ● ● ● ● ●',
            counterText: '',
            errorText: _error,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _loading ? null : _linkToParent,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Link'),
          ),
        ),
      ],
    );
  }
}
