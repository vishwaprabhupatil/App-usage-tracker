import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/role_selection_screen.dart';
import 'screens/child_entry_screen.dart';
import 'screens/parent_entry_screen.dart';
import 'screens/child/child_home_screen.dart';
import 'theme/theme_controller.dart';
import 'services/foreground_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Initialize foreground sync service
  await ForegroundSyncService.init();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeController(),
      child: Consumer<ThemeController>(
        builder: (context, theme, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            themeMode: theme.themeMode,
            theme: ThemeData(
              brightness: Brightness.light,
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: Colors.black, // AMOLED
              useMaterial3: true,
            ),
            home: const AuthGate(),
            routes: {
              '/role-selection': (_) => const RoleSelectionScreen(),
            },
          );
        },
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Not logged in - show role selection
        if (!snapshot.hasData) {
          return const RoleSelectionScreen();
        }

        // Logged in - check role and navigate accordingly
        return const RoleBasedHome();
      },
    );
  }
}

/// Widget that checks the user's role and shows appropriate screen
class RoleBasedHome extends StatefulWidget {
  const RoleBasedHome({super.key});

  @override
  State<RoleBasedHome> createState() => _RoleBasedHomeState();
}

class _RoleBasedHomeState extends State<RoleBasedHome> {
  String? _role;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('userRole');
    
    // Foreground service will be started from ChildHomeScreen's initState
    
    if (mounted) {
      setState(() {
        _role = role;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Route based on role
    if (_role == 'parent') {
      return const ParentEntryScreen();
    } else if (_role == 'child') {
      return const ChildHomeScreen();
    } else {
      // Role not set - go to role selection
      // This can happen if user was logged in before we added role saving
      return const RoleSelectionScreen();
    }
  }
}
