import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PackageInstallerMeta {
  final String appName;
  final String? iconBase64;
  final String? installerPackage;

  const PackageInstallerMeta({
    required this.appName,
    this.iconBase64,
    this.installerPackage,
  });
}

class PackageInstallerService {
  static const MethodChannel _channel =
      MethodChannel('com.example.parental_monitor/overlay');

  static Future<Map<String, PackageInstallerMeta>> getPackageMetadata(
    List<String> packages, {
    int iconSize = 48,
  }) async {
    if (packages.isEmpty) return {};

    try {
      final dynamic raw = await _channel.invokeMethod(
        'getPackageInstallerMetadata',
        {
          'packages': packages,
          'iconSize': iconSize,
        },
      );

      final Map<String, PackageInstallerMeta> out = {};
      if (raw is! Map) return out;

      raw.forEach((key, value) {
        final pkg = key?.toString();
        if (pkg == null || pkg.isEmpty || value is! Map) return;
        out[pkg] = PackageInstallerMeta(
          appName: value['appName']?.toString() ?? pkg,
          iconBase64: value['iconBase64']?.toString(),
          installerPackage: value['installerPackage']?.toString(),
        );
      });

      return out;
    } catch (e) {
      debugPrint('PackageInstallerService: metadata fetch failed - $e');
      return {};
    }
  }
}

