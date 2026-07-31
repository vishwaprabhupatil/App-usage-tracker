import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';

import 'usage_service.dart';
import 'package_installer_service.dart';

/// Service to automatically sync screen time to Supabase.
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
      final user = SupabaseConfig.client.auth.currentUser;
      if (user == null) {
        debugPrint('ScreentimeSyncService: No user logged in');
        return;
      }

      final uid = user.id;

      // Check if child is linked to a parent
      final childData = await SupabaseConfig.client
          .from('children')
          .select('parent_id')
          .eq('id', uid)
          .maybeSingle();

      if (childData == null) {
        debugPrint('ScreentimeSyncService: Not linked to parent, skipping sync');
        return;
      }

      final parentId = childData['parent_id'] as String?;

      if (parentId == null || parentId.isEmpty) {
        debugPrint('ScreentimeSyncService: Not linked to parent, skipping sync');
        return;
      }

      debugPrint('ScreentimeSyncService: Syncing to Supabase...');

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

      // Upload current screentime status
      await SupabaseConfig.client.from('screentime').upsert({
        'id': uid,
        'total_time': totalFormatted,
        'apps': appsList,
        'last_updated': DateTime.now().toIso8601String(),
      });

      // Keep 30-day daily history updated
      final now = DateTime.now();
      final endHistory = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(seconds: 1)); // End yesterday
      final startHistory = endHistory
          .subtract(const Duration(days: 29)); // Past 30 days including yesterday

      final historyData =
          await UsageService.getDailyUsageForRange(startHistory, endHistory);

      final List<Map<String, dynamic>> dailyUsageUpserts = [];

      for (final entry in historyData.entries) {
        final dateStr = entry.key;
        final dayApps = entry.value;
        Duration dayTotal = Duration.zero;
        for (final app in dayApps) {
          dayTotal += app.duration;
        }

        dailyUsageUpserts.add({
          'child_id': uid,
          'date': dateStr,
          'total_minutes': dayTotal.inMinutes,
          'apps': dayApps
              .map((a) => {
                    'packageName': a.packageName,
                    'appName': a.appName,
                    'minutes': a.duration.inMinutes,
                    'openCount': a.openCount,
                  })
              .toList(),
        });
      }

      // Add today's provisional data
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      dailyUsageUpserts.add({
        'child_id': uid,
        'date': todayStr,
        'total_minutes': total.inMinutes,
        'apps': usageUpload
            .map((a) => {
                  'packageName': a.packageName,
                  'appName': a.appName,
                  'minutes': a.duration.inMinutes,
                  'openCount': a.openCount,
                })
            .toList(),
      });

      // Bulk upsert to daily_usage table
      if (dailyUsageUpserts.isNotEmpty) {
         await SupabaseConfig.client.from('daily_usage').upsert(
           dailyUsageUpserts,
           onConflict: 'child_id, date'
         );
      }

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
