import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'usage_service.dart';

/// Service to automatically sync screen time to Firebase.
/// Runs on app startup and syncs periodically.
class ScreentimeSyncService {
  static Timer? _syncTimer;
  static bool _isRunning = false;

  /// Start automatic syncing (call once on app start for child users)
  static void startAutoSync() {
    if (_isRunning) return;
    _isRunning = true;

    debugPrint('ScreentimeSyncService: Starting auto sync');

    // Sync immediately
    syncNow();

    // Then sync every 5 minutes
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      syncNow();
    });
  }

  /// Stop automatic syncing
  static void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _isRunning = false;
    debugPrint('ScreentimeSyncService: Stopped auto sync');
  }

  /// Sync screen time to Firebase now
  static Future<void> syncNow() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('ScreentimeSyncService: No user logged in');
        return;
      }

      // Check if child is linked to a parent
      final childDoc = await FirebaseFirestore.instance
          .collection('children')
          .doc(uid)
          .get();

      if (!childDoc.exists || childDoc.data()?['parentId'] == null) {
        debugPrint('ScreentimeSyncService: Not linked to parent, skipping sync');
        return;
      }

      debugPrint('ScreentimeSyncService: Syncing to Firebase...');

      // Get today's usage
      final apps = await UsageService.getTodayUsage();

      // Calculate total time
      Duration total = Duration.zero;
      for (final app in apps) {
        total += app.duration;
      }

      // Format total time as "Xh Ym"
      final totalFormatted = _formatDuration(total);

      // Format apps list
      final appsList = apps.map((app) => {
        'packageName': app.packageName,
        'appName': app.appName,
        'duration': _formatDuration(app.duration),
      }).toList();

      // Upload to Firebase
      await FirebaseFirestore.instance.collection('screentime').doc(uid).set({
        'totalTime': totalFormatted,
        'apps': appsList,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      debugPrint('ScreentimeSyncService: Synced - $totalFormatted, ${apps.length} apps');

    } catch (e) {
      debugPrint('ScreentimeSyncService: Error syncing - $e');
    }
  }

  /// Format duration as "Xh Ym" or "Xm"
  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0 && m == 0) return '<1m';
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }
}
