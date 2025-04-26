import 'package:flutter/foundation.dart';
import 'package:attendance/services/api_service.dart';
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
    debugPrint('AuthProvider.login: Attempting login with $username');
    try {
      final data = await ApiService.login(username, password);
      
      // Check if we actually got a token
      if (data['access'] != null && data['access'].toString().isNotEmpty) {
        _isLoggedIn = true;
        _username = username;
        
        // Save username
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', username);
        
        debugPrint('AuthProvider.login: Login successful');
        notifyListeners();
        return true;
      } else {
        debugPrint('AuthProvider.login: No token received');
        return false;
      }
    } catch (e) {
      debugPrint('AuthProvider.login error: $e');
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
