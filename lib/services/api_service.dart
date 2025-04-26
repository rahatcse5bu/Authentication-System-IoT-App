import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:attendance_app/models/profile.dart';
import 'package:attendance_app/models/attendance.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String _baseUrl = 'https://your-backend-api.com/api';
  static String? _token;
  static String? _esp32Url;

  // Initialize with saved settings
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('auth_token');
    _esp32Url = prefs.getString('esp32_url');
  }

  // Configure ESP32 Camera URL
  static Future<void> setEsp32Url(String url) async {
    _esp32Url = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp32_url', url);
  }

  static String? get esp32Url => _esp32Url;

  // Authentication
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _token = data['token'];
      
      // Save token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', _token!);
      
      return data;
    } else {
      throw Exception('Failed to login: ${response.body}');
    }
  }

  static Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  // Profile Management
  static Future<List<Profile>> getProfiles() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/profiles'),
      headers: _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Profile.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load profiles: ${response.body}');
    }
  }

  static Future<Profile> getProfileById(String id) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/profiles/$id'),
      headers: _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return Profile.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load profile: ${response.body}');
    }
  }

  static Future<Profile> createProfile(Profile profile, File imageFile) async {
    // Create multipart request for the profile with image
    var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/profiles'));
    
    // Add auth headers
    request.headers.addAll(_getAuthHeaders());
    
    // Add profile data
    request.fields['profileData'] = jsonEncode(profile.toJson());
    
    // Add image
    request.files.add(await http.MultipartFile.fromPath(
      'profileImage', 
      imageFile.path,
    ));
    
    // Send request
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 201) {
      return Profile.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to create profile: ${response.body}');
    }
  }

  static Future<Profile> updateProfile(Profile profile, {File? imageFile}) async {
    if (imageFile == null) {
      // Simple JSON update without image
      final response = await http.put(
        Uri.parse('$_baseUrl/profiles/${profile.id}'),
        headers: _getAuthHeaders(),
        body: jsonEncode(profile.toJson()),
      );

      if (response.statusCode == 200) {
        return Profile.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to update profile: ${response.body}');
      }
    } else {
      // Multipart request with image
      var request = http.MultipartRequest('PUT', Uri.parse('$_baseUrl/profiles/${profile.id}'));
      
      // Add auth headers
      request.headers.addAll(_getAuthHeaders());
      
      // Add profile data
      request.fields['profileData'] = jsonEncode(profile.toJson());
      
      // Add image
      request.files.add(await http.MultipartFile.fromPath(
        'profileImage', 
        imageFile.path,
      ));
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        return Profile.fromJson(jsonDecode(response.body));
      } else {
        throw Exception('Failed to update profile: ${response.body}');
      }
    }
  }

  static Future<bool> deleteProfile(String id) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/profiles/$id'),
      headers: _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Failed to delete profile: ${response.body}');
    }
  }

  // Attendance Management
  static Future<List<Attendance>> getAttendance({String? date, String? profileId}) async {
    var uri = Uri.parse('$_baseUrl/attendance');
    
    // Add query parameters if provided
    final queryParams = <String, String>{};
    if (date != null) queryParams['date'] = date;
    if (profileId != null) queryParams['profileId'] = profileId;
    
    if (queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }

    final response = await http.get(
      uri,
      headers: _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((json) => Attendance.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load attendance: ${response.body}');
    }
  }

  static Future<Attendance> markAttendance(String profileId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/attendance'),
      headers: _getAuthHeaders(),
      body: jsonEncode({'profileId': profileId}),
    );

    if (response.statusCode == 201) {
      return Attendance.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to mark attendance: ${response.body}');
    }
  }

  // ESP32 Camera Integration
  static Future<File> captureImage() async {
    if (_esp32Url == null) {
      throw Exception('ESP32 camera URL not configured');
    }

    try {
      final response = await http.get(Uri.parse(_esp32Url!));
      
      if (response.statusCode == 200) {
        // Save the image to temporary file
        final tempDir = Directory.systemTemp;
        final tempFile = File('${tempDir.path}/captured_image_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tempFile.writeAsBytes(response.bodyBytes);
        return tempFile;
      } else {
        throw Exception('Failed to capture image from ESP32 camera: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to ESP32 camera: $e');
    }
  }

  // Helpers
  static Map<String, String> _getAuthHeaders() {
    if (_token == null) {
      throw Exception('Not authenticated');
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_token',
    };
  }
}
