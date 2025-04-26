import 'package:flutter/foundation.dart';
import 'package:attendance_app/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  bool _isLoggedIn = false;
  String _username = '';
  
  bool get isLoggedIn => _isLoggedIn;
  String get username => _username;
  
  AuthProvider() {
    _checkLoginStatus();
  }
  
  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    if (token != null) {
      _isLoggedIn = true;
      _username = prefs.getString('username') ?? '';
      notifyListeners();
    }
  }
  
  Future<bool> login(String username, String password) async {
    try {
      final data = await ApiService.login(username, password);
      _isLoggedIn = true;
      _username = username;
      
      // Save username
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', username);
      
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  Future<void> logout() async {
    await ApiService.logout();
    _isLoggedIn = false;
    _username = '';
    notifyListeners();
  }
}
