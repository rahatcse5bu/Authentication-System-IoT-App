import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendance/services/api_service.dart';

class SettingsProvider with ChangeNotifier {
  bool _isDarkMode = false;
  String? _esp32Url;
  
  bool get isDarkMode => _isDarkMode;
  String? get esp32Url => _esp32Url;
  
  SettingsProvider() {
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    debugPrint('SettingsProvider: Loading settings');
    
    try {
      // First load local settings
      final prefs = await ApiService.ensureSharedPreferences();
      _isDarkMode = prefs.getBool('dark_mode') ?? false;
      _esp32Url = prefs.getString('esp32_url');
      
      debugPrint('SettingsProvider: Loaded settings from local storage - isDarkMode: $_isDarkMode, esp32Url: $_esp32Url');
      notifyListeners();
      
      // Then try to fetch from server
      try {
        final settings = await ApiService.getSettings();
        debugPrint('SettingsProvider: Loaded settings from server: $settings');
        
        if (settings.containsKey('esp32_url')) {
          _esp32Url = settings['esp32_url'];
          await prefs.setString('esp32_url', _esp32Url ?? '');
          
          // Also update API service
          if (_esp32Url != null && _esp32Url!.isNotEmpty) {
            await ApiService.setEsp32Url(_esp32Url!);
          }
        }
        
        if (settings.containsKey('dark_mode')) {
          _isDarkMode = settings['dark_mode'] ?? false;
          await prefs.setBool('dark_mode', _isDarkMode);
        }
        
        notifyListeners();
      } catch (e) {
        debugPrint('SettingsProvider: Error loading settings from server: $e');
        // Continue with local settings if server is unavailable
      }
    } catch (e) {
      debugPrint('SettingsProvider: Error loading settings: $e');
    }
  }
  
  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await ApiService.ensureSharedPreferences();
    await prefs.setBool('dark_mode', _isDarkMode);
    
    // Also update server settings
    try {
      await ApiService.updateSettings(darkMode: _isDarkMode);
    } catch (e) {
      debugPrint('SettingsProvider: Error updating dark mode setting on server: $e');
    }
    
    notifyListeners();
  }
  
  Future<void> setEsp32Url(String url) async {
    debugPrint('SettingsProvider: Setting ESP32 URL to: $url');
    await ApiService.setEsp32Url(url);
    _esp32Url = url;
    
    // Store locally
    final prefs = await ApiService.ensureSharedPreferences();
    await prefs.setString('esp32_url', url);
    
    notifyListeners();
  }
}
