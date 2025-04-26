// lib/services/api_service.dart
// Updated to correctly handle face recognition attendance marking

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/attendance.dart';
import '../models/profile.dart';

class ApiService {
  static const String _baseUrl = 'http://127.0.0.1:8000/api';
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
      Uri.parse('$_baseUrl/token/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
debugPrint('Login response: ${response.body}');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      _token = data['access'];
      
      // Save token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_token', _token!);
      await prefs.setString('username', username);
      
      return data;
    } else {
      throw Exception('Failed to login: ${response.body}');
    }
  }

  static Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('username');
  }

  // Profile Management
  static Future<List<Profile>> getProfiles() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/profiles/'),
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
      Uri.parse('$_baseUrl/profiles/$id/'),
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
    var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/profiles/register_with_face/'));
    
    // Add auth headers
    request.headers.addAll(_getAuthHeaders());
    
    // Add profile data
    request.fields['name'] = profile.name;
    request.fields['email'] = profile.email;
    request.fields['blood_group'] = profile.bloodGroup;
    request.fields['reg_number'] = profile.regNumber;
    request.fields['university'] = profile.university;
    
    // Check if using ESP32
    if (_esp32Url != null && _esp32Url!.isNotEmpty) {
      request.fields['use_esp32'] = 'true';
      request.fields['esp32_url'] = _esp32Url!;
    } else {
      // Add image
      request.files.add(await http.MultipartFile.fromPath(
        'image', 
        imageFile.path,
      ));
    }
    
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
    // Create multipart request
    var request = http.MultipartRequest(
      'PUT', 
      Uri.parse('$_baseUrl/profiles/${profile.id}/update_face/')
    );
    
    // Add auth headers
    request.headers.addAll(_getAuthHeaders());
    
    // Add profile data
    request.fields['name'] = profile.name;
    request.fields['email'] = profile.email;
    request.fields['blood_group'] = profile.bloodGroup;
    request.fields['reg_number'] = profile.regNumber;
    request.fields['university'] = profile.university;
    request.fields['is_active'] = profile.isActive.toString();
    
    // Check if using ESP32 or image file
    if (imageFile != null) {
      request.files.add(await http.MultipartFile.fromPath(
        'image', 
        imageFile.path,
      ));
    } else if (_esp32Url != null && _esp32Url!.isNotEmpty) {
      request.fields['use_esp32'] = 'true';
      request.fields['esp32_url'] = _esp32Url!;
    }
    
    // Send request
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 200) {
      return Profile.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to update profile: ${response.body}');
    }
  }

  static Future<bool> deleteProfile(String id) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/profiles/$id/'),
      headers: _getAuthHeaders(),
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      return true;
    } else {
      throw Exception('Failed to delete profile: ${response.body}');
    }
  }

  // Attendance Management
  static Future<List<Attendance>> getAttendance({String? date, String? profileId}) async {
    var uri = Uri.parse('$_baseUrl/attendance/');
    
    // Add query parameters if provided
    final queryParams = <String, String>{};
    if (date != null) queryParams['date'] = date;
    if (profileId != null) queryParams['profile_id'] = profileId;
    
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

  // This is the fixed method for face recognition attendance
  static Future<Map<String, dynamic>> markAttendanceWithFaceRecognition() async {
    final response = await http.post(
      Uri.parse('$_baseUrl/attendance/mark_attendance/'),
      headers: _getAuthHeaders(),
      body: jsonEncode({
        'esp32_url': _esp32Url,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to mark attendance: ${response.body}');
    }
  }

  // This is the method for marking attendance with a profile ID
  static Future<Attendance> markAttendance(String profileId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/attendance/'),
      headers: _getAuthHeaders(),
      body: jsonEncode({'profile_id': profileId}),
    );

    if (response.statusCode == 201) {
      return Attendance.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to mark attendance: ${response.body}');
    }
  }
// ESP32 Camera Image Capture
static Future<File> captureImage() async {
  if (_esp32Url == null || _esp32Url!.isEmpty) {
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
  static Future<List<Map<String, dynamic>>> getAttendanceReport({
    required String reportType,
    required String startDate,
    String? endDate,
    String? profileId,
  }) async {
    var uri = Uri.parse('$_baseUrl/attendance/reports/');
    
    // Add query parameters
    final queryParams = <String, String>{
      'type': reportType,
      'start_date': startDate,
    };
    
    if (endDate != null) queryParams['end_date'] = endDate;
    if (profileId != null) queryParams['profile_id'] = profileId;
    
    uri = uri.replace(queryParameters: queryParams);

    final response = await http.get(
      uri,
      headers: _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data);
    } else {
      throw Exception('Failed to get attendance report: ${response.body}');
    }
  }

  // Settings Management
  static Future<Map<String, dynamic>> getSettings() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/settings/my_settings/'),
      headers: _getAuthHeaders(),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get settings: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> updateSettings({
    String? esp32Url,
    bool? darkMode,
  }) async {
    final Map<String, dynamic> data = {};
    if (esp32Url != null) data['esp32_url'] = esp32Url;
    if (darkMode != null) data['dark_mode'] = darkMode;

    final response = await http.patch(
      Uri.parse('$_baseUrl/settings/update_settings/'),
      headers: _getAuthHeaders(),
      body: jsonEncode(data),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update settings: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> testEsp32Connection(String url) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/settings/test_esp32/'),
      headers: _getAuthHeaders(),
      body: jsonEncode({'esp32_url': url}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to test ESP32 connection: ${response.body}');
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