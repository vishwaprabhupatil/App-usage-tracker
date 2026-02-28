import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'usage_service.dart';
import 'package_installer_service.dart';

/// Service to automatically sync screen time to Firebase.
/// Runs on app startup and syncs periodically.
class ScreentimeSyncService {
  static Timer? _syncTimer;
  static bool _isRunning = false;
  static const int _maxAppsUpload = 120;
  static const int _maxIconsUpload = 80;

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

      final childData = childDoc.data() ?? <String, dynamic>{};
      final parentId =
          (childData['parentId'] ?? childData['parentUid']) as String?;

      if (!childDoc.exists || parentId == null || parentId.isEmpty) {
        debugPrint('ScreentimeSyncService: Not linked to parent, skipping sync');
        return;
      }

      // Backward compatibility: migrate legacy `parentUid` to `parentId`.
      if (childData['parentId'] == null) {
        await FirebaseFirestore.instance.collection('children').doc(uid).set({
          'parentId': parentId,
        }, SetOptions(merge: true));
      }

      debugPrint('ScreentimeSyncService: Syncing to Firebase...');

      // Get today's usage
      final apps = await UsageService.getTodayUsage();
      final usageUpload = apps.take(_maxAppsUpload).toList();

      final packageMetadata = await PackageInstallerService.getPackageMetadata(
        usageUpload.take(_maxIconsUpload).map((a) => a.packageName).toList(),
        iconSize: 48,
      );

      // Calculate total time
      Duration total = Duration.zero;
      for (final app in usageUpload) {
        total += app.duration;
      }

      // Format total time as "Xh Ym"
      final totalFormatted = _formatDuration(total);

      // Format apps list
      final appsList = usageUpload.map((app) {
        final meta = packageMetadata[app.packageName];
        final Map<String, dynamic> item = {
          'packageName': app.packageName,
          'appName': (meta != null && meta.appName.isNotEmpty)
              ? meta.appName
              : app.appName,
          'duration': _formatDuration(app.duration),
          'openCount': app.openCount,
        };
        if (meta != null &&
            meta.iconBase64 != null &&
            meta.iconBase64!.isNotEmpty) {
          item['icon'] = meta.iconBase64;
        } else if (app.iconBytes != null && app.iconBytes!.isNotEmpty) {
          item['icon'] = base64Encode(app.iconBytes!);
        }
        if (meta != null &&
            meta.installerPackage != null &&
            meta.installerPackage!.isNotEmpty) {
          item['installerPackage'] = meta.installerPackage;
        }
        return item;
      }).toList();

      // Upload to Firebase
      final screentimeRef = FirebaseFirestore.instance.collection('screentime').doc(uid);
      final batch = FirebaseFirestore.instance.batch();

      batch.set(screentimeRef, {
        'totalTime': totalFormatted,
        'apps': appsList,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Keep 30-day daily history updated for weekly/monthly analysis.
      final now = DateTime.now();
      final endHistory = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(seconds: 1)); // End yesterday
      final startHistory = endHistory
          .subtract(const Duration(days: 29)); // Past 30 days including yesterday

      final historyData =
          await UsageService.getDailyUsageForRange(startHistory, endHistory);

      for (final entry in historyData.entries) {
        final dateStr = entry.key;
        final dayApps = entry.value;
        Duration dayTotal = Duration.zero;
        for (final app in dayApps) {
          dayTotal += app.duration;
        }

        final dayRef = screentimeRef.collection('daily').doc(dateStr);
        batch.set(dayRef, {
          'date': dateStr,
          'totalMinutes': dayTotal.inMinutes,
          'apps': dayApps
              .map((a) => {
                    'packageName': a.packageName,
                    'appName': a.appName,
                    'minutes': a.duration.inMinutes,
                    'openCount': a.openCount,
                  })
              .toList(),
        }, SetOptions(merge: true));
      }

      // Save today's provisional data as well.
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final todayRef = screentimeRef.collection('daily').doc(todayStr);
      batch.set(todayRef, {
        'date': todayStr,
        'totalMinutes': total.inMinutes,
        'apps': usageUpload
            .map((a) => {
                  'packageName': a.packageName,
                  'appName': a.appName,
                  'minutes': a.duration.inMinutes,
                  'openCount': a.openCount,
                })
            .toList(),
      }, SetOptions(merge: true));

      await batch.commit();

      debugPrint(
          'ScreentimeSyncService: Synced - $totalFormatted, ${usageUpload.length} apps');

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
