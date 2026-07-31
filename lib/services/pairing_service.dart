import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_config.dart';

class PairingService {
  static final _supabase = SupabaseConfig.client;

  /// Generates a 6-digit pairing code
  static String generatePairingCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  /// Ensures the current parent has a permanent unique 6-digit pairing code.
  /// Returns the existing code if present, otherwise generates and stores a new one.
  static Future<String> ensureParentPairingCode({String? parentName}) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('User not logged in');

    final parentData = await _supabase
        .from('parents')
        .select('pairing_code')
        .eq('id', user.id)
        .maybeSingle();
    
    final existingCode = parentData?['pairing_code']?.toString();

    if (_isValidPairingCode(existingCode)) {
      return existingCode!;
    }

    // Retry bounded times to avoid an infinite loop on unexpected failures.
    for (var attempt = 0; attempt < 20; attempt++) {
      final code = generatePairingCode();
      final existing = await _supabase
          .from('parents')
          .select('id')
          .eq('pairing_code', code)
          .maybeSingle();

      if (existing != null) continue;

      await _supabase.from('parents').upsert({
        'id': user.id,
        'pairing_code': code,
        'name': parentName ?? user.userMetadata?['full_name'] ?? 'Parent',
        'email': user.email,
        'updated_at': DateTime.now().toIso8601String(),
      });

      return code;
    }

    throw Exception('Could not generate a unique pairing code. Please try again.');
  }

  static bool _isValidPairingCode(String? code) {
    if (code == null) return false;
    return RegExp(r'^\d{6}$').hasMatch(code);
  }

  /// Save pairing code for parent
  static Future<String> createParentPairingCode() async {
    return ensureParentPairingCode();
  }

  /// Child uses code to link to parent
  static Future<void> linkChildToParent(
    String pairingCode,
    String deviceName,
  ) async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw Exception('Child not logged in');

    final parentData = await _supabase
        .from('parents')
        .select('id')
        .eq('pairing_code', pairingCode)
        .maybeSingle();

    if (parentData == null) {
      throw Exception('Invalid pairing code');
    }

    final parentId = parentData['id'];

    await _supabase.from('children').upsert({
      'id': user.id,
      'parent_id': parentId,
      'device_name': deviceName,
      'linked_at': DateTime.now().toIso8601String(),
    });
  }
}
