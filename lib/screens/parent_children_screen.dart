import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import 'child_screentime_view.dart';
import 'parent_pairing_code_screen.dart';
import '../theme/theme_controller.dart';
import '../auth/auth_service.dart';

/// Status of a child's device/app
enum ChildStatus {
  online,    // Last sync < 10 minutes ago
  inactive,  // Last sync 10-35 minutes ago
  offline,   // Last sync > 35 minutes ago (app deleted or no internet)
}

/// Get child status based on last update time
ChildStatus getChildStatus(DateTime? lastUpdated) {
  if (lastUpdated == null) return ChildStatus.offline;
  
  final now = DateTime.now();
  final diff = now.difference(lastUpdated);
  
  if (diff.inMinutes < 10) {
    return ChildStatus.online;
  } else if (diff.inMinutes < 35) {
    return ChildStatus.inactive;
  } else {
    return ChildStatus.offline;
  }
}

/// Get status color
Color getStatusColor(ChildStatus status) {
  switch (status) {
    case ChildStatus.online:
      return Colors.green;
    case ChildStatus.inactive:
      return Colors.orange;
    case ChildStatus.offline:
      return Colors.red;
  }
}

/// Get status text
String getStatusText(ChildStatus status) {
  switch (status) {
    case ChildStatus.online:
      return 'Online';
    case ChildStatus.inactive:
      return 'Inactive';
    case ChildStatus.offline:
      return 'Offline';
  }
}

/// Parent dashboard showing linked children.
class ParentChildrenScreen extends StatelessWidget {
  const ParentChildrenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final parentId = FirebaseAuth.instance.currentUser!.uid;
    final themeController = context.watch<ThemeController>();
    final isDark = themeController.mode == AppThemeMode.dark ||
        (themeController.mode == AppThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Children'),
        automaticallyImplyLeading: false,
        actions: [
          // Show pairing code
          IconButton(
            icon: const Icon(Icons.qr_code),
            tooltip: 'Show Pairing Code',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ParentPairingCodeScreen(),
                ),
              );
            },
          ),
          // Menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _handleMenuAction(value, context),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'theme',
                child: Row(
                  children: [
                    Icon(
                      isDark ? Icons.light_mode : Icons.dark_mode,
                      size: 20,
                      color: Theme.of(context).iconTheme.color,
                    ),
                    const SizedBox(width: 12),
                    const Text('Theme'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 20, color: Colors.red),
                    SizedBox(width: 12),
                    Text('Log Out', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('children')
            .where('parentId', isEqualTo: parentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final children = snapshot.data?.docs ?? [];

          if (children.isEmpty) {
            return _buildEmptyState(context);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: children.length,
            itemBuilder: (context, index) {
              final doc = children[index];
              return _buildChildCard(context, doc);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 80, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              'No Children Linked',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Share your pairing code with your child to link devices',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code),
              label: const Text('Show Pairing Code'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ParentPairingCodeScreen(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChildCard(BuildContext context, DocumentSnapshot doc) {
    final childId = doc.id;
    final childName = doc['childName'] ?? 'Child';

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('screentime')
          .doc(childId)
          .snapshots(),
      builder: (context, snapshot) {
        // Determine status from lastUpdated
        DateTime? lastUpdated;
        String totalTime = '0m';
        
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          totalTime = data?['totalTime'] ?? '0m';
          final timestamp = data?['lastUpdated'] as Timestamp?;
          lastUpdated = timestamp?.toDate();
        }
        
        final status = getChildStatus(lastUpdated);

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChildScreentimeView(
                    childId: childId,
                    childName: childName,
                  ),
                ),
              );
            },
            onLongPress: () {
              _showRemoveChildDialog(context, childId, childName);
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: Avatar, Name, Chevron
                  Row(
                    children: [
                      // Avatar
                      CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor,
                        child: Text(
                          childName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white, 
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Name and screen time
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              childName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Screen time: $totalTime',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                  // Warning message for offline status
                  if (status == ChildStatus.offline) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.red.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Child may have deleted the app or has no internet connection',
                              style: TextStyle(
                                color: Colors.red[700],
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showRemoveChildDialog(BuildContext context, String childId, String childName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Child'),
        content: Text('Are you sure you want to remove "$childName" from your account?\n\nThis will unlink the child\'s device from your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _removeChild(context, childId, childName);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _removeChild(BuildContext context, String childId, String childName) async {
    try {
      // Remove parentId from children collection (unlink)
      await FirebaseFirestore.instance
          .collection('children')
          .doc(childId)
          .update({'parentId': FieldValue.delete()});
      
      // Optionally delete screentime data
      await FirebaseFirestore.instance
          .collection('screentime')
          .doc(childId)
          .delete();

      // Optionally delete blocked apps data
      await FirebaseFirestore.instance
          .collection('blocked_apps')
          .doc(childId)
          .delete();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$childName has been removed'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error removing child: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }


  void _handleMenuAction(String action, BuildContext context) {
    switch (action) {
      case 'theme':
        // Toggle theme
        final controller = context.read<ThemeController>();
        if (controller.mode == AppThemeMode.dark) {
          controller.setLight();
        } else {
          controller.setDark();
        }
        break;
      case 'logout':
        _showLogoutConfirmation(context);
        break;
    }
  }

  void _showLogoutConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await AuthService().logout();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/role-selection',
                  (route) => false,
                );
              }
            },
            child: const Text('Log Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
