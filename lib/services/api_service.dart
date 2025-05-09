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
  static SharedPreferences? _sharedPreferences;
  // Default ESP32 camera URL to use when none is configured
  static const String defaultEsp32Url = "http://192.168.1.100:81";

  // Initialize with saved settings
  static Future<void> initialize() async {
    debugPrint('Initializing ApiService');
    
    try {
      // Initialize SharedPreferences
      _sharedPreferences = await _ensureSharedPreferences();
      
      // Try to load ESP32 URL from preferences
      _esp32Url = _sharedPreferences!.getString('esp32_url') ?? defaultEsp32Url;
      
      // Ensure ESP32 URL is not empty
      if (_esp32Url == null || _esp32Url!.isEmpty) {
        _esp32Url = defaultEsp32Url;
        await _sharedPreferences!.setString('esp32_url', _esp32Url!);
      }
      
      debugPrint('ESP32 URL initialized to: $_esp32Url');
      
      // Test server connection
      await testServerConnection();
      
      // Load token
      await _getAuthToken();
    } catch (e) {
      debugPrint('Error initializing ApiService: $e');
      // Set default ESP32 URL if there was an error
      _esp32Url = defaultEsp32Url;
    }
  }

  /// Tests the connection to the server
  static Future<void> testServerConnection() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/')).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Server connection test timed out');
        },
      );
      debugPrint('Server connection test successful: ${response.statusCode}');
    } catch (e) {
      debugPrint('Server connection test failed: $e');
      throw Exception('Could not connect to server at $_baseUrl');
    }
  }

  // Ensure shared preferences are initialized
  static Future<SharedPreferences> _ensureSharedPreferences() async {
    if (_sharedPreferences == null) {
      _sharedPreferences = await SharedPreferences.getInstance();
    }
    return _sharedPreferences!;
  }

  // Public method to ensure SharedPreferences is initialized
  static Future<SharedPreferences> ensureSharedPreferences() async {
    return _ensureSharedPreferences();
  }

  // Get auth token synchronously, ensuring SharedPreferences is initialized
  static String? _getAuthTokenSync() {
    if (_token == null && _sharedPreferences != null) {
      _token = _sharedPreferences!.getString('auth_token');
    }
    return _token;
  }

  // Configure ESP32 Camera URL
  static Future<void> setEsp32Url(String url) async {
    debugPrint('ApiService: Setting ESP32 URL to: $url');
    
    // Ensure URL is not empty
    if (url.isEmpty) {
      url = defaultEsp32Url;
      debugPrint('ApiService: Empty URL provided, using default: $url');
    }
    
    _esp32Url = url;
    final prefs = await _ensureSharedPreferences();
    await prefs.setString('esp32_url', url);
    debugPrint('ApiService: ESP32 URL saved: $_esp32Url');
  }

  static String? get esp32Url => _esp32Url;

  // Authentication
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final url = '$_baseUrl/token/';
    debugPrint('Attempting login with username: $username');
    
    final payload = {
      'username': username, 
      'password': password
    };
    
    try {
      _logApiCall(
        method: 'POST',
        url: url,
        payload: payload,
      );
      
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      
      _logApiCall(
        method: 'POST',
        url: url,
        response: response,
        statusCode: response.statusCode,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['access'];
        debugPrint('Login successful, token received');
        
        // Save token
        final prefs = await _ensureSharedPreferences();
        await prefs.setString('auth_token', _token!);
        await prefs.setString('username', username);
        
        return data;
      } else {
        debugPrint('Login failed with status code: ${response.statusCode}');
        throw Exception('Failed to login: ${response.body}');
      }
    } catch (e) {
      _logApiCall(
        method: 'POST',
        url: url,
        payload: payload,
        error: e.toString(),
      );
      debugPrint('Login error: $e');
      throw Exception('Login error: $e');
    }
  }

  static Future<void> logout() async {
    _token = null;
    final prefs = await _ensureSharedPreferences();
    await prefs.remove('auth_token');
    await prefs.remove('username');
  }

  // Profile Management
  static Future<List<Profile>> getProfiles() async {
    final url = '$_baseUrl/profiles/';
    debugPrint('getProfiles: Fetching all profiles');
    
    try {
      final uri = Uri.parse(url);
      debugPrint('getProfiles: Full URL: $uri');
      
      final headers = _getAuthHeaders();
      
      _logApiCall(
        method: 'GET',
        url: url,
      );
      
      final response = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 10), onTimeout: () {
            debugPrint('getProfiles: Request timed out after 10 seconds');
            throw TimeoutException('Request timed out');
          });

      _logApiCall(
        method: 'GET',
        url: url,
        response: response,
        statusCode: response.statusCode,
      );

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
      _logApiCall(
        method: 'GET',
        url: url,
        error: e.toString(),
      );
      
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

  static Future<Profile> updateProfile(
    String id, {
    String? name,
    String? email,
    String? bloodGroup,
    String? regNumber,
    String? university,
    bool? isActive,
    File? imageFile,
  }) async {
    debugPrint('updateProfile: Starting profile update for ID: $id');
    try {
      // Prepare the data for update
      final Map<String, dynamic> data = {};
      if (name != null) data['name'] = name;
      if (email != null) data['email'] = email;
      if (bloodGroup != null) data['blood_group'] = bloodGroup;
      if (regNumber != null) data['reg_number'] = regNumber;
      if (university != null) data['university'] = university;
      if (isActive != null) data['is_active'] = isActive;
      
      // For PATCH with no image, use regular JSON request
      if (imageFile == null) {
        debugPrint('updateProfile: Sending PATCH request with data: $data');
        final response = await http.patch(
          Uri.parse('$_baseUrl/profiles/$id/'),
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
        'PUT', 
        Uri.parse('$_baseUrl/profiles/$id/')
      );
      
      // Add auth headers
      final headers = _getAuthHeaders(isMultipart: true);
      debugPrint('updateProfile: Using auth headers: $headers');
      request.headers.addAll(headers);
      
      // Add profile data
      debugPrint('updateProfile: Adding profile data');
      if (name != null) request.fields['name'] = name;
      if (email != null) request.fields['email'] = email;
      if (bloodGroup != null) request.fields['blood_group'] = bloodGroup;
      if (regNumber != null) request.fields['reg_number'] = regNumber;
      if (university != null) request.fields['university'] = university;
      if (isActive != null) request.fields['is_active'] = isActive.toString();
      
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
    final url = '$_baseUrl/attendance/mark_attendance/';
    
    try {
      debugPrint('markAttendanceWithFaceRecognition: Delegating to ApiServiceFix');
      final token = await _getAuthToken();
      
      if (token == null) {
        debugPrint('markAttendanceWithFaceRecognition: Authentication token is null. Please log in again.');
        throw Exception('Authentication required. Please log in again.');
      }
      
      // Log token format (first few characters)
      debugPrint('markAttendanceWithFaceRecognition: Using token format: ${token.length > 5 ? token.substring(0, 5) + "..." : token}');
      
      // Log the request details
      _logApiCall(
        method: 'POST (Face Recognition)',
        url: url,
        payload: {
          'verification_method': 'face',
          'image_file_path': imageFile.path,
          'esp32_url': esp32Url ?? 'Not provided',
          'token_prefix': token.substring(0, token.length > 10 ? 10 : token.length) + '...',
        },
      );
      
      // Use the fixed implementation that tries multiple endpoints
      final result = await ApiServiceFix.markAttendanceWithFaceRecognition(imageFile, esp32Url, token);
      
      // Log the response
      _logApiCall(
        method: 'POST (Face Recognition)',
        url: url,
        response: result,
      );
      
      return result;
    } catch (e) {
      // Log the error
      _logApiCall(
        method: 'POST (Face Recognition)',
        url: url,
        error: e.toString(),
      );
      
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
              try {
                // Save the image to application documents directory for better persistence
                final appDir = await getApplicationDocumentsDirectory();
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final imageFile = File('${appDir.path}/esp32_captured_$timestamp.jpg');
                await imageFile.writeAsBytes(response.bodyBytes);
                
                debugPrint('captureImage: Image saved to ${imageFile.path}, size: ${response.bodyBytes.length} bytes');
                return imageFile;
              } catch (e) {
                debugPrint('captureImage: Error saving image: $e');
                
                // Fallback for web platform or if saving fails
                final tempDir = await getTemporaryDirectory();
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final imageFile = File('${tempDir.path}/esp32_temp_$timestamp.jpg');
                await imageFile.writeAsBytes(response.bodyBytes);
                debugPrint('captureImage: Image saved to temp directory: ${imageFile.path}');
                return imageFile;
              }
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
  static Map<String, String> _getAuthHeaders({bool excludeContentType = false, bool isMultipart = false}) {
    final token = _getAuthTokenSync();
    
    if (token == null) {
      throw Exception('Authentication token is missing. Please log in again.');
    }
    
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
    };
    
    if (!excludeContentType && !isMultipart) {
      headers['Content-Type'] = 'application/json';
    }
    
    return headers;
  }

  // Helper method to get the authentication token
  static Future<String?> _getToken() async {
    // Return cached token if available
    if (_token != null) {
      return _token;
    }
    
    // Try to load token from preferences
    try {
      final prefs = await _ensureSharedPreferences();
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

  /**
   * Gets a preview image from the ESP32 camera.
   * 
   * This method tries different endpoints in order to get a valid image from the ESP32 camera.
   * It will attempt to connect to various common ESP32 camera endpoints until it finds one that works.
   * 
   * @return A Uint8List containing the image bytes if successful, null otherwise.
   */
  static Future<Uint8List?> getEsp32CameraPreview() async {
    if (_esp32Url == null || _esp32Url!.isEmpty) {
      debugPrint('getEsp32CameraPreview: ESP32 URL not configured');
      return null;
    }
    
    debugPrint('getEsp32CameraPreview: Attempting to get preview from: $_esp32Url');
    
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
    
    // Add ESP-CAM specific endpoints
    if (_esp32Url!.endsWith("/")) {
      endpointsToTry.add('${_esp32Url}cam-hi.jpg');
      endpointsToTry.add('${_esp32Url}cam-lo.jpg');
      endpointsToTry.add('${_esp32Url}cam.jpg');
      endpointsToTry.add('${_esp32Url}snapshot.jpg');
    } else {
      endpointsToTry.add('${_esp32Url}/cam-hi.jpg');
      endpointsToTry.add('${_esp32Url}/cam-lo.jpg');
      endpointsToTry.add('${_esp32Url}/cam.jpg');
      endpointsToTry.add('${_esp32Url}/snapshot.jpg');
    }
    
    debugPrint('getEsp32CameraPreview: Trying endpoints: $endpointsToTry');
    
    Exception? lastException;
    
    for (final url in endpointsToTry) {
      try {
        debugPrint('getEsp32CameraPreview: Fetching image from: $url');
        
        _logApiCall(
          method: 'GET',
          url: url,
        );
        
        final response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 3), onTimeout: () {
            debugPrint('getEsp32CameraPreview: Timeout on $url');
            throw TimeoutException('Preview timeout');
          });
        
        // Log response status and headers but not the binary image data
        _logApiCall(
          method: 'GET',
          url: url,
          statusCode: response.statusCode,
        );
        
        if (response.statusCode == 200 && response.bodyBytes.length > 100) {
          // Check Content-Type header (more reliable than guessing)
          final contentType = response.headers['content-type'] ?? '';
          final isImageContentType = contentType.toLowerCase().contains('image');
          
          // Validate the image data with custom validator
          final bool isValidImage = _isValidImage(response.bodyBytes);
          
          if (isValidImage || isImageContentType) {
            debugPrint('getEsp32CameraPreview: Successfully received image from $url, size: ${response.bodyBytes.length} bytes');
            return response.bodyBytes;
          } else {
            debugPrint('getEsp32CameraPreview: Received data does not appear to be a valid image from $url');
          }
        } else {
          debugPrint('getEsp32CameraPreview: Invalid response from $url: ${response.statusCode}, body size: ${response.bodyBytes.length}');
        }
      } catch (e) {
        _logApiCall(
          method: 'GET',
          url: url,
          error: e.toString(),
        );
        
        debugPrint('getEsp32CameraPreview: Error fetching from $url: $e');
        lastException = e as Exception;
        // Continue to next endpoint
      }
    }
    
    debugPrint('getEsp32CameraPreview: All endpoints failed. Last error: $lastException');
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

  // Update profile with voice sample
  static Future<Profile> updateProfileVoice(String id, File voiceFile) async {
    try {
      debugPrint('updateProfileVoice: Uploading voice sample for profile $id');
      
      // Create a multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/profiles/$id/update_voice/'),
      );
      
      // Add auth headers
      request.headers.addAll(_getAuthHeaders(excludeContentType: true));
      
      // Add the voice file
      request.files.add(await http.MultipartFile.fromPath(
        'voice_sample', 
        voiceFile.path,
        contentType: MediaType('audio', 'wav'),
      ));
      
      // Send the request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final profileJson = jsonDecode(responseBody);
        debugPrint('updateProfileVoice: Voice sample updated successfully');
        return Profile.fromJson(profileJson);
      } else {
        throw Exception('Failed to update voice sample: $responseBody');
      }
    } catch (e) {
      debugPrint('updateProfileVoice error: $e');
      throw Exception('Error updating voice sample: $e');
    }
  }
  
  // Register profile with face and optional voice
  static Future<Profile> registerProfileWithFaceAndVoice(
    String name, 
    String email, 
    String regNumber, 
    String university, 
    String bloodGroup, 
    File imageFile, 
    [File? voiceFile]
  ) async {
    try {
      debugPrint('registerProfileWithFaceAndVoice: Registering new profile');
      
      // Create a multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/profiles/register_with_face/'),
      );
      
      // Add auth headers
      request.headers.addAll(_getAuthHeaders(excludeContentType: true));
      
      // Add profile fields
      request.fields['name'] = name;
      request.fields['email'] = email;
      request.fields['reg_number'] = regNumber;
      request.fields['university'] = university;
      request.fields['blood_group'] = bloodGroup;
      
      // Add the image file as both 'image' and 'face_images'
      final imageBytes = await imageFile.readAsBytes();
      
      // Add as 'image' for backward compatibility
      request.files.add(http.MultipartFile.fromBytes(
        'image', 
        imageBytes,
        filename: imageFile.path.split('/').last,
        contentType: MediaType('image', 'jpeg'),
      ));
      
      // Also add as 'face_images' which is required by the server
      request.files.add(http.MultipartFile.fromBytes(
        'face_images', 
        imageBytes,
        filename: imageFile.path.split('/').last,
        contentType: MediaType('image', 'jpeg'),
      ));
      
      // Add the voice file if provided
      if (voiceFile != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'voice_sample', 
          voiceFile.path,
          contentType: MediaType('audio', 'wav'),
        ));
      }
      
      // Send the request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 201) {
        final profileJson = jsonDecode(responseBody);
        debugPrint('registerProfileWithFaceAndVoice: Profile registered successfully');
        return Profile.fromJson(profileJson);
      } else {
        throw Exception('Failed to register profile: $responseBody');
      }
    } catch (e) {
      debugPrint('registerProfileWithFaceAndVoice error: $e');
      throw Exception('Error registering profile: $e');
    }
  }

  // Mark attendance with voice only
  static Future<Map<String, dynamic>> markAttendanceWithVoice(File voiceFile) async {
    final url = '$_baseUrl/attendance/mark_attendance/';
    
    try {
      debugPrint('markAttendanceWithVoice: Marking attendance with voice');
      final token = await _getAuthToken();
      
      if (token == null) {
        debugPrint('markAttendanceWithVoice: Authentication token is null. Please log in again.');
        throw Exception('Authentication required. Please log in again.');
      }
      
      // Create a multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(url),
      );
      
      // Add auth headers
      request.headers['Authorization'] = 'Bearer $token';
      
      // Add verification method
      request.fields['verification_method'] = 'voice';
      
      // Log request information
      _logApiCall(
        method: 'POST (Multipart)',
        url: url,
        payload: {
          'verification_method': 'voice',
          'voice_file_path': voiceFile.path,
          'token': '${token.substring(0, 10)}...',
        },
      );
      
      // Add the voice file
      request.files.add(await http.MultipartFile.fromPath(
        'voice_sample', 
        voiceFile.path,
        contentType: MediaType('audio', 'wav'),
      ));
      
      // Send the request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      // Log response
      _logApiCall(
        method: 'POST (Multipart)',
        url: url,
        response: response,
        statusCode: response.statusCode,
      );
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        debugPrint('markAttendanceWithVoice: Success');
        
        // Process the response
        if (responseData.containsKey('results') && responseData['results'] is List && responseData['results'].isNotEmpty) {
          final firstResult = responseData['results'][0];
          
          final String profileName = firstResult['name'] ?? 'Unknown';
          final String regNumber = firstResult['reg_number'] ?? '';
          final String action = firstResult['action'] ?? 'time_in';
          final String time = firstResult['time'] ?? DateTime.now().toIso8601String();
          final String verificationMethod = firstResult['verification_method'] ?? 'voice';
          
          return {
            'success': true,
            'profile_name': profileName,
            'reg_number': regNumber,
            'action': action,
            'time': time,
            'verification_method': verificationMethod,
            'raw_response': responseData
          };
        } else {
          // Return a generic success response
          return {
            'success': true,
            'profile_name': 'Unknown',
            'timestamp': DateTime.now().toString(),
            'raw_response': responseData
          };
        }
      } else {
        _logApiCall(
          method: 'POST (Multipart)',
          url: url,
          error: 'Failed with status code: ${response.statusCode}',
        );
        throw Exception('Failed to mark attendance: ${response.body}');
      }
    } catch (e) {
      _logApiCall(
        method: 'POST (Multipart)',
        url: url,
        error: e.toString(),
      );
      
      debugPrint('markAttendanceWithVoice error: $e');
      throw Exception('Error marking attendance with voice: $e');
    }
  }
  
  // Mark attendance with both face and voice
  static Future<Map<String, dynamic>> markAttendanceWithFaceAndVoice(File imageFile, File voiceFile, String? esp32Url) async {
    try {
      debugPrint('markAttendanceWithFaceAndVoice: Marking attendance with face and voice');
      final token = await _getAuthToken();
      
      if (token == null) {
        debugPrint('markAttendanceWithFaceAndVoice: Authentication token is null. Please log in again.');
        throw Exception('Authentication required. Please log in again.');
      }
      
      // Create a multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_baseUrl/attendance/mark_attendance/'),
      );
      
      // Add auth headers
      request.headers['Authorization'] = 'Bearer $token';
      
      // Add verification method
      request.fields['verification_method'] = 'both';
      
      // Add the image file
      request.files.add(await http.MultipartFile.fromPath(
        'image', 
        imageFile.path,
        contentType: MediaType('image', 'jpeg'),
      ));
      
      // Add the voice file
      request.files.add(await http.MultipartFile.fromPath(
        'voice_sample', 
        voiceFile.path,
        contentType: MediaType('audio', 'wav'),
      ));
      
      // Send the request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> responseData = jsonDecode(responseBody);
        debugPrint('markAttendanceWithFaceAndVoice: Success');
        
        // Process the response
        if (responseData.containsKey('results') && responseData['results'] is List && responseData['results'].isNotEmpty) {
          final firstResult = responseData['results'][0];
          
          final String profileName = firstResult['name'] ?? 'Unknown';
          final String regNumber = firstResult['reg_number'] ?? '';
          final String email = firstResult['email'] ?? '';
          final String university = firstResult['university'] ?? '';
          final String bloodGroup = firstResult['blood_group'] ?? '';
          final String action = firstResult['action'] ?? 'time_in';
          final String time = firstResult['time'] ?? DateTime.now().toIso8601String();
          final double confidence = firstResult['confidence'] is num ? (firstResult['confidence'] as num).toDouble() : 0.0;
          final String profileImage = firstResult['image'] ?? '';
          final String verificationMethod = firstResult['verification_method'] ?? 'both';
          
          return {
            'success': true,
            'profile_name': profileName,
            'reg_number': regNumber,
            'email': email,
            'university': university,
            'blood_group': bloodGroup,
            'action': action,
            'time': time,
            'confidence': confidence,
            'profile_image': profileImage,
            'verification_method': verificationMethod,
            'raw_response': responseData
          };
        } else {
          // Return a generic success response
          return {
            'success': true,
            'profile_name': 'Unknown',
            'timestamp': DateTime.now().toString(),
            'raw_response': responseData
          };
        }
      } else {
        throw Exception('Failed to mark attendance: $responseBody');
      }
    } catch (e) {
      debugPrint('markAttendanceWithFaceAndVoice error: $e');
      throw Exception('Error marking attendance with face and voice: $e');
    }
  }

  // Add a single face image to a profile
  static Future<Profile> addFaceImage(String profileId, File imageFile) async {
    debugPrint('addFaceImage: Adding face image to profile: $profileId');
    try {
      // Validate image file
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist at path: ${imageFile.path}');
      }
      
      // Create multipart request
      var request = http.MultipartRequest(
        'POST', 
        Uri.parse('$_baseUrl/profiles/$profileId/add_face_images/')
      );
      
      // Add auth headers
      final headers = _getAuthHeaders(isMultipart: true);
      request.headers.addAll(headers);
      
      // Add face image
      debugPrint('addFaceImage: Adding image from file: ${imageFile.path}');
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
        debugPrint('addFaceImage: Error reading image file: $e');
        throw Exception('Error reading image file: $e');
      }
      
      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      debugPrint('addFaceImage: Response status: ${response.statusCode}');
      debugPrint('addFaceImage: Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        // Get the updated profile after adding image
        return await getProfileById(profileId);
      } else if (response.statusCode == 400 && response.body.toLowerCase().contains('no face')) {
        // Face detection error from backend
        debugPrint('addFaceImage: Backend reported no face or face detection error');
        throw Exception('The server could not detect faces in the provided image. Please try with a clearer image that shows a face clearly.');
      } else {
        throw Exception('Failed to add face image: ${response.body}');
      }
    } catch (e) {
      debugPrint('addFaceImage error: $e');
      throw Exception('Error adding face image: $e');
    }
  }

  // Helper method to log API requests and responses
  static void _logApiCall({
    required String method,
    required String url,
    Map<String, dynamic>? payload,
    dynamic response,
    int? statusCode,
    String? error,
  }) {
    debugPrint('\n=== API CALL DEBUG ===');
    debugPrint('🔷 METHOD: $method');
    debugPrint('🔷 URL: $url');
    
    if (payload != null) {
      try {
        final jsonPayload = jsonEncode(payload);
        debugPrint('🔷 PAYLOAD: $jsonPayload');
      } catch (e) {
        debugPrint('🔷 PAYLOAD: $payload (Could not encode to JSON: $e)');
      }
    }
    
    if (statusCode != null) {
      debugPrint('🔷 STATUS CODE: $statusCode');
    }
    
    if (response != null) {
      try {
        if (response is String) {
          debugPrint('🔷 RESPONSE: $response');
        } else if (response is http.Response) {
          debugPrint('🔷 RESPONSE CODE: ${response.statusCode}');
          debugPrint('🔷 RESPONSE HEADERS: ${response.headers}');
          debugPrint('🔷 RESPONSE BODY: ${response.body}');
        } else {
          final jsonResponse = jsonEncode(response);
          debugPrint('🔷 RESPONSE: $jsonResponse');
        }
      } catch (e) {
        debugPrint('🔷 RESPONSE: Could not format response: $e');
        debugPrint('🔷 RAW RESPONSE: $response');
      }
    }
    
    if (error != null) {
      debugPrint('🔶 ERROR: $error');
    }
    
    debugPrint('=== END API CALL DEBUG ===\n');
  }
}