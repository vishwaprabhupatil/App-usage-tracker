import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // TODO: Paste your Supabase Project URL here
  static const String supabaseUrl = 'https://pirqlipftnxapryxsxgw.supabase.co';

  // TODO: Paste your Supabase Anon Key here
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBpcnFsaXBmdG54YXByeXhzeGd3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4NzExMzQsImV4cCI6MjA5MDQ0NzEzNH0.bqMRR3O85ED8ADu4hDhqc8y86AQmcKhNhSVPC0iK1UU';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}
