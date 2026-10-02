import 'package:shared_preferences/shared_preferences.dart';

import '../models/news_article.dart';

const kAutoScrollEnabledPref = 'auto_scroll_enabled';

/// Reading time for [a]: 3s + a per-word allowance, clamped to 6-20s.
Duration dwellFor(NewsArticle a) {
  final words = '${a.headline} ${a.snippet}'
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;
  final secs = (3 + words * (a.language == 'bn' ? 0.4 : 0.3)).clamp(6.0, 20.0);
  return Duration(milliseconds: (secs * 1000).round());
}

abstract class AutoScrollStore {
  Future<bool> readEnabled();
  Future<void> writeEnabled(bool enabled);
}

class SharedPreferencesAutoScrollStore implements AutoScrollStore {
  const SharedPreferencesAutoScrollStore();

  @override
  Future<bool> readEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(kAutoScrollEnabledPref) ?? false;

  @override
  Future<void> writeEnabled(bool enabled) async =>
      (await SharedPreferences.getInstance()).setBool(kAutoScrollEnabledPref, enabled);
}
