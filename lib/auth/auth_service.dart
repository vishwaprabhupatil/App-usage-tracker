import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';

class AuthService {
  final SupabaseClient _supabase = SupabaseConfig.client;

  // SIGN UP
  Future<User?> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': name},
    );
    return response.user;
  }

  // LOGIN
  Future<User?> login({
    required String email,
    required String password,
  }) async {
    final response = await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
    return response.user;
  }

  // LOGOUT (later use)
  Future<void> logout() async {
    await _supabase.auth.signOut();
  }
}