import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import '../screens/child/child_home_screen.dart';

class ChildRegisterScreen extends StatefulWidget {
  const ChildRegisterScreen({super.key});

  @override
  State<ChildRegisterScreen> createState() => _ChildRegisterScreenState();
}

class _ChildRegisterScreenState extends State<ChildRegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  Future<void> _register() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // Create child account
      final response = await AuthService().signUp(
        name: name,
        email: email,
        password: password,
      );

      if (response != null) {
        // Save role
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userRole', 'child');

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ChildHomeScreen()),
        );
      }
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Create Child Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Text(
                'Create your account',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 40),
              _input(controller: _nameController, hint: 'Child Name'),
              const SizedBox(height: 16),
              _input(controller: _emailController, hint: 'Email'),
              const SizedBox(height: 16),
              _input(
                controller: _passwordController,
                hint: 'Password',
                obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() => _obscure = !_obscure);
                  },
                ),
              ),
              const SizedBox(height: 28),
              _primaryButton('Create account', _register),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("Already have an account? Login"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(18),
          suffixIcon: suffix,
        ),
      ),
    );
  }

  Widget _primaryButton(String text, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _loading ? null : onTap,
        child: _loading 
          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(text),
      ),
    );
  }
}
