import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full-screen overlay shown when child tries to use a blocked app.
class BlockedAppOverlay extends StatelessWidget {
  final String? packageName;
  final String? appName;
  final VoidCallback? onGoHome;

  const BlockedAppOverlay({
    super.key,
    this.packageName,
    this.appName,
    this.onGoHome,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Prevent back button from dismissing
        if (!didPop) {
          _goToHome();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.red.shade900,
                  Colors.black,
                ],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Lock icon
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                  child: const Icon(
                    Icons.block,
                    size: 80,
                    color: Colors.white,
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // Title
                const Text(
                  'App Blocked',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Subtitle
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    appName != null 
                        ? '$appName has been blocked by your parent'
                        : 'This app has been blocked by your parent',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 18,
                    ),
                  ),
                ),
                
                const SizedBox(height: 48),
                
                // Info text
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    'Ask your parent to unblock this app if you need to use it.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                ),
                
                const SizedBox(height: 48),
                
                // Go Home button
                ElevatedButton.icon(
                  onPressed: () {
                    if (onGoHome != null) {
                      onGoHome!();
                    } else {
                      _goToHome();
                    }
                  },
                  icon: const Icon(Icons.home),
                  label: const Text('Go to Home Screen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red.shade900,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _goToHome() {
    // Send user to home screen
    const platform = MethodChannel('com.example.parental_monitor/overlay');
    platform.invokeMethod('goToHome').catchError((e) {
      debugPrint('BlockedAppOverlay: Error going to home: $e');
    });
  }
}
