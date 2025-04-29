// lib/services/api_service.dart
// Updated to correctly handle face recognition attendance marking

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import '../models/attendance.dart';
import '../models/profile.dart';
import '../utils/constants.dart';
import '../providers/settings_provider.dart';
import '../providers/profile_provider.dart';
import '../services/face_detection_service.dart';
import '../services/api_service_fix.dart';

class ApiService {
  static String get _baseUrl => Constants.baseApiUrl;
  static String? _token;
  static String? _esp32Url;

  // Initialize with saved settings
  static Future<void> initialize() async {
    debugPrint('ApiService.initialize: Starting initialization');
    debugPrint('ApiService.initialize: Base URL: $_baseUrl');
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('auth_token');
      _esp32Url = prefs.getString('esp32_url');
      
      debugPrint('ApiService.initialize: Loaded token and ESP32 URL from preferences');
      debugPrint('ApiService.initialize: ESP32 URL set to: $_esp32Url');
      
      if (_token != null) {
        debugPrint('ApiService.initialize: Authorization token loaded');
      } else {
        debugPrint('ApiService.initialize: No authorization token found');
      }

      // Test connection to the server
      try {
        final response = await http.get(Uri.parse('$_baseUrl/')).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException('Server connection test timed out');
          },
        );
        debugPrint('ApiService.initialize: Server connection test successful');
        debugPrint('ApiService.initialize: Server response: ${response.statusCode}');
      } catch (e) {
        debugPrint('ApiService.initialize: Server connection test failed: $e');
        throw Exception('Could not connect to server at $_baseUrl. Please check if the server is running.');
      }
    } catch (e) {
      debugPrint('ApiService.initialize error: $e');
      rethrow;
    }
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
    debugPrint('Attempting login with username: $username');
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/token/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
      
      debugPrint('Login response status code: ${response.statusCode}');
      debugPrint('Login response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['access'];
        debugPrint('Login successful, token received');
        
        // Save token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        await prefs.setString('username', username);
        
        return data;
      } else {
        debugPrint('Login failed with status code: ${response.statusCode}');
        throw Exception('Failed to login: ${response.body}');
      }
    } catch (e) {
      debugPrint('Login error: $e');
      throw Exception('Login error: $e');
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
    debugPrint('getProfiles: Fetching all profiles');
    debugPrint('getProfiles: Using base URL: $_baseUrl');
    debugPrint('getProfiles: Auth token: ${_token != null ? "Present" : "Missing"}');
    
    try {
      final uri = Uri.parse('$_baseUrl/profiles/');
      debugPrint('getProfiles: Full URL: $uri');
      
      final headers = _getAuthHeaders();
      debugPrint('getProfiles: Request headers: $headers');
      
      final response = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 10), onTimeout: () {
            debugPrint('getProfiles: Request timed out after 10 seconds');
            throw TimeoutException('Request timed out');
          });

      debugPrint('getProfiles: Response status: ${response.statusCode}');
      debugPrint('getProfiles: Response headers: ${response.headers}');
      debugPrint('getProfiles: Response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final List<dynamic> data = jsonDecode(response.body);
          debugPrint('getProfiles: Successfully parsed ${data.length} profiles');
          return data.map((json) => Profile.fromJson(json)).toList();
        } catch (e) {
          debugPrint('getProfiles: Error parsing response: $e');
          throw Exception('Error parsing profiles data: $e');
        }
      } else if (response.statusCode == 401) {
        debugPrint('getProfiles: Unauthorized - Token might be invalid or expired');
        throw Exception('Unauthorized - Please login again');
      } else if (response.statusCode == 404) {
        debugPrint('getProfiles: Endpoint not found - Check API URL');
        throw Exception('API endpoint not found - Check server configuration');
      } else {
        debugPrint('getProfiles: Unexpected status code: ${response.statusCode}');
        throw Exception('Failed to load profiles: ${response.body}');
      }
    } catch (e) {
      debugPrint('getProfiles: Network error: $e');
      if (e is SocketException) {
        throw Exception('Network error: Could not connect to server. Check if the server is running and accessible.');
      } else if (e is TimeoutException) {
        throw Exception('Network error: Request timed out. Check your internet connection and server status.');
      } else {
        throw Exception('Error loading profiles: $e');
      }
    }
  }

  static Future<Profile> getProfileById(String id) async {
    debugPrint('getProfileById: Fetching profile with ID: $id');
    final response = await http.get(
      Uri.parse('$_baseUrl/profiles/$id/'),
      headers: _getAuthHeaders(),
    );

    debugPrint('getProfileById: Response status: ${response.statusCode}');
    debugPrint('getProfileById: Response body: ${response.body}');

    if (response.statusCode == 200) {
      return Profile.fromJson(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load profile: ${response.body}');
    }
  }

  static Future<Profile> createProfile(Profile profile, List<File> imageFiles) async {
    debugPrint('createProfile: Starting profile creation');
    try {
      // Validate image files
      if (imageFiles.isEmpty) {
        throw Exception('At least one face image is required');
      }
      
      if (imageFiles.length > 15) {
        throw Exception('Maximum of 15 face images allowed');
      }
      
      for (var imageFile in imageFiles) {
        if (!await imageFile.exists()) {
          throw Exception('Image file does not exist at path: ${imageFile.path}');
        }
      }
      
      // Create multipart request for the profile with images
      var request = http.MultipartRequest('POST', Uri.parse('$_baseUrl/profiles/register_with_face/'));
      
      // Add auth headers
      final headers = _getAuthHeaders(isMultipart: true);
      debugPrint('createProfile: Using auth headers: $headers');
      request.headers.addAll(headers);
      
      // Add profile data
      debugPrint('createProfile: Adding profile data');
      request.fields['name'] = profile.name;
      request.fields['email'] = profile.email;
      request.fields['reg_number'] = profile.regNumber;
      
      // Optional fields
      if (profile.bloodGroup.isNotEmpty) {
        request.fields['blood_group'] = profile.bloodGroup;
      }
      if (profile.university.isNotEmpty) {
        request.fields['university'] = profile.university;
      }
      
      // Add all face images
      for (var i = 0; i < imageFiles.length; i++) {
        final imageFile = imageFiles[i];
        debugPrint('createProfile: Adding image ${i + 1} from file: ${imageFile.path}');
        try {
          final bytes = await imageFile.readAsBytes();
          
          // First image is also sent as 'image' for backward compatibility
          if (i == 0) {
            request.files.add(
              http.MultipartFile.fromBytes(
                'image',
                bytes,
                filename: imageFile.path.split('/').last,
                contentType: MediaType('image', 'jpeg'),
              )
            );
          }
          
          // All images are sent as 'face_images'
          request.files.add(
            http.MultipartFile.fromBytes(
              'face_images',
              bytes,
              filename: imageFile.path.split('/').last,
              contentType: MediaType('image', 'jpeg'),
            )
          );
        } catch (e) {
          debugPrint('createProfile: Error reading image file: $e');
          throw Exception('Error reading image file: $e');
        }
      }
      
      // Send request
      debugPrint('createProfile: Sending request to ${request.url}');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      debugPrint('createProfile: Response status: ${response.statusCode}');
      debugPrint('createProfile: Response body: ${response.body}');
      
      if (response.statusCode == 201) {
        final profileJson = jsonDecode(response.body);
        debugPrint('createProfile: Profile created successfully');
        return Profile.fromJson(profileJson);
      } else if (response.statusCode == 400 && response.body.toLowerCase().contains('no face')) {
        // Face detection error from backend
        debugPrint('createProfile: Backend reported no face or face detection error');
        throw Exception('The server could not detect faces in the provided images. Please try with clearer images that show faces clearly.');
      } else {
        throw Exception('Failed to create profile: ${response.body}');
      }
    } catch (e) {
      debugPrint('createProfile error: $e');
      throw Exception('Error creating profile: $e');
    }
  }

  static Future<Profile> updateProfile(Profile profile, {File? imageFile}) async {
    debugPrint('updateProfile: Starting profile update for ID: ${profile.id}');
    try {
      // Decide whether to use PATCH (no image update) or PUT (with image update)
      final String method = imageFile == null ? 'PATCH' : 'PUT';
      debugPrint('updateProfile: Using $method method for update');
      
      // For PATCH with no image, use regular JSON request
      if (method == 'PATCH' && imageFile == null) {
        final Map<String, dynamic> data = {
          'name': profile.name,
          'email': profile.email,
          'blood_group': profile.bloodGroup,
          'reg_number': profile.regNumber,
          'university': profile.university,
          'is_active': profile.isActive,
        };
        
        debugPrint('updateProfile: Sending PATCH request with data: $data');
        final response = await http.patch(
          Uri.parse('$_baseUrl/profiles/${profile.id}/'),
          headers: _getAuthHeaders(),
          body: jsonEncode(data),
        );
        
        debugPrint('updateProfile: Response status: ${response.statusCode}');
        debugPrint('updateProfile: Response body: ${response.body}');
        
        if (response.statusCode == 200) {
          final profileJson = jsonDecode(response.body);
          debugPrint('updateProfile: Profile updated successfully via PATCH');
          return Profile.fromJson(profileJson);
        } else {
          throw Exception('Failed to update profile: ${response.body}');
        }
      }
      
      // Otherwise proceed with multipart request for image upload
      var request = http.MultipartRequest(
        method, 
        Uri.parse('$_baseUrl/profiles/${profile.id}/')
      );
      
      // Add auth headers
      final headers = _getAuthHeaders(isMultipart: true);
      debugPrint('updateProfile: Using auth headers: $headers');
      request.headers.addAll(headers);
      
      // Add profile data
      debugPrint('updateProfile: Adding profile data');
      request.fields['name'] = profile.name;
      request.fields['email'] = profile.email;
      request.fields['blood_group'] = profile.bloodGroup;
      request.fields['reg_number'] = profile.regNumber;
      request.fields['university'] = profile.university;
      request.fields['is_active'] = profile.isActive.toString();
      
      // Add ESP32 info if available
      if (_esp32Url != null && _esp32Url!.isNotEmpty) {
        debugPrint('updateProfile: Using ESP32 camera: $_esp32Url');
        request.fields['use_esp32'] = 'true';
        request.fields['esp32_url'] = _esp32Url!;
      }
      
      // Add image file if provided
      if (imageFile != null) {
        // Verify image file exists
        if (await imageFile.exists()) {
          debugPrint('updateProfile: Using image file from path: ${imageFile.path}');
          try {
            final bytes = await imageFile.readAsBytes();
            debugPrint('updateProfile: Successfully read ${bytes.length} bytes from image file');
            
            request.files.add(
              http.MultipartFile.fromBytes(
                'image',
                bytes,
                filename: imageFile.path.split('/').last,
                contentType: MediaType('image', 'jpeg'),
              )
            );
          } catch (e) {
            debugPrint('updateProfile: Error reading image file: $e');
            throw Exception('Error reading image file: $e');
          }
        } else {
          debugPrint('updateProfile: Image file does not exist at path: ${imageFile.path}');
          throw Exception('Image file does not exist at path: ${imageFile.path}');
        }
      } else {
        debugPrint('updateProfile: No new image provided, using existing image');
        // No image field is sent, so the server will keep the existing image
      }
      
      // Send request
      debugPrint('updateProfile: Sending request to ${request.url}');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      debugPrint('updateProfile: Response status: ${response.statusCode}');
      debugPrint('updateProfile: Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final profileJson = jsonDecode(response.body);
        debugPrint('updateProfile: Profile updated successfully');
        return Profile.fromJson(profileJson);
      } else {
        throw Exception('Failed to update profile: ${response.body}');
      }
    } catch (e) {
      debugPrint('updateProfile error: $e');
      throw Exception('Error updating profile: $e');
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

  // Face Recognition method to scan and recognize a face
  static Future<Map<String, dynamic>> recognizeFace() async {
    debugPrint('recognizeFace: Starting face recognition');
    
    if (_esp32Url == null || _esp32Url!.isEmpty) {
      debugPrint('recognizeFace: ESP32 URL is not configured');
      throw Exception('ESP32 camera URL not configured');
    }
    
    debugPrint('recognizeFace: Using ESP32 URL: $_esp32Url');
    
    try {
      final requestBody = {'esp32_url': _esp32Url};
      debugPrint('recognizeFace: Request body: $requestBody');
      
      final response = await http.post(
        Uri.parse('$_baseUrl/recognition/recognize_face/'),
        headers: _getAuthHeaders(),
        body: jsonEncode(requestBody),
      );
      
      debugPrint('recognizeFace: Response status: ${response.statusCode}');
      debugPrint('recognizeFace: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('recognizeFace: Face recognition completed');
        return data;
      } else {
        debugPrint('recognizeFace: Failed to recognize face: ${response.body}');
        throw Exception('Failed to recognize face: ${response.body}');
      }
    } catch (e) {
      debugPrint('recognizeFace error: $e');
      throw Exception('Error recognizing face: $e');
    }
  }

  // This is the fixed method for face recognition attendance
  static Future<Map<String, dynamic>> markAttendanceWithFaceRecognition(File imageFile, String? esp32Url) async {
    try {
      debugPrint('markAttendanceWithFaceRecognition: Delegating to ApiServiceFix');
      final token = await _getAuthToken();
      
      if (token == null) {
        debugPrint('markAttendanceWithFaceRecognition: Authentication token is null. Please log in again.');
        throw Exception('Authentication required. Please log in again.');
      }
      
      // Log token format (first few characters)
      debugPrint('markAttendanceWithFaceRecognition: Using token format: ${token.length > 5 ? token.substring(0, 5) + "..." : token}');
      
      // Use the fixed implementation that tries multiple endpoints
      return await ApiServiceFix.markAttendanceWithFaceRecognition(imageFile, esp32Url, token);
    } catch (e) {
      debugPrint('markAttendanceWithFaceRecognition error: $e');
      rethrow;
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
      debugPrint('captureImage: Attempting to capture from ESP32 camera at: $_esp32Url');
      
      // Try different endpoints in order of reliability
      List<String> endpointsToTry = [];
      
      // Try /capture endpoint first
      if (!_esp32Url!.toLowerCase().contains("capture")) {
        if (_esp32Url!.endsWith("/")) {
          endpointsToTry.add('${_esp32Url}capture');
        } else {
          endpointsToTry.add('${_esp32Url}/capture');
        }
      }
      
      // Then try base URL
      endpointsToTry.add(_esp32Url!);
      
      // Then try /jpg endpoint 
      if (!_esp32Url!.toLowerCase().contains("jpg")) {
        if (_esp32Url!.endsWith("/")) {
          endpointsToTry.add('${_esp32Url}jpg');
        } else {
          endpointsToTry.add('${_esp32Url}/jpg');
        }
      }
      
      // Also try /camera/snapshot endpoint (some ESP32 cams use this)
      if (_esp32Url!.endsWith("/")) {
        endpointsToTry.add('${_esp32Url}camera/snapshot');
      } else {
        endpointsToTry.add('${_esp32Url}/camera/snapshot');
      }
      
      Exception? lastException;
      
      for (final url in endpointsToTry) {
        try {
          debugPrint('captureImage: Trying endpoint: $url');
          
          final response = await http.get(Uri.parse(url))
            .timeout(const Duration(seconds: 5), onTimeout: () {
              debugPrint('captureImage: Timeout on endpoint $url');
              throw TimeoutException('Camera timeout');
            });
          
          if (response.statusCode == 200 && response.bodyBytes.length > 100) {
            // Check if data looks like an image
            if (_isValidImage(response.bodyBytes)) {
              // Save the image to application documents directory for better persistence
              final appDir = await getApplicationDocumentsDirectory();
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              final imageFile = File('${appDir.path}/esp32_captured_$timestamp.jpg');
              await imageFile.writeAsBytes(response.bodyBytes);
              
              debugPrint('captureImage: Image saved to ${imageFile.path}, size: ${response.bodyBytes.length} bytes');
              return imageFile;
            } else {
              debugPrint('captureImage: Invalid image data from $url');
              continue; // Try next endpoint
            }
          } else {
            debugPrint('captureImage: Invalid response from $url: ${response.statusCode}, size: ${response.bodyBytes.length}');
          }
        } catch (e) {
          debugPrint('captureImage: Error with endpoint $url: $e');
          lastException = e as Exception;
          // Try next endpoint
          continue;
        }
      }
      
      // If we get here, all endpoints failed
      throw lastException ?? Exception('Failed to capture image from any endpoint');
    } catch (e) {
      debugPrint('captureImage error: $e');
      throw Exception('Error connecting to ESP32 camera: $e');
    }
  }
  
  // Helper method to check if data is a valid image
  static bool _isValidImage(Uint8List bytes) {
    // Check for JPEG signature at start of file
    if (bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return true;
    }
    
    // Check for common HTML patterns that indicate we got a webpage instead of an image
    if (bytes.length > 15) {
      String start = String.fromCharCodes(bytes.sublist(0, 15).where((c) => c >= 32 && c < 127));
      if (start.toLowerCase().contains('<!doctype') || 
          start.toLowerCase().contains('<html') ||
          start.toLowerCase().contains('<?xml')) {
        debugPrint('API Service: Detected HTML content instead of image');
        return false;
      }
    }
    
    // If we can't definitively say it's bad, let's try it as an image
    return bytes.length > 1000; // At least some reasonable size for an image
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

  // Method to regenerate face embeddings for a specific profile
  static Future<Map<String, dynamic>> regenerateFaceEmbedding(String profileId) async {
    debugPrint('regenerateFaceEmbedding: Starting regeneration for profile $profileId');
    
    if (_esp32Url == null || _esp32Url!.isEmpty) {
      debugPrint('regenerateFaceEmbedding: ESP32 URL is not configured');
      throw Exception('ESP32 camera URL not configured');
    }
    
    try {
      final requestBody = {
        'profile_id': profileId,
        'esp32_url': _esp32Url
      };
      
      debugPrint('regenerateFaceEmbedding: Request body: $requestBody');
      
      final response = await http.post(
        Uri.parse('$_baseUrl/recognition/regenerate_face_embedding/'),
        headers: _getAuthHeaders(),
        body: jsonEncode(requestBody),
      );
      
      debugPrint('regenerateFaceEmbedding: Response status: ${response.statusCode}');
      debugPrint('regenerateFaceEmbedding: Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('regenerateFaceEmbedding: Face embedding regenerated successfully');
        return data;
      } else {
        debugPrint('regenerateFaceEmbedding: Failed to regenerate face embedding: ${response.body}');
        throw Exception('Failed to regenerate face embedding: ${response.body}');
      }
    } catch (e) {
      debugPrint('regenerateFaceEmbedding error: $e');
      throw Exception('Error regenerating face embedding: $e');
    }
  }
  
  // Method to regenerate face embeddings for all profiles
  static Future<Map<String, dynamic>> regenerateAllFaceEmbeddings() async {
    debugPrint('regenerateAllFaceEmbeddings: Starting regeneration for all profiles');
    
    if (_esp32Url == null || _esp32Url!.isEmpty) {
      debugPrint('regenerateAllFaceEmbeddings: ESP32 URL is not configured');
      throw Exception('ESP32 camera URL not configured');
    }
    
    try {
      final requestBody = {
        'esp32_url': _esp32Url
      };
      
      debugPrint('regenerateAllFaceEmbeddings: Request body: $requestBody');
      
      final response = await http.post(
        Uri.parse('$_baseUrl/recognition/regenerate_all_face_embeddings/'),
        headers: _getAuthHeaders(),
        body: jsonEncode(requestBody),
      );
      
      debugPrint('regenerateAllFaceEmbeddings: Response status: ${response.statusCode}');
      debugPrint('regenerateAllFaceEmbeddings: Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('regenerateAllFaceEmbeddings: All face embeddings regenerated successfully');
        return data;
      } else {
        debugPrint('regenerateAllFaceEmbeddings: Failed to regenerate all face embeddings: ${response.body}');
        throw Exception('Failed to regenerate all face embeddings: ${response.body}');
      }
    } catch (e) {
      debugPrint('regenerateAllFaceEmbeddings error: $e');
      throw Exception('Error regenerating all face embeddings: $e');
    }
  }

  // Helpers
  static Map<String, String> _getAuthHeaders({bool isMultipart = false}) {
    if (_token == null) {
      throw Exception('Not authenticated');
    }
    
    if (isMultipart) {
      // For multipart requests, we should not set content-type as it will be set automatically
      return {
        'Authorization': 'Bearer $_token',
      };
    } else {
      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };
    }
  }

  // Helper method to get the authentication token
  static Future<String?> _getToken() async {
    // Return cached token if available
    if (_token != null) {
      return _token;
    }
    
    // Try to load token from preferences
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('auth_token');
      return _token;
    } catch (e) {
      debugPrint('_getToken error: $e');
      return null;
    }
  }
  
  // For backward compatibility - aliases to _getToken
  static Future<String?> _getAuthToken() async {
    return _getToken();
  }

  // Get the latest image from ESP32 camera for preview
  static Future<Uint8List?> getEsp32CameraPreview() async {
    if (_esp32Url == null || _esp32Url!.isEmpty) {
      debugPrint('getEsp32CameraPreview: ESP32 URL not configured');
      return null;
    }
    
    // List of endpoints to try in order of preference
    List<String> endpointsToTry = [];
    
    // Try /capture endpoint first
    if (!_esp32Url!.toLowerCase().contains("capture")) {
      if (_esp32Url!.endsWith("/")) {
        endpointsToTry.add('${_esp32Url}capture');
      } else {
        endpointsToTry.add('${_esp32Url}/capture');
      }
    }
    
    // Then try base URL
    endpointsToTry.add(_esp32Url!);
    
    // Try /jpg endpoint
    if (!_esp32Url!.toLowerCase().contains("jpg")) {
      if (_esp32Url!.endsWith("/")) {
        endpointsToTry.add('${_esp32Url}jpg');
      } else {
        endpointsToTry.add('${_esp32Url}/jpg');
      }
    }
    
    // Also try /camera/snapshot endpoint (used by some ESP32 camera software)
    if (_esp32Url!.endsWith("/")) {
      endpointsToTry.add('${_esp32Url}camera/snapshot');
    } else {
      endpointsToTry.add('${_esp32Url}/camera/snapshot');
    }
    
    for (final url in endpointsToTry) {
      try {
        debugPrint('getEsp32CameraPreview: Fetching image from: $url');
        
        final response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 5), onTimeout: () {
            debugPrint('getEsp32CameraPreview: Timeout on $url');
            throw TimeoutException('Preview timeout');
          });
        
        if (response.statusCode == 200 && response.bodyBytes.length > 100) {
          debugPrint('getEsp32CameraPreview: Successfully received image from $url, size: ${response.bodyBytes.length} bytes');
          return response.bodyBytes;
        } else {
          debugPrint('getEsp32CameraPreview: Invalid response from $url: ${response.statusCode}, body size: ${response.bodyBytes.length}');
        }
      } catch (e) {
        debugPrint('getEsp32CameraPreview: Error fetching from $url: $e');
        // Continue to next endpoint
      }
    }
    
    debugPrint('getEsp32CameraPreview: All endpoints failed');
    return null;
  }

  static Future<Profile> addFaceImages(String profileId, List<File> imageFiles) async {
    debugPrint('addFaceImages: Starting to add face images for profile: $profileId');
    try {
      // Validate image files
      if (imageFiles.isEmpty) {
        throw Exception('At least one face image is required');
      }
      
      if (imageFiles.length > 15) {
        throw Exception('Maximum of 15 face images allowed');
      }
      
      for (var imageFile in imageFiles) {
        if (!await imageFile.exists()) {
          throw Exception('Image file does not exist at path: ${imageFile.path}');
        }
      }
      
      // Create multipart request
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse('$_baseUrl/profiles/$profileId/add_face_images/')
      );
      
      // Add auth headers
      final headers = _getAuthHeaders(isMultipart: true);
      request.headers.addAll(headers);
      
      // Add face images
      for (var i = 0; i < imageFiles.length; i++) {
        final imageFile = imageFiles[i];
        debugPrint('addFaceImages: Adding image ${i + 1} from file: ${imageFile.path}');
        try {
          final bytes = await imageFile.readAsBytes();
          request.files.add(
            http.MultipartFile.fromBytes(
              'face_images',
              bytes,
              filename: imageFile.path.split('/').last,
              contentType: MediaType('image', 'jpeg'),
            )
          );
        } catch (e) {
          debugPrint('addFaceImages: Error reading image file: $e');
          throw Exception('Error reading image file: $e');
        }
      }
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      debugPrint('addFaceImages: Response status: ${response.statusCode}');
      debugPrint('addFaceImages: Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        // Get the updated profile after adding images
        return await getProfileById(profileId);
      } else if (response.statusCode == 400 && response.body.toLowerCase().contains('no face')) {
        // Face detection error from backend
        debugPrint('addFaceImages: Backend reported no face or face detection error');
        throw Exception('The server could not detect faces in the provided images. Please try with clearer images that show faces clearly.');
      } else {
        throw Exception('Failed to add face images: ${response.body}');
      }
    } catch (e) {
      debugPrint('addFaceImages error: $e');
      throw Exception('Error adding face images: $e');
    }
  }

  // Check if an image contains a face
  static Future<bool> checkFace(File imageFile) async {
    debugPrint('checkFace: Checking if image contains a face');
    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication token is null');
      }
      
      final uri = Uri.parse('$_baseUrl/profiles/check_face/');
      final request = http.MultipartRequest('POST', uri);
      
      // Add auth header
      request.headers.addAll({
        'Authorization': 'Bearer $token',
      });
      
      // Add image file
      final bytes = await imageFile.readAsBytes();
      final file = http.MultipartFile.fromBytes(
        'image', 
        bytes,
        filename: 'face_image.jpg',
        contentType: MediaType('image', 'jpeg'),
      );
      request.files.add(file);
      
      debugPrint('checkFace: Sending request to $uri');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode != 200) {
        final errorBody = response.body;
        debugPrint('checkFace error: ${response.statusCode}, $errorBody');
        return false;
      }
      
      final responseData = jsonDecode(response.body);
      final hasFace = responseData['has_face'] ?? false;
      
      debugPrint('checkFace: Has face: $hasFace');
      return hasFace;
    } catch (e) {
      debugPrint('checkFace error: $e');
      return false;
    }
  }
}