import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/usage_service.dart';
import '../../services/usage_permission_service.dart';
import '../../services/foreground_sync_service.dart';
import '../../services/screentime_sync_service.dart';
import '../../services/app_blocker_service.dart';
import '../../theme/theme_controller.dart';
import '../../auth/auth_service.dart';
import 'theme_settings_screen.dart';
import 'parent_link_screen.dart';

class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen>
    with WidgetsBindingObserver {
  Duration _screenTime = Duration.zero;
  List<AppUsage> _apps = [];
  bool _loading = true;
  bool _permissionDenied = false;
  bool _overlayPermissionGranted = false;
  bool _batteryOptimizationExempted = false;
  Timer? _healthCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadUsage();
    // Start foreground sync service after screen is initialized
    // This ensures notification permission is requested after home screen appears
    _startForegroundService();
    // Initialize app blocker
    _initAppBlocker();
    // Start periodic health check for services
    _startServiceHealthCheck();
  }

  Future<void> _startForegroundService() async {
    // Delay slightly to ensure the home screen is fully visible
    await Future.delayed(const Duration(milliseconds: 500));
    final started = await ForegroundSyncService.startService();

    if (started) {
      // Foreground path is available, no need for in-app timer fallback.
      ScreentimeSyncService.stopAutoSync();
      await ForegroundSyncService.triggerSyncNow();
    } else {
      // Fallback for devices that block/kill foreground service.
      ScreentimeSyncService.startAutoSync();
      await ScreentimeSyncService.syncNow();
    }
    
    // After notification permission is handled, check for overlay permission
    // and show a dialog if needed
    await _showOverlayPermissionDialogIfNeeded();
  }

  Future<void> _showOverlayPermissionDialogIfNeeded() async {
    final hasPermission = await AppBlockerService.hasOverlayPermission();
    if (!hasPermission && mounted) {
      // Show dialog to explain and request overlay permission
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.security, color: Colors.orange),
              SizedBox(width: 12),
              Expanded(child: Text('Permission Required')),
            ],
          ),
          content: const Text(
            'To enable app blocking features, please allow "Display over other apps" permission.\n\n'
            'This allows the app to show a blocking screen when restricted apps are opened.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await AppBlockerService.requestOverlayPermission();
              },
              child: const Text('Enable Now'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _healthCheckTimer?.cancel();
    ScreentimeSyncService.stopAutoSync();
    // Note: AppBlockerService.dispose() is async but we don't await it in dispose
    // The service will clean itself up
    AppBlockerService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadUsage();
      // Trigger immediate sync with direct-write fallback if service is down.
      ForegroundSyncService.triggerSyncNow();
      // Check overlay permission
      _checkOverlayPermission();
      // Check battery optimization
      _checkBatteryOptimization();
      // Restart health check when app resumes
      _startServiceHealthCheck();
      // Also run an immediate health check
      _checkAndRestartServices();
    } else if (state == AppLifecycleState.paused) {
      // Keep the timer running in background - don't cancel
    }
  }

  Future<void> _initAppBlocker() async {
    await AppBlockerService.init();
    await _checkOverlayPermission();
    await _checkBatteryOptimization();
    
    // Start the blocker service if permission is granted and there are blocked apps
    if (_overlayPermissionGranted && AppBlockerService.blockedApps.isNotEmpty) {
      await AppBlockerService.startBlockerService();
    }
  }

  Future<void> _checkOverlayPermission() async {
    final hasPermission = await AppBlockerService.hasOverlayPermission();
    if (mounted) {
      setState(() {
        _overlayPermissionGranted = hasPermission;
      });
    }
  }

  Future<void> _checkBatteryOptimization() async {
    final hasExemption = await AppBlockerService.hasBatteryOptimizationExemption();
    if (mounted) {
      setState(() {
        _batteryOptimizationExempted = hasExemption;
      });
    }
  }
  
  /// Start periodic service health check (every 5 minutes)
  void _startServiceHealthCheck() {
    _healthCheckTimer?.cancel();
    // Check every 5 minutes when app is running
    _healthCheckTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _checkAndRestartServices();
    });
    // Also run immediately
    _checkAndRestartServices();
  }
  
  /// Check if all services are running and restart if needed
  Future<void> _checkAndRestartServices() async {
    debugPrint('ChildHome: Running service health check...');
    
    // Check if foreground sync service is running
    final isForegroundRunning = await ForegroundSyncService.isRunning();
    if (!isForegroundRunning) {
      debugPrint('ChildHome: Foreground service not running - restarting');
      final started = await ForegroundSyncService.startService();
      if (!started) {
        // Keep syncing while app is open on restrictive devices.
        ScreentimeSyncService.startAutoSync();
      } else {
        ScreentimeSyncService.stopAutoSync();
      }
    } else {
      ScreentimeSyncService.stopAutoSync();
    }
    
    // Check native services status
    final status = await AppBlockerService.checkAllServicesStatus();
    final isBlockerRunning = status['appBlockerRunning'] as bool? ?? false;
    
    if (!isBlockerRunning) {
      debugPrint('ChildHome: AppBlockerService not running - restarting');
      await AppBlockerService.startBlockerService();
    }
    
    // Ensure watchdog is scheduled
    await AppBlockerService.startWatchdog();
    
    debugPrint('ChildHome: Health check complete - foreground: $isForegroundRunning, blocker: $isBlockerRunning');
  }

  Future<void> _loadUsage() async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
    });

    final hasPermission = await UsagePermissionService.hasPermission();

    if (!hasPermission) {
      setState(() {
        _permissionDenied = true;
        _loading = false;
      });
      return;
    }

    final apps = await UsageService.getTodayUsage();

    Duration total = Duration.zero;
    for (final app in apps) {
      total += app.duration;
    }

    debugPrint('UI: Loaded ${apps.length} apps');

    setState(() {
      _screenTime = total;
      _apps = apps;
      _loading = false;
    });
  }

  String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0 && m == 0) {
      return '<1m';
    }
    return h == 0 ? '${m}m' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    final isDark = themeController.mode == AppThemeMode.dark ||
        (themeController.mode == AppThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // Exit the app when back button is pressed
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Screen Time'),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadUsage,
            tooltip: 'Refresh',
          ),
          // Menu button with theme, link parent, logout
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More options',
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
                value: 'link_parent',
                child: Row(
                  children: [
                    Icon(Icons.link, size: 20),
                    SizedBox(width: 12),
                    Text('Link to Parent'),
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
      body: _buildBody(),
      ),
    );
  }

  void _handleMenuAction(String action, BuildContext context) {
    switch (action) {
      case 'theme':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ThemeSettingsScreen()),
        );
        break;
      case 'link_parent':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ParentLinkScreen()),
        );
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
              // Stop the foreground sync service
              await ForegroundSyncService.stopService();
              ScreentimeSyncService.stopAutoSync();
              await AuthService().logout();
              if (context.mounted) {
                // Navigate to role selection and clear stack
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      );
    }

    if (_permissionDenied) {
      return _buildPermissionDenied();
    }

    if (_apps.isEmpty) {
      return _buildEmptyState();
    }

    return _buildUsageList();
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Usage Access Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Grant Usage Access permission in Settings.',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('Open Settings'),
              onPressed: () => UsagePermissionService.openUsageAccessSettings(),
            ),
            const SizedBox(height: 12),
            TextButton(
              child: const Text('I\'ve granted permission'),
              onPressed: _loadUsage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.hourglass_empty, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No usage data yet',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Use some apps and check back!',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              onPressed: _loadUsage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageList() {
    return RefreshIndicator(
      onRefresh: _loadUsage,
      child: CustomScrollView(
        slivers: [
          // Battery optimization warning
          if (!_batteryOptimizationExempted)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.battery_alert, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Battery Optimization Active',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Disable battery optimization to keep monitoring active',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await AppBlockerService.requestBatteryOptimizationExemption();
                      },
                      child: const Text('Disable'),
                    ),
                  ],
                ),
              ),
            ),
          
          // Overlay permission warning
          if (!_overlayPermissionGranted && AppBlockerService.blockedApps.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Overlay Permission Required',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Enable "Display over other apps" for app blocking to work',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _showOverlayPermissionDialogIfNeeded,
                      child: const Text('Enable'),
                    ),
                  ],
                ),
              ),
            ),
          
          // Header
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
                    _format(_screenTime),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_apps.length} apps',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // Section header
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

          // App list
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildAppTile(_apps[index]),
              childCount: _apps.length,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildAppTile(AppUsage app) {
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
        leading: _buildAppIcon(app),
        title: Text(
          app.appName,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _getUsageColor(app.duration).withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _format(app.duration),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: _getUsageColor(app.duration),
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAppIcon(AppUsage app) {
    // Use REAL icon from PackageManager
    if (app.hasIcon) {
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
            app.iconBytes!,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return _buildFallbackIcon(app.appName);
            },
          ),
        ),
      );
    }

    return _buildFallbackIcon(app.appName);
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
      Colors.cyan,
      Colors.green,
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  Color _getUsageColor(Duration duration) {
    if (duration.inHours >= 2) return Colors.red;
    if (duration.inHours >= 1) return Colors.orange;
    if (duration.inMinutes >= 30) return Colors.amber[700]!;
    return Colors.green;
  }
}
