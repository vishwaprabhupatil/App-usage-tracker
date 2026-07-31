import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../supabase_config.dart';
import '../../services/foreground_sync_service.dart';

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
    final user = SupabaseConfig.client.auth.currentUser;
    if (user == null) return;

    try {
      final childDoc = await SupabaseConfig.client
          .from('children')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final parentId = childDoc?['parent_id'] as String?;

      if (childDoc != null && parentId != null && parentId.isNotEmpty) {
        // Already linked - get parent name
        final parentDoc = await SupabaseConfig.client
            .from('parents')
            .select('name')
            .eq('id', parentId)
            .maybeSingle();

        setState(() {
          _linked = true;
          _linkedParentName = parentDoc?['name'] ?? 'Parent';
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
      final parentDoc = await SupabaseConfig.client
          .from('parents')
          .select()
          .eq('pairing_code', code)
          .maybeSingle();

      if (parentDoc == null) {
        setState(() {
          _error = 'Invalid code. Please check and try again.';
          _loading = false;
        });
        return;
      }

      final parentId = parentDoc['id'];
      final parentName = parentDoc['name'] ?? 'Parent';

      // Create/Update child entry
      final user = SupabaseConfig.client.auth.currentUser!;
      final childId = user.id;
      final childName = user.userMetadata?['name'] ?? user.email ?? 'Child';

      await SupabaseConfig.client.from('children').upsert({
        'id': childId,
        'parent_id': parentId,
        'child_name': childName,
        'linked_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Initialize screentime document
      await SupabaseConfig.client.from('screentime').upsert({
        'id': childId,
        'total_time': '0m',
        'apps': [],
        'last_updated': DateTime.now().toUtc().toIso8601String(),
      });
      
      // Trigger immediate sync so parent sees data right away
      await ForegroundSyncService.triggerSyncNow();

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
      final childId = SupabaseConfig.client.auth.currentUser!.id;
      
      // We don't delete the whole child record, just remove the parent_id
      await SupabaseConfig.client
          .from('children')
          .update({'parent_id': null})
          .eq('id', childId);

      // Optionally delete screentime data
      await SupabaseConfig.client
          .from('screentime')
          .delete()
          .eq('id', childId);

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
