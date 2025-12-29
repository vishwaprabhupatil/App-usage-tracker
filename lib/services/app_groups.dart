/// App Grouping Definitions for accurate screen time calculation.
///
/// This file defines which Android packages belong to the same logical app.
/// For example, Instagram might use multiple packages for different services,
/// but they should all be counted as "Instagram" usage.

/// Represents a logical app that may consist of multiple Android packages.
class AppGroup {
  /// Unique identifier for this group (e.g., "instagram")
  final String id;

  /// Display name shown in UI (e.g., "Instagram")
  final String displayName;

  /// Exact package names that belong to this group
  final List<String> packages;

  /// Package prefixes - any package starting with these belongs to this group
  final List<String> packagePrefixes;

  /// The primary package to use for fetching app icon
  final String? primaryPackage;

  const AppGroup({
    required this.id,
    required this.displayName,
    this.packages = const [],
    this.packagePrefixes = const [],
    this.primaryPackage,
  });

  /// Check if a package name belongs to this group
  bool matches(String packageName) {
    // Check exact match first
    if (packages.contains(packageName)) return true;

    // Check prefix match
    for (final prefix in packagePrefixes) {
      if (packageName.startsWith(prefix)) return true;
    }

    return false;
  }

  /// Get the best package to use for fetching icon/info
  String get iconPackage => primaryPackage ?? (packages.isNotEmpty ? packages.first : '');
}

