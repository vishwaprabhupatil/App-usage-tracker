import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// HeartbeatService - Flutter service for heartbeat and restriction management.
/// 
/// DESIGN RATIONALE:
/// -----------------
/// This service acts as a thin wrapper around the native Android implementation.
/// All actual background work happens in Java:
/// - HeartbeatManager handles heartbeat persistence
/// - ServiceHealthWorker handles recovery via WorkManager
/// - RestrictionDetector handles battery/OEM restriction detection
/// 
/// Flutter/Dart only acts as UI and control layer - it does NOT:
/// - Run background tasks
/// - Monitor services
/// - Handle restarts
/// 
/// This ensures compliance with Android background execution policies.
class HeartbeatService {
  static const platform = MethodChannel('com.example.parental_monitor/overlay');
  
  // ===== HEARTBEAT STATUS =====
  
  /// Get comprehensive heartbeat status from native side.
  /// 
  /// Returns a map containing:
  /// - lastHeartbeatTime: timestamp of last heartbeat (ms since epoch)
  /// - serviceStartTime: when the service was last started
  /// - heartbeatCount: total heartbeats recorded
  /// - timeSinceLastHeartbeat: ms since last heartbeat (-1 if never)
  /// - isHealthy: bool indicating if service is healthy
  /// - healthThresholdMs: the threshold used for health check
  /// - heartbeatIntervalMs: interval between heartbeats
  /// - staticServiceRunning: the static flag (may be stale)
  static Future<Map<String, dynamic>> getHeartbeatStatus() async {
    if (!Platform.isAndroid) {
      return _getDefaultHeartbeatStatus();
    }
    
    try {
      final result = await platform.invokeMethod<Map>('getHeartbeatStatus');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (e) {
      debugPrint('HeartbeatService: Error getting heartbeat status: $e');
    }
    return _getDefaultHeartbeatStatus();
  }
  
  static Map<String, dynamic> _getDefaultHeartbeatStatus() {
    return {
      'lastHeartbeatTime': 0,
      'serviceStartTime': 0,
      'heartbeatCount': 0,
      'timeSinceLastHeartbeat': -1,
      'isHealthy': false,
      'healthThresholdMs': 600000, // 10 minutes
      'heartbeatIntervalMs': 180000, // 3 minutes
      'staticServiceRunning': false,
    };
  }
  
  /// Check if the service is currently healthy.
  /// This compares the last heartbeat time against the threshold.
  static Future<bool> isServiceHealthy() async {
    final status = await getHeartbeatStatus();
    return status['isHealthy'] == true;
  }
  
  /// Get the time since the last heartbeat in a human-readable format.
  static Future<String> getTimeSinceLastHeartbeatFormatted() async {
    final status = await getHeartbeatStatus();
    final timeSince = status['timeSinceLastHeartbeat'] as int? ?? -1;
    
    if (timeSince < 0) {
      return 'Never';
    }
    
    if (timeSince < 60000) {
      return '${(timeSince / 1000).round()} seconds ago';
    } else if (timeSince < 3600000) {
      return '${(timeSince / 60000).round()} minutes ago';
    } else {
      return '${(timeSince / 3600000).round()} hours ago';
    }
  }
  
  // ===== RESTRICTION STATUS =====
  
  /// Get comprehensive restriction status from native side.
  /// 
  /// Returns a map containing:
  /// - isIgnoringBatteryOptimizations: bool (true = unrestricted)
  /// - manufacturer: device manufacturer (e.g., "samsung")
  /// - isSamsung: bool
  /// - hasAggressiveOemRestrictions: bool
  /// - androidVersion: int SDK version
  /// - deviceModel: string
  /// - oemInstructions: user-friendly instructions for this OEM
  /// - needsUserAction: bool indicating if user should take action
  static Future<Map<String, dynamic>> getRestrictionStatus() async {
    if (!Platform.isAndroid) {
      return _getDefaultRestrictionStatus();
    }
    
    try {
      final result = await platform.invokeMethod<Map>('getRestrictionStatus');
      if (result != null) {
        return Map<String, dynamic>.from(result);
      }
    } catch (e) {
      debugPrint('HeartbeatService: Error getting restriction status: $e');
    }
    return _getDefaultRestrictionStatus();
  }
  
  static Map<String, dynamic> _getDefaultRestrictionStatus() {
    return {
      'isIgnoringBatteryOptimizations': true,
      'manufacturer': 'unknown',
      'isSamsung': false,
      'hasAggressiveOemRestrictions': false,
      'androidVersion': 0,
      'deviceModel': 'unknown',
      'oemInstructions': '',
      'needsUserAction': false,
    };
  }
  
  /// Check if battery optimization is disabled (app is unrestricted).
  static Future<bool> isBatteryOptimizationDisabled() async {
    final status = await getRestrictionStatus();
    return status['isIgnoringBatteryOptimizations'] == true;
  }
  
  /// Check if this device has aggressive OEM restrictions.
  static Future<bool> hasOemRestrictions() async {
    final status = await getRestrictionStatus();
    return status['hasAggressiveOemRestrictions'] == true;
  }
  
  /// Get OEM-specific instructions for the user.
  static Future<String> getOemInstructions() async {
    final status = await getRestrictionStatus();
    return status['oemInstructions'] as String? ?? '';
  }
  
  // ===== SETTINGS NAVIGATION =====
  
  /// Open the battery optimization settings.
  /// This will show a dialog asking the user to allow unrestricted battery usage.
  static Future<void> openBatterySettings() async {
    if (!Platform.isAndroid) return;
    
    try {
      await platform.invokeMethod('openBatterySettings');
    } catch (e) {
      debugPrint('HeartbeatService: Error opening battery settings: $e');
    }
  }
  
  /// Open OEM-specific settings (e.g., Samsung battery settings).
  static Future<void> openOemSettings() async {
    if (!Platform.isAndroid) return;
    
    try {
      await platform.invokeMethod('openOemSettings');
    } catch (e) {
      debugPrint('HeartbeatService: Error opening OEM settings: $e');
    }
  }
  
  // ===== HEALTH WORKER CONTROL =====
  
  /// Schedule the health worker for ongoing service monitoring.
  /// This is normally called automatically by the service, but can be
  /// called manually if needed.
  static Future<void> scheduleHealthWorker() async {
    if (!Platform.isAndroid) return;
    
    try {
      await platform.invokeMethod('scheduleHealthWorker');
      debugPrint('HeartbeatService: Health worker scheduled');
    } catch (e) {
      debugPrint('HeartbeatService: Error scheduling health worker: $e');
    }
  }
  
  /// Run an immediate health check and recover the service if needed.
  /// Use this on app launch to ensure the service is running.
  static Future<void> runImmediateHealthCheck() async {
    if (!Platform.isAndroid) return;
    
    try {
      await platform.invokeMethod('runImmediateHealthCheck');
      debugPrint('HeartbeatService: Immediate health check completed');
    } catch (e) {
      debugPrint('HeartbeatService: Error running health check: $e');
    }
  }
  
  // ===== CONVENIENCE METHODS =====
  
  /// Get a complete service status summary for display in UI.
  static Future<ServiceStatusSummary> getServiceStatusSummary() async {
    final heartbeat = await getHeartbeatStatus();
    final restrictions = await getRestrictionStatus();
    
    return ServiceStatusSummary(
      isHealthy: heartbeat['isHealthy'] == true,
      lastHeartbeatTime: DateTime.fromMillisecondsSinceEpoch(
        heartbeat['lastHeartbeatTime'] as int? ?? 0
      ),
      heartbeatCount: heartbeat['heartbeatCount'] as int? ?? 0,
      isIgnoringBatteryOptimizations: restrictions['isIgnoringBatteryOptimizations'] == true,
      manufacturer: restrictions['manufacturer'] as String? ?? 'unknown',
      hasOemRestrictions: restrictions['hasAggressiveOemRestrictions'] == true,
      needsUserAction: restrictions['needsUserAction'] == true,
      oemInstructions: restrictions['oemInstructions'] as String? ?? '',
    );
  }
}

/// Data class for service status summary.
class ServiceStatusSummary {
  final bool isHealthy;
  final DateTime lastHeartbeatTime;
  final int heartbeatCount;
  final bool isIgnoringBatteryOptimizations;
  final String manufacturer;
  final bool hasOemRestrictions;
  final bool needsUserAction;
  final String oemInstructions;
  
