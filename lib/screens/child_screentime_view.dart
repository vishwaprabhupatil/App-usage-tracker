import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'blocked_apps_screen.dart';
import 'usage_analysis_screen.dart'; // <---

/// Screen for parent to view a specific child's screen time.
class ChildScreentimeView extends StatelessWidget {
  final String childId;
  final String childName;

  const ChildScreentimeView({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$childName\'s Screen Time'),
        actions: [
          // Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'block') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BlockedAppsScreen(
                      childId: childId,
                      childName: childName,
                    ),
                  ),
                );
              } else if (value == 'analysis') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsageAnalysisScreen(
                      childId: childId,
                      childName: childName,
                    ),
                  ),
                );
              } else if (value == 'share') {
                _showShareAccessDialog(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'analysis',
                child: Row(
                  children: [
                    Icon(Icons.bar_chart, size: 20),
                    SizedBox(width: 12),
                    Text('Usage Analysis'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'block',
                child: Row(
                  children: [
                    Icon(Icons.block, size: 20),
                    SizedBox(width: 12),
                    Text('Manage Apps'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20),
                    SizedBox(width: 12),
                    Text('Share Access'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BlockedAppsScreen(
                childId: childId,
                childName: childName,
              ),
            ),
          );
        },
        icon: const Icon(Icons.block),
        label: const Text('Block Apps'),
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('screentime')
            .doc(childId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _buildNoData();
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final totalTime = data['totalTime'] ?? '0m';
          final apps = (data['apps'] as List<dynamic>?) ?? [];
          final lastUpdated = data['lastUpdated'] as Timestamp?;

          return _buildContent(context, totalTime, apps, lastUpdated);
        },
      ),
    );
  }

  Widget _buildNoData() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No screen time data yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Data will appear once the child opens the app',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    String totalTime,
    List<dynamic> apps,
    Timestamp? lastUpdated,
  ) {
    return CustomScrollView(
      slivers: [
        // Header with total time
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Screen time today',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  totalTime,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${apps.length} apps',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                if (lastUpdated != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Updated ${_formatTime(lastUpdated.toDate())}',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Apps section header
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              'Apps used today',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ),
        ),

        // Apps list
        if (apps.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('No app usage recorded'),
              ),
            ),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildAppTile(context, apps[index]),
              childCount: apps.length,
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildAppTile(BuildContext context, dynamic appData) {
    final app = appData as Map<String, dynamic>;
    final appName = app['appName'] ?? 'Unknown';
    final duration = app['duration'] ?? '0m';
    final openCount = (app['openCount'] as num?)?.toInt() ?? 0;
    final iconBase64 = app['icon'] as String?;

    // Decode icon from base64 if available
    Uint8List? iconBytes;
    if (iconBase64 != null && iconBase64.isNotEmpty) {
      try {
        iconBytes = base64Decode(iconBase64);
      } catch (e) {
        // Ignore decode errors, will use fallback
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildAppIcon(appName, iconBytes),
        title: Text(
          appName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          openCount == 1 ? 'Opened 1 time' : 'Opened $openCount times',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _getDurationColor(duration).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            duration,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _getDurationColor(duration),
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppIcon(String appName, Uint8List? iconBytes) {
    // Use real icon if available
    if (iconBytes != null && iconBytes.isNotEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            iconBytes,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackIcon(appName);
            },
          ),
        ),
      );
    }

    return _buildFallbackIcon(appName);
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

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _getColorFromName(String name) {
    final colors = [
      Colors.blue,
      Colors.purple,
      Colors.teal,
      Colors.orange,
      Colors.pink,
      Colors.indigo,
      Colors.cyan,
      Colors.green,
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  Color _getDurationColor(String duration) {
    if (duration.contains('h')) {
      final hours = int.tryParse(duration.split('h')[0]) ?? 0;
      if (hours >= 2) return Colors.red;
      if (hours >= 1) return Colors.orange;
    }
    final mins = int.tryParse(duration.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (mins >= 30) return Colors.amber[700]!;
    return Colors.green;
  }

  void _showShareAccessDialog(BuildContext context) {
    final parentId = FirebaseAuth.instance.currentUser!.uid;
    final codeController = TextEditingController();
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('parents').doc(parentId).snapshots(),
        builder: (context, snapshot) {
          final parentData = snapshot.data?.data() as Map<String, dynamic>?;
          final myCode = parentData?['pairingCode'] ?? '...';

          return StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('Share Access'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Text('Your Pairing Code', style: TextStyle(fontSize: 12)),
                        Text(
                          myCode,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Enter another parent\'s pairing code to share access to $childName\'s screen time.',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: codeController,
                    decoration: const InputDecoration(
                      labelText: 'Parent Pairing Code',
                      hintText: 'Enter 6-digit code',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                  ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final code = codeController.text.trim();
                          if (code.length != 6) return;

                          setState(() => loading = true);

                          try {
                            // 1. Find the other parent by code
                            final otherParentQuery = await FirebaseFirestore.instance
                                .collection('parents')
                                .where('pairingCode', isEqualTo: code)
                                .limit(1)
                                .get();

                            if (otherParentQuery.docs.isEmpty) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('Invalid code. Parent not found.')),
                                );
                              }
                              setState(() => loading = false);
                              return;
                            }

                            final otherParentId = otherParentQuery.docs.first.id;

                            if (otherParentId == parentId) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(content: Text('You cannot share with yourself.')),
                                );
                              }
                              setState(() => loading = false);
                              return;
                            }

                            // 2. Add otherParentId to this child's sharedParentIds
                            await FirebaseFirestore.instance
                                .collection('children')
                                .doc(childId)
                                .update({
                              'sharedParentIds': FieldValue.arrayUnion([otherParentId])
                            });

                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text('Access to $childName shared successfully!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('Error sharing access: $e')),
                              );
                            }
                            setState(() => loading = false);
                          }
                        },
                  child: const Text('Share'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
