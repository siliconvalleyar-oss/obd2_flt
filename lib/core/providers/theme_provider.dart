import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final prefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('prefsProvider must be overridden');
});

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';
  static const _cycle = [ThemeMode.dark, ThemeMode.light, ThemeMode.system];

  @override
  ThemeMode build() => ThemeMode.dark;

  void loadFromPrefs() {
    final prefs = ref.read(prefsProvider);
    final themeString = prefs.getString(_key) ?? 'dark';
    state = switch (themeString) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  void toggle() {
    final currentIndex = _cycle.indexOf(state);
    final newMode = _cycle[(currentIndex + 1) % _cycle.length];
    final modeString = switch (newMode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      _ => 'dark',
    };
    ref.read(prefsProvider).setString(_key, modeString);
    state = newMode;
  }
}