  ServiceStatusSummary({
    required this.isHealthy,
    required this.lastHeartbeatTime,
    required this.heartbeatCount,
    required this.isIgnoringBatteryOptimizations,
    required this.manufacturer,
    required this.hasOemRestrictions,
    required this.needsUserAction,
    required this.oemInstructions,
  });
  
  /// Check if service has ever been started.
  bool get hasEverStarted => lastHeartbeatTime.millisecondsSinceEpoch > 0;
  
  /// Get a color for the health status.
  Color get healthColor {
    if (!hasEverStarted) return Colors.grey;
    if (isHealthy) return Colors.green;
    return Colors.red;
  }
  
  /// Get a text description of the health status.
  String get healthDescription {
    if (!hasEverStarted) return 'Service never started';
    if (isHealthy) return 'Service is running';
    return 'Service stopped - will recover automatically';
  }
  
  /// Get a text description of battery optimization status.
  String get batteryDescription {
    if (isIgnoringBatteryOptimizations) {
      return 'Battery optimization disabled (good)';
    }
    return 'Battery optimization enabled (may affect reliability)';
  }
  
  /// Get overall reliability score (0-100).
  int get reliabilityScore {
    int score = 50; // Base score
    
    if (isHealthy) score += 30;
    if (isIgnoringBatteryOptimizations) score += 10;
    if (!hasOemRestrictions) score += 10;
    
    return score.clamp(0, 100);
  }
}
