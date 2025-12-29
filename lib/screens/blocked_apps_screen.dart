import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Screen for parent to manage blocked apps for a child.
class BlockedAppsScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const BlockedAppsScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<BlockedAppsScreen> createState() => _BlockedAppsScreenState();
}

class _BlockedAppsScreenState extends State<BlockedAppsScreen> {
  List<String> _blockedApps = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadBlockedApps();
  }

  Future<void> _loadBlockedApps() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('children')
          .doc(widget.childId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final blockedList = data?['blockedApps'] as List<dynamic>?;
        _blockedApps = blockedList?.cast<String>() ?? [];
      }
    } catch (e) {
      debugPrint('BlockedAppsScreen: Error loading blocked apps: $e');
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleBlockApp(String packageName, bool block) async {
    setState(() {
      if (block) {
        if (!_blockedApps.contains(packageName)) {
          _blockedApps.add(packageName);
        }
      } else {
        _blockedApps.remove(packageName);
      }
    });

    // Save to Firestore
    setState(() => _saving = true);
    
    try {
      await FirebaseFirestore.instance
          .collection('children')
          .doc(widget.childId)
          .set({
        'blockedApps': _blockedApps,
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(block ? 'App blocked' : 'App unblocked'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('BlockedAppsScreen: Error saving: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save changes')),
        );
      }
    }

    if (mounted) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Block Apps - ${widget.childName}'),
        actions: [
          if (_saving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('screentime')
          .doc(widget.childId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          return _buildNoApps();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final apps = (data?['apps'] as List<dynamic>?) ?? [];

        if (apps.isEmpty) {
          return _buildNoApps();
        }

        return Column(
          children: [
            // Header info
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Toggle the switch to block apps. Blocked apps will show a "Blocked" screen when opened.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Blocked count
            if (_blockedApps.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.block, size: 16, color: Colors.red),
                          const SizedBox(width: 6),
                          Text(
                            '${_blockedApps.length} app${_blockedApps.length == 1 ? '' : 's'} blocked',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            
            // Apps list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 32),
                itemCount: apps.length,
                itemBuilder: (context, index) {
                  return _buildAppTile(apps[index]);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNoApps() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.apps, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No apps to show',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Apps will appear here once the child uses their device',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppTile(dynamic appData) {
    final app = appData as Map<String, dynamic>;
    final packageName = app['packageName'] as String? ?? '';
    final appName = app['appName'] as String? ?? 'Unknown';
    final iconBase64 = app['icon'] as String?;
    final duration = app['duration'] as String? ?? '0m';

    // Decode icon
    Uint8List? iconBytes;
    if (iconBase64 != null && iconBase64.isNotEmpty) {
      try {
        iconBytes = base64Decode(iconBase64);
      } catch (e) {
        // Ignore
      }
    }

    final isBlocked = _blockedApps.contains(packageName);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isBlocked
            ? Colors.red.withOpacity(0.05)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: isBlocked
            ? Border.all(color: Colors.red.withOpacity(0.3))
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildAppIcon(appName, iconBytes, isBlocked),
        title: Row(
          children: [
            Expanded(
              child: Text(
                appName,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: isBlocked ? Colors.red : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isBlocked)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'BLOCKED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'Usage: $duration',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 13,
          ),
        ),
        trailing: Switch(
          value: isBlocked,
          onChanged: (value) => _toggleBlockApp(packageName, value),
          activeColor: Colors.red,
        ),
      ),
    );
  }

  Widget _buildAppIcon(String appName, Uint8List? iconBytes, bool isBlocked) {
    Widget icon;
    
    if (iconBytes != null && iconBytes.isNotEmpty) {
      icon = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.memory(
          iconBytes,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(appName),
        ),
      );
    } else {
      icon = _buildFallbackIcon(appName);
    }

    // Add blocked overlay
    if (isBlocked) {
      return Stack(
        children: [
          Opacity(opacity: 0.5, child: icon),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.red.withOpacity(0.3),
              ),
              child: const Icon(Icons.block, color: Colors.red, size: 24),
            ),
          ),
        ],
      );
    }

    return icon;
  }

  Widget _buildFallbackIcon(String appName) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _getColorFromName(appName),
            _getColorFromName(appName).withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          appName.isNotEmpty ? appName[0].toUpperCase() : '?',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Color _getColorFromName(String name) {
    final colors = [
      Colors.blue,
      Colors.purple,
      Colors.teal,
      Colors.orange,
      Colors.pink,
      Colors.indigo,
    ];
    return colors[name.hashCode.abs() % colors.length];
  }
}
