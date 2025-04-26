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
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('dark_mode') ?? false;
    _esp32Url = prefs.getString('esp32_url');
    notifyListeners();
  }
  
  Future<void> toggleDarkMode() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', _isDarkMode);
    notifyListeners();
  }
  
  Future<void> setEsp32Url(String url) async {
    await ApiService.setEsp32Url(url);
    _esp32Url = url;
    notifyListeners();
  }
}
