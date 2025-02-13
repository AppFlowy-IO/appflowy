import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/startup/tasks/device_info_task.dart';
import 'package:auto_updater/auto_updater.dart';
import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:universal_platform/universal_platform.dart';
import 'package:xml/xml.dart' as xml;

final versionChecker = VersionChecker();

/// Version checker class to handle update checks using appcast XML feeds
class VersionChecker {
  factory VersionChecker() => _instance;

  VersionChecker._internal();
  String? _feedUrl;

  static final VersionChecker _instance = VersionChecker._internal();

  /// Sets the appcast XML feed URL
  void setFeedUrl(String url) {
    _feedUrl = url;

    if (UniversalPlatform.isWindows || UniversalPlatform.isMacOS) {
      autoUpdater.setFeedURL(url);
      // disable the auto update check
      autoUpdater.setScheduledCheckInterval(0);
    }
  }

  /// Checks for updates by fetching and parsing the appcast XML
  /// Returns a list of [AppcastItem] or throws an exception if the feed URL is not set
  Future<AppcastItem?> checkForUpdateInformation() async {
    if (_feedUrl == null) {
      throw Exception('Feed URL not set. Call setFeedUrl() first.');
    }

    try {
      final response = await http.get(Uri.parse(_feedUrl!));
      if (response.statusCode != 200) {
        throw Exception('Failed to fetch appcast feed');
      }

      // Parse XML content
      final document = xml.XmlDocument.parse(response.body);
      final items = document.findAllElements('item');

      // Convert XML items to AppcastItem objects
      return items
          .map(_parseAppcastItem)
          .nonNulls
          .firstWhereOrNull((e) => e.os == ApplicationInfo.os);
    } catch (e) {
      throw Exception('Error checking for updates: $e');
    }
  }

  /// For Windows and macOS, calling this API will trigger the auto updater to check for updates
  /// For Linux, it will open the official website in the browser if there is a new version

  Future<void> checkForUpdate() async {
    if (UniversalPlatform.isLinux) {
      // open the official website in the browser
      await afLaunchUrlString('https://appflowy.com/download');
    } else {
      await autoUpdater.checkForUpdates();
    }
  }

  AppcastItem? _parseAppcastItem(xml.XmlElement item) {
    final enclosure = item.findElements('enclosure').firstOrNull;
    return AppcastItem.fromJson({
      'title': item.findElements('title').firstOrNull?.innerText,
      'versionString': item
          .findElements('sparkle:shortVersionString')
          .firstOrNull
          ?.innerText,
      'displayVersionString': item
          .findElements('sparkle:shortVersionString')
          .firstOrNull
          ?.innerText,
      'releaseNotesUrl':
          item.findElements('releaseNotesLink').firstOrNull?.innerText,
      'pubDate': item.findElements('pubDate').firstOrNull?.innerText,
      'fileURL': enclosure?.getAttribute('url') ?? '',
      'os': enclosure?.getAttribute('sparkle:os') ?? '',
      'criticalUpdate':
          enclosure?.getAttribute('sparkle:criticalUpdate') ?? false,
    });
  }
}