/// Central registry of known multi-package apps.
///
/// Add new app groups here as needed. The order matters for matching -
/// more specific groups should come before general ones.
class AppGroupRegistry {
  /// All known app groups
  static const List<AppGroup> groups = [
    // ==================== META APPS ====================

    AppGroup(
      id: 'instagram',
      displayName: 'Instagram',
      packages: [
        'com.instagram.android',
        'com.instagram.barcelona', // Threads-related
        'com.instagram.lite',
      ],
      packagePrefixes: ['com.instagram.'],
      primaryPackage: 'com.instagram.android',
    ),

    AppGroup(
      id: 'facebook',
      displayName: 'Facebook',
      packages: [
        'com.facebook.katana',
        'com.facebook.lite',
        'com.facebook.mlite',
        'com.facebook.appmanager',
      ],
      packagePrefixes: ['com.facebook.katana'],
      primaryPackage: 'com.facebook.katana',
    ),

    AppGroup(
      id: 'messenger',
      displayName: 'Messenger',
      packages: [
        'com.facebook.orca',
        'com.facebook.mlite',
      ],
      primaryPackage: 'com.facebook.orca',
    ),

    AppGroup(
      id: 'whatsapp',
      displayName: 'WhatsApp',
      packages: [
        'com.whatsapp',
        'com.whatsapp.w4b', // WhatsApp Business
      ],
      packagePrefixes: ['com.whatsapp.'],
      primaryPackage: 'com.whatsapp',
    ),

    AppGroup(
      id: 'threads',
      displayName: 'Threads',
      packages: ['com.instagram.barcelona'],
      primaryPackage: 'com.instagram.barcelona',
    ),

    // ==================== GOOGLE APPS ====================

    AppGroup(
      id: 'youtube',
      displayName: 'YouTube',
      packages: [
        'com.google.android.youtube',
        'com.google.android.youtube.tv',
        'com.google.android.youtube.tvkids',
        'com.google.android.youtube.tvmusic',
        'com.google.android.apps.youtube.music',
        'com.google.android.apps.youtube.creator',
        'com.google.android.apps.youtube.kids',
      ],
      primaryPackage: 'com.google.android.youtube',
    ),

    AppGroup(
      id: 'youtube_music',
      displayName: 'YouTube Music',
      packages: ['com.google.android.apps.youtube.music'],
      primaryPackage: 'com.google.android.apps.youtube.music',
    ),

    AppGroup(
      id: 'gmail',
      displayName: 'Gmail',
      packages: ['com.google.android.gm', 'com.google.android.gm.lite'],
      primaryPackage: 'com.google.android.gm',
    ),

    AppGroup(
      id: 'google_maps',
      displayName: 'Google Maps',
      packages: [
        'com.google.android.apps.maps',
        'com.google.android.apps.mapslite',
      ],
      primaryPackage: 'com.google.android.apps.maps',
    ),

    AppGroup(
      id: 'chrome',
      displayName: 'Chrome',
      packages: [
        'com.android.chrome',
        'com.chrome.beta',
        'com.chrome.dev',
        'com.chrome.canary',
      ],
      primaryPackage: 'com.android.chrome',
    ),

    AppGroup(
      id: 'google_photos',
      displayName: 'Google Photos',
      packages: ['com.google.android.apps.photos'],
      primaryPackage: 'com.google.android.apps.photos',
    ),

    AppGroup(
      id: 'google_drive',
      displayName: 'Google Drive',
      packages: ['com.google.android.apps.docs'],
      primaryPackage: 'com.google.android.apps.docs',
    ),

    AppGroup(
      id: 'google_meet',
      displayName: 'Google Meet',
      packages: ['com.google.android.apps.meetings'],
      primaryPackage: 'com.google.android.apps.meetings',
    ),

    AppGroup(
      id: 'google_calendar',
      displayName: 'Google Calendar',
      packages: ['com.google.android.calendar'],
      primaryPackage: 'com.google.android.calendar',
    ),

    AppGroup(
      id: 'google_keep',
      displayName: 'Google Keep',
      packages: ['com.google.android.keep'],
      primaryPackage: 'com.google.android.keep',
    ),

    // ==================== MUSIC & STREAMING ====================

    AppGroup(
      id: 'spotify',
      displayName: 'Spotify',
      packages: [
        'com.spotify.music',
        'com.spotify.lite',
      ],
      packagePrefixes: ['com.spotify.'],
      primaryPackage: 'com.spotify.music',
    ),

    AppGroup(
      id: 'netflix',
      displayName: 'Netflix',
      packages: ['com.netflix.mediaclient', 'com.netflix.ninja'],
      primaryPackage: 'com.netflix.mediaclient',
    ),

    AppGroup(
      id: 'prime_video',
      displayName: 'Prime Video',
      packages: [
        'com.amazon.avod.thirdpartyclient',
        'com.amazon.avod',
      ],
      primaryPackage: 'com.amazon.avod.thirdpartyclient',
    ),

    AppGroup(
      id: 'disney_plus',
      displayName: 'Disney+',
      packages: ['com.disney.disneyplus', 'com.disney.disneyplus.india'],
      primaryPackage: 'com.disney.disneyplus',
    ),

    AppGroup(
      id: 'hotstar',
      displayName: 'Hotstar',
      packages: ['in.startv.hotstar', 'com.hotstar.android'],
      primaryPackage: 'in.startv.hotstar',
    ),

    AppGroup(
      id: 'jiocinema',
      displayName: 'JioCinema',
      packages: ['com.jio.media.ondemand', 'com.jio.jioplay.tv'],
      primaryPackage: 'com.jio.media.ondemand',
    ),

    // ==================== SOCIAL MEDIA ====================

    AppGroup(
      id: 'twitter',
      displayName: 'X (Twitter)',
      packages: ['com.twitter.android', 'com.twitter.android.lite'],
      primaryPackage: 'com.twitter.android',
    ),

    AppGroup(
      id: 'snapchat',
      displayName: 'Snapchat',
      packages: ['com.snapchat.android'],
      primaryPackage: 'com.snapchat.android',
    ),

    AppGroup(
      id: 'tiktok',
      displayName: 'TikTok',
      packages: [
        'com.zhiliaoapp.musically',
        'com.ss.android.ugc.trill',
        'com.tiktok.lite',
      ],
      primaryPackage: 'com.zhiliaoapp.musically',
    ),

    AppGroup(
      id: 'linkedin',
      displayName: 'LinkedIn',
      packages: ['com.linkedin.android', 'com.linkedin.android.lite'],
      primaryPackage: 'com.linkedin.android',
    ),

    AppGroup(
      id: 'reddit',
      displayName: 'Reddit',
      packages: ['com.reddit.frontpage'],
      primaryPackage: 'com.reddit.frontpage',
    ),

    AppGroup(
      id: 'pinterest',
      displayName: 'Pinterest',
      packages: ['com.pinterest', 'com.pinterest.lite'],
      primaryPackage: 'com.pinterest',
    ),

    AppGroup(
      id: 'discord',
      displayName: 'Discord',
      packages: ['com.discord'],
      primaryPackage: 'com.discord',
    ),

    AppGroup(
      id: 'telegram',
      displayName: 'Telegram',
      packages: [
        'org.telegram.messenger',
        'org.telegram.messenger.web',
        'org.thunderdog.chalern', // Telegram X
      ],
      primaryPackage: 'org.telegram.messenger',
    ),

    // ==================== COMMUNICATION ====================

    AppGroup(
      id: 'zoom',
      displayName: 'Zoom',
      packages: ['us.zoom.videomeetings'],
      primaryPackage: 'us.zoom.videomeetings',
    ),

    AppGroup(
      id: 'skype',
      displayName: 'Skype',
      packages: ['com.skype.raider', 'com.skype.m2'],
      primaryPackage: 'com.skype.raider',
    ),

    AppGroup(
      id: 'teams',
      displayName: 'Microsoft Teams',
      packages: [
        'com.microsoft.teams',
        'com.microsoft.teams.personal',
      ],
      primaryPackage: 'com.microsoft.teams',
    ),

    // ==================== MICROSOFT ====================

    AppGroup(
      id: 'outlook',
      displayName: 'Outlook',
      packages: ['com.microsoft.office.outlook'],
      primaryPackage: 'com.microsoft.office.outlook',
    ),

    AppGroup(
      id: 'onedrive',
      displayName: 'OneDrive',
      packages: ['com.microsoft.skydrive'],
      primaryPackage: 'com.microsoft.skydrive',
    ),

    // ==================== SHOPPING ====================

    AppGroup(
      id: 'amazon',
      displayName: 'Amazon',
      packages: [
        'com.amazon.mShop.android.shopping',
        'in.amazon.mShop.android.shopping',
        'com.amazon.windowshop',
      ],
      primaryPackage: 'in.amazon.mShop.android.shopping',
    ),

    AppGroup(
      id: 'flipkart',
      displayName: 'Flipkart',
      packages: ['com.flipkart.android'],
      primaryPackage: 'com.flipkart.android',
    ),

    AppGroup(
      id: 'myntra',
      displayName: 'Myntra',
      packages: ['com.myntra.android'],
      primaryPackage: 'com.myntra.android',
    ),

    // ==================== FOOD DELIVERY ====================

    AppGroup(
      id: 'swiggy',
      displayName: 'Swiggy',
      packages: ['in.swiggy.android'],
      primaryPackage: 'in.swiggy.android',
    ),

    AppGroup(
      id: 'zomato',
      displayName: 'Zomato',
      packages: ['com.application.zomato'],
      primaryPackage: 'com.application.zomato',
    ),

    // ==================== RIDE SHARING ====================

    AppGroup(
      id: 'uber',
      displayName: 'Uber',
      packages: ['com.ubercab', 'com.ubercab.eats'],
      primaryPackage: 'com.ubercab',
    ),

    AppGroup(
      id: 'ola',
      displayName: 'Ola',
      packages: ['com.olacabs.customer'],
      primaryPackage: 'com.olacabs.customer',
    ),

    AppGroup(
      id: 'rapido',
      displayName: 'Rapido',
      packages: ['com.rapido.passenger'],
      primaryPackage: 'com.rapido.passenger',
    ),

    // ==================== PAYMENTS ====================

    AppGroup(
      id: 'gpay',
      displayName: 'Google Pay',
      packages: [
        'com.google.android.apps.nbu.paisa.user',
        'com.google.android.apps.walletnfcrel',
      ],
      primaryPackage: 'com.google.android.apps.nbu.paisa.user',
    ),

    AppGroup(
      id: 'phonepe',
      displayName: 'PhonePe',
      packages: ['com.phonepe.app', 'com.phonepe.app.prepaid'],
      primaryPackage: 'com.phonepe.app',
    ),

    AppGroup(
      id: 'paytm',
      displayName: 'Paytm',
      packages: ['net.one97.paytm'],
      primaryPackage: 'net.one97.paytm',
    ),

    // ==================== SAMSUNG APPS (keep separate) ====================

    AppGroup(
      id: 'samsung_internet',
      displayName: 'Samsung Internet',
      packages: ['com.sec.android.app.sbrowser', 'com.sec.android.app.sbrowser.beta'],
      primaryPackage: 'com.sec.android.app.sbrowser',
    ),

    AppGroup(
      id: 'samsung_notes',
      displayName: 'Samsung Notes',
      packages: ['com.samsung.android.app.notes'],
      primaryPackage: 'com.samsung.android.app.notes',
    ),

    AppGroup(
      id: 'samsung_gallery',
      displayName: 'Gallery',
      packages: ['com.sec.android.gallery3d', 'com.samsung.android.gallery'],
      primaryPackage: 'com.sec.android.gallery3d',
    ),

    AppGroup(
      id: 'samsung_camera',
      displayName: 'Camera',
      packages: ['com.sec.android.app.camera', 'com.samsung.android.app.camera'],
      primaryPackage: 'com.sec.android.app.camera',
    ),

    // ==================== AI & PRODUCTIVITY APPS ====================

    AppGroup(
      id: 'chatgpt',
      displayName: 'ChatGPT',
      packages: ['com.openai.chatgpt'],
      primaryPackage: 'com.openai.chatgpt',
    ),

    AppGroup(
      id: 'gemini',
      displayName: 'Gemini',
      packages: [
        'com.google.android.apps.bard',
        'com.google.android.apps.aicore',
      ],
      primaryPackage: 'com.google.android.apps.bard',
    ),

    AppGroup(
      id: 'claude',
      displayName: 'Claude',
      packages: ['com.anthropic.claude'],
      primaryPackage: 'com.anthropic.claude',
    ),

    AppGroup(
      id: 'copilot',
      displayName: 'Copilot',
      packages: ['com.microsoft.copilot', 'com.microsoft.bing'],
      primaryPackage: 'com.microsoft.copilot',
    ),

    AppGroup(
      id: 'perplexity',
      displayName: 'Perplexity',
      packages: ['ai.perplexity.app.android'],
      primaryPackage: 'ai.perplexity.app.android',
    ),

    AppGroup(
      id: 'notion',
      displayName: 'Notion',
      packages: ['notion.id'],
      primaryPackage: 'notion.id',
    ),

    AppGroup(
      id: 'evernote',
      displayName: 'Evernote',
      packages: ['com.evernote'],
      primaryPackage: 'com.evernote',
    ),

    // ==================== GAMES ====================

    AppGroup(
      id: 'bgmi',
      displayName: 'BGMI',
      packages: ['com.pubg.imobile', 'com.pubg.krmobile', 'com.tencent.ig'],
      primaryPackage: 'com.pubg.imobile',
    ),

    AppGroup(
      id: 'freefire',
      displayName: 'Free Fire',
      packages: ['com.dts.freefireth', 'com.dts.freefiremax'],
      primaryPackage: 'com.dts.freefireth',
    ),

    AppGroup(
      id: 'coc',
      displayName: 'Clash of Clans',
      packages: ['com.supercell.clashofclans'],
      primaryPackage: 'com.supercell.clashofclans',
    ),

    AppGroup(
      id: 'clashroyale',
      displayName: 'Clash Royale',
      packages: ['com.supercell.clashroyale'],
      primaryPackage: 'com.supercell.clashroyale',
    ),

    AppGroup(
      id: 'brawlstars',
      displayName: 'Brawl Stars',
      packages: ['com.supercell.brawlstars'],
      primaryPackage: 'com.supercell.brawlstars',
    ),

    AppGroup(
      id: 'candycrush',
      displayName: 'Candy Crush',
      packages: [
        'com.king.candycrushsaga',
        'com.king.candycrushsodasaga',
        'com.king.candycrushjellysaga',
      ],
      primaryPackage: 'com.king.candycrushsaga',
    ),

    AppGroup(
      id: 'subwaysurfers',
      displayName: 'Subway Surfers',
      packages: ['com.kiloo.subwaysurf'],
      primaryPackage: 'com.kiloo.subwaysurf',
    ),

    AppGroup(
      id: 'roblox',
      displayName: 'Roblox',
      packages: ['com.roblox.client'],
      primaryPackage: 'com.roblox.client',
    ),

    AppGroup(
      id: 'minecraft',
      displayName: 'Minecraft',
      packages: ['com.mojang.minecraftpe'],
      primaryPackage: 'com.mojang.minecraftpe',
    ),

    AppGroup(
      id: 'genshin',
      displayName: 'Genshin Impact',
      packages: ['com.miHoYo.GenshinImpact'],
      primaryPackage: 'com.miHoYo.GenshinImpact',
    ),

    AppGroup(
      id: 'cod_mobile',
      displayName: 'Call of Duty Mobile',
      packages: ['com.activision.callofduty.shooter'],
      primaryPackage: 'com.activision.callofduty.shooter',
    ),

    AppGroup(
      id: 'asphalt',
      displayName: 'Asphalt 9',
      packages: ['com.gameloft.android.ANMP.GloftA9HM'],
      primaryPackage: 'com.gameloft.android.ANMP.GloftA9HM',
    ),

    // ==================== READING & NEWS ====================

    AppGroup(
      id: 'kindle',
      displayName: 'Kindle',
      packages: ['com.amazon.kindle'],
      primaryPackage: 'com.amazon.kindle',
    ),

    AppGroup(
      id: 'inshorts',
      displayName: 'Inshorts',
      packages: ['com.nis.app'],
      primaryPackage: 'com.nis.app',
    ),

    AppGroup(
      id: 'google_news',
      displayName: 'Google News',
      packages: ['com.google.android.apps.magazines'],
      primaryPackage: 'com.google.android.apps.magazines',
    ),

    AppGroup(
      id: 'medium',
      displayName: 'Medium',
      packages: ['com.medium.reader'],
      primaryPackage: 'com.medium.reader',
    ),

    // ==================== HEALTH & FITNESS ====================

    AppGroup(
      id: 'strava',
      displayName: 'Strava',
      packages: ['com.strava'],
      primaryPackage: 'com.strava',
    ),

    AppGroup(
      id: 'samsung_health',
      displayName: 'Samsung Health',
      packages: ['com.sec.android.app.shealth', 'com.samsung.android.app.health'],
      primaryPackage: 'com.sec.android.app.shealth',
    ),

    AppGroup(
      id: 'google_fit',
      displayName: 'Google Fit',
      packages: ['com.google.android.apps.fitness'],
      primaryPackage: 'com.google.android.apps.fitness',
    ),

    // ==================== BANKING ====================

    AppGroup(
      id: 'groww',
      displayName: 'Groww',
      packages: ['com.nextbillion.groww'],
      primaryPackage: 'com.nextbillion.groww',
    ),

    AppGroup(
      id: 'zerodha',
      displayName: 'Zerodha Kite',
      packages: ['com.zerodha.kite3'],
      primaryPackage: 'com.zerodha.kite3',
    ),

    AppGroup(
      id: 'cred',
      displayName: 'CRED',
      packages: ['com.dreamplug.androidapp'],
      primaryPackage: 'com.dreamplug.androidapp',
    ),

    // ==================== UTILITIES (User-facing) ====================

    AppGroup(
      id: 'files_google',
      displayName: 'Files by Google',
      packages: ['com.google.android.apps.nbu.files'],
      primaryPackage: 'com.google.android.apps.nbu.files',
    ),

    AppGroup(
      id: 'calculator',
      displayName: 'Calculator',
      packages: [
        'com.google.android.calculator',
        'com.sec.android.app.popupcalculator',
        'com.android.calculator2',
      ],
      primaryPackage: 'com.google.android.calculator',
    ),

    AppGroup(
      id: 'clock',
      displayName: 'Clock',
      packages: [
        'com.google.android.deskclock',
        'com.sec.android.app.clockpackage',
        'com.android.deskclock',
      ],
      primaryPackage: 'com.google.android.deskclock',
    ),
  ];

  /// Find the AppGroup that matches a given package name.
  /// Returns null if no group matches (standalone app).
  static AppGroup? findGroup(String packageName) {
    for (final group in groups) {
      if (group.matches(packageName)) {
        return group;
      }
    }
    return null;
  }

  /// Get the display name for a package.
  /// Returns the group's display name if found, otherwise null.
  static String? getDisplayName(String packageName) {
    return findGroup(packageName)?.displayName;
  }
}
