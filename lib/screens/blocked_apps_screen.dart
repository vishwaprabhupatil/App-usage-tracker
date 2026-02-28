import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Screen for parent to manage blocked apps and time limits for a child.
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
  Map<String, int> _appLimits = {}; // Package name -> Limit in minutes
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadChildSettings();
  }

  Future<void> _loadChildSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('children')
          .doc(widget.childId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        final blockedList = data?['blockedApps'] as List<dynamic>?;
        _blockedApps = blockedList?.cast<String>() ?? [];
        
        final limitsMap = data?['appLimits'] as Map<String, dynamic>?;
        if (limitsMap != null) {
          _appLimits = limitsMap.map((key, value) => MapEntry(key, value as int));
        }
      }
    } catch (e) {
      debugPrint('BlockedAppsScreen: Error loading child settings: $e');
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

    _saveSettings();
  }
  
  Future<void> _setAppLimit(String packageName, String appName, int? currentLimitMinutes) async {
    final int? selectedLimit = await showDialog<int?>(
      context: context,
      builder: (context) => _SetLimitDialog(
        appName: appName,
        currentLimitMinutes: currentLimitMinutes,
      ),
    );
    
    if (selectedLimit == null) return; // Cancelled
    
    setState(() {
      if (selectedLimit == -1) {
        // Remove limit
        _appLimits.remove(packageName);
      } else {
        _appLimits[packageName] = selectedLimit;
      }
    });
    
    _saveSettings();
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    
    try {
      await FirebaseFirestore.instance
          .collection('children')
          .doc(widget.childId)
          .set({
        'blockedApps': _blockedApps,
        'appLimits': _appLimits,
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Settings saved'),
            duration: Duration(seconds: 1),
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
        title: Text('Manage Apps - ${widget.childName}'),
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
          .collection('children')
          .doc(widget.childId)
          .snapshots(),
      builder: (context, childSnapshot) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('screentime')
              .doc(widget.childId)
              .snapshots(),
          builder: (context, screentimeSnapshot) {
            if (screentimeSnapshot.connectionState == ConnectionState.waiting && 
                childSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Consolidate app info
            final Map<String, Map<String, dynamic>> consolidatedApps = {};
            
            // 1. Add all installed apps from child document
            if (childSnapshot.hasData && childSnapshot.data!.exists) {
              final childData = childSnapshot.data!.data() as Map<String, dynamic>?;
              final installedApps = (childData?['installedApps'] as List<dynamic>?) ?? [];
              
              for (final app in installedApps) {
                if (app is Map<String, dynamic> && app['packageName'] != null) {
                  consolidatedApps[app['packageName']] = {
                    'packageName': app['packageName'],
                    'appName': app['appName'] ?? 'Unknown',
                    'duration': '0m',
                    'icon': app['icon'],
                    'openCount': 0,
                  };
                }
              }
            }
            
            // 2. Add/Update with used apps (which have icons and duration)
            if (screentimeSnapshot.hasData && screentimeSnapshot.data!.exists) {
              final data = screentimeSnapshot.data!.data() as Map<String, dynamic>?;
              final usedApps = (data?['apps'] as List<dynamic>?) ?? [];
              
              for (final app in usedApps) {
                if (app is Map<String, dynamic> && app['packageName'] != null) {
                  final pkg = app['packageName'];
                  final usedIcon = app['icon'];
                  if (consolidatedApps.containsKey(pkg)) {
                    consolidatedApps[pkg]!['duration'] = app['duration'] ?? '0m';
                    consolidatedApps[pkg]!['openCount'] =
                        (app['openCount'] as num?)?.toInt() ?? 0;
                    // Do not overwrite an existing icon with null/empty.
                    if (usedIcon is String && usedIcon.isNotEmpty) {
                      consolidatedApps[pkg]!['icon'] = usedIcon;
                    }
                  } else {
                    consolidatedApps[pkg] = {
                      'packageName': pkg,
                      'appName': app['appName'] ?? 'Unknown',
                      'duration': app['duration'] ?? '0m',
                      'icon': usedIcon,
                      'openCount': (app['openCount'] as num?)?.toInt() ?? 0,
                    };
                  }
                }
              }
            }

            final appsList = consolidatedApps.values.toList();
            // Sort by name
            appsList.sort((a, b) => (a['appName'] as String).toLowerCase().compareTo((b['appName'] as String).toLowerCase()));

            if (appsList.isEmpty) {
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
                          'Block apps entirely or tap to set a daily time limit. Blocked apps or apps exceeding their limit will be restricted.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Status counts
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      if (_blockedApps.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                                '${_blockedApps.length} blocked',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_blockedApps.isNotEmpty && _appLimits.isNotEmpty)
                        const SizedBox(width: 8),
                      if (_appLimits.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer, size: 16, color: Colors.orange),
                              const SizedBox(width: 6),
                              Text(
                                '${_appLimits.length} limits set',
                                style: const TextStyle(
                                  color: Colors.orange,
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
                    itemCount: appsList.length,
                    itemBuilder: (context, index) {
                      return _buildAppTile(appsList[index]);
                    },
                  ),
                ),
              ],
            );
          }
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
              'No apps found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Ensure the child\'s device is synced and connected.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppTile(Map<String, dynamic> app) {
    final packageName = app['packageName'] as String? ?? '';
    final appName = app['appName'] as String? ?? 'Unknown';
    final iconBase64 = app['icon'] as String?;
    final duration = app['duration'] as String? ?? '0m';
    final openCount = (app['openCount'] as num?)?.toInt() ?? 0;

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
    final limitMinutes = _appLimits[packageName];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isBlocked
            ? Colors.red.withOpacity(0.05)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: isBlocked
            ? Border.all(color: Colors.red.withOpacity(0.3))
            : limitMinutes != null 
                ? Border.all(color: Colors.orange.withOpacity(0.3))
                : Border.all(color: Colors.transparent),
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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today: $duration',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
            Text(
              openCount == 1 ? 'Opened 1 time' : 'Opened $openCount times',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
            if (limitMinutes != null)
              Text(
                'Limit: ${_formatMinutes(limitMinutes)}',
                style: TextStyle(
                  color: Colors.orange[800],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (limitMinutes == null && !isBlocked)
              Text(
                'Tap to set limit',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 11,
                ),
              ),
          ],
        ),
        trailing: Switch(
          value: isBlocked,
          onChanged: (value) {
            // Remove limit if strictly blocking
            if (value && _appLimits.containsKey(packageName)) {
              setState(() {
                _appLimits.remove(packageName);
              });
            }
            _toggleBlockApp(packageName, value);
          },
          activeColor: Colors.red,
        ),
        onTap: isBlocked ? null : () => _setAppLimit(packageName, appName, limitMinutes),
      ),
    );
  }
  
  String _formatMinutes(int totalMinutes) {
    if (totalMinutes < 60) return '$totalMinutes min';
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;
    if (minutes == 0) return '$hours hr';
    return '$hours hr $minutes min';
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

/// Dialog to set a time limit for an app.
class _SetLimitDialog extends StatefulWidget {
  final String appName;
  final int? currentLimitMinutes;

  const _SetLimitDialog({
    required this.appName,
    this.currentLimitMinutes,
  });

  @override
  State<_SetLimitDialog> createState() => _SetLimitDialogState();
}

class _SetLimitDialogState extends State<_SetLimitDialog> {
  int _hours = 0;
  int _minutes = 0;

  @override
  void initState() {
    super.initState();
    if (widget.currentLimitMinutes != null) {
      _hours = widget.currentLimitMinutes! ~/ 60;
      _minutes = widget.currentLimitMinutes! % 60;
    } else {
      _hours = 1;
      _minutes = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Set limit for ${widget.appName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Daily time limit before blocking:'),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildNumberPicker(
                label: 'Hours',
                value: _hours,
                min: 0,
                max: 23,
                onChanged: (val) => setState(() => _hours = val),
              ),
              const SizedBox(width: 16),
              const Text(':', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              _buildNumberPicker(
                label: 'Minutes',
                value: _minutes,
                min: 0,
                max: 59,
                step: 5,
                onChanged: (val) => setState(() => _minutes = val),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (widget.currentLimitMinutes != null)
          TextButton(
            onPressed: () => Navigator.pop(context, -1), // -1 signals removal
            child: const Text('Remove Limit', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final totalMinutes = (_hours * 60) + _minutes;
            if (totalMinutes > 0) {
              Navigator.pop(context, totalMinutes);
            }
          },
          child: const Text('Set Limit'),
        ),
      ],
    );
  }

  Widget _buildNumberPicker({
    required String label,
    required int value,
    required int min,
    required int max,
    int step = 1,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_drop_up),
          onPressed: value < max ? () {
            int next = value + step;
            if (next > max) next = max;
            onChanged(next);
          } : null,
        ),
        Text(
          value.toString().padLeft(2, '0'),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_drop_down),
          onPressed: value > min ? () {
            int prev = value - step;
            if (prev < min) prev = min;
            onChanged(prev);
          } : null,
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}
