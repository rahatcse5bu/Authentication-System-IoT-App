// lib/services/api_service_fix.dart
// Replacement for markAttendanceWithFaceRecognition method to fix the 405 error

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../utils/constants.dart';

class ApiServiceFix {
  static String get _baseUrl => Constants.baseApiUrl;

  // Try different endpoints for face recognition attendance marking
  static Future<bool> markAttendanceWithFaceRecognition(
      File imageFile, String? esp32Url, String? token) async {
    try {
      debugPrint('FixedAttendance: Starting face recognition process');
      
      if (token == null) {
        throw Exception('Authentication token is missing');
      }
      
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist: ${imageFile.path}');
      }
      
      // List of endpoints to try, in order of preference
      final List<String> endpointsToTry = [
        '$_baseUrl/attendance/mark_attendance/',
        '$_baseUrl/recognition/mark_attendance/',
        '$_baseUrl/attendance/mark_with_face/',
        '$_baseUrl/attendance/mark/',
        '$_baseUrl/attendance/',
      ];
      
      Exception? lastException;
      
      // Try each endpoint until one works
      for (final endpoint in endpointsToTry) {
        try {
          final uri = Uri.parse(endpoint);
          debugPrint('FixedAttendance: Trying endpoint: $uri');
          
          final request = http.MultipartRequest('POST', uri);
          
          // Add headers - Using Bearer format for JWT tokens
          request.headers.addAll({
            'Authorization': 'Bearer $token',
          });
          
          // Add ESP32 camera URL if available (try both field names)
          if (esp32Url != null && esp32Url.isNotEmpty) {
            request.fields['esp32_url'] = esp32Url;
            request.fields['esp32_camera_url'] = esp32Url;
          }
          
          // Add image file (only with 'image' field name as specified in API docs)
          final bytes = await imageFile.readAsBytes();
          
          request.files.add(http.MultipartFile.fromBytes(
            'image',
            bytes,
            filename: 'face_image.jpg',
            contentType: MediaType('image', 'jpeg'),
          ));
          
          // Send request
          debugPrint('FixedAttendance: Sending request to $uri');
          final streamedResponse = await request.send();
          final response = await http.Response.fromStream(streamedResponse);
          
          debugPrint('FixedAttendance: Response status: ${response.statusCode}');
          debugPrint('FixedAttendance: Response body: ${response.body}');
          
          // If successful, return true
          if (response.statusCode == 200 || response.statusCode == 201) {
            debugPrint('FixedAttendance: Success with endpoint $endpoint');
            return true;
          }
          
          // If not 405 (Method Not Allowed), check common error conditions
          if (response.statusCode != 405) {
            if (response.statusCode == 400 && response.body.toLowerCase().contains('no face')) {
              throw Exception('No face detected in the image. Please try again with a clearer image.');
            } else if (response.statusCode == 404 && response.body.toLowerCase().contains('not recognized')) {
              throw Exception('Face not recognized. Please register your profile first.');
            } else if (response.statusCode == 401) {
              debugPrint('FixedAttendance: Authentication failed. Token: ${token.length > 10 ? token.substring(0, 10) + "..." : token}');
              lastException = Exception('Authentication failed: ${response.statusCode}, ${response.body}');
              continue;
            } else {
              // Store exception but continue trying other endpoints
              lastException = Exception('Failed with endpoint $endpoint: ${response.statusCode}, ${response.body}');
              continue;
            }
          }
          
          // If 405, try the next endpoint
          debugPrint('FixedAttendance: Method not allowed for endpoint $endpoint, trying next...');
        } catch (e) {
          debugPrint('FixedAttendance: Error with endpoint $endpoint: $e');
          lastException = e is Exception ? e : Exception(e.toString());
          // Continue to next endpoint
        }
      }
      
      // If we get here, all endpoints failed
      throw lastException ?? Exception('All attendance endpoints failed');
    } catch (e) {
      debugPrint('FixedAttendance error: $e');
      rethrow;
    }
  }
} 