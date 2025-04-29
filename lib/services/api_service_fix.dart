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
  static Future<Map<String, dynamic>> markAttendanceWithFaceRecognition(
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
        '$_baseUrl/attendance/mark_attendance/',  // This is the correct endpoint according to the latest info
        '$_baseUrl/attendance/mark_with_face/',
        '$_baseUrl/recognition/mark_attendance/',
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
          
          // Add required fields - add 'field' parameter that seems to be required
          if (esp32Url != null && esp32Url.isNotEmpty) {
            request.fields['esp32_url'] = esp32Url;
            request.fields['esp32_camera_url'] = esp32Url;
          }
          
          // Add basic required fields (these might be expected by the API)
          request.fields['timestamp'] = DateTime.now().toIso8601String();
          request.fields['request_id'] = DateTime.now().millisecondsSinceEpoch.toString();
          
          // Add the required 'profile' field
          request.fields['profile'] = 'auto_detect'; // This field is required by the API
          
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
          
          // If successful, parse the new response format
          if (response.statusCode == 200 || response.statusCode == 201) {
            debugPrint('FixedAttendance: Success with endpoint $endpoint');
            debugPrint('FixedAttendance: Full response body: ${response.body}');
            
            // Try to parse the response JSON to get profile information
            try {
              final Map<String, dynamic> responseData = jsonDecode(response.body);
              
              // Log all keys in the response for debugging
              debugPrint('FixedAttendance: Response keys: ${responseData.keys.toList()}');
              
              // The new API returns results as an array
              if (responseData.containsKey('results') && responseData['results'] is List) {
                // Check if the results array is empty
                if (responseData['results'].isEmpty) {
                  debugPrint('FixedAttendance: Warning - Results array is empty. This might be a backend issue.');
                  
                  // Return a special response indicating empty results
                  return {
                    'success': true,
                    'empty_results': true,
                    'profile_name': 'No Profile Found',
                    'message': 'The server processed the request but did not return any profile data.',
                    'raw_response': responseData
                  };
                }
                
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
                
                debugPrint('FixedAttendance: Attendance marked for $profileName ($regNumber) with $confidence% confidence');
                
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
                  'raw_response': responseData
                };
              } else {
                // Fallback to the old format if 'results' key is not present
                final String profileName = responseData['profile_name'] ?? 
                                          responseData['name'] ?? 
                                          responseData['profile']?['name'] ??
                                          responseData['user_name'] ??
                                          'Unknown';
                
                final String regNumber = responseData['reg_number'] ?? 
                                        responseData['profile']?['reg_number'] ?? 
                                        responseData['registration_number'] ??
                                        '';
                
                debugPrint('FixedAttendance: Attendance marked for $profileName ($regNumber) using old format');
                
                return {
                  'success': true,
                  'profile_name': profileName,
                  'reg_number': regNumber,
                  'timestamp': DateTime.now().toString(),
                  'raw_response': responseData
                };
              }
            } catch (parseError) {
              debugPrint('FixedAttendance: Could not parse profile info: $parseError');
              // Return success with limited info if we can't parse the response
              return {
                'success': true,
                'profile_name': 'Unknown',
                'timestamp': DateTime.now().toString()
              };
            }
          }
          
          // If not 405 (Method Not Allowed), check common error conditions
          if (response.statusCode != 405) {
            if (response.statusCode == 400) {
              // For 400 Bad Request, try to parse the error message to find the missing field
              try {
                final errorData = jsonDecode(response.body);
                debugPrint('FixedAttendance: 400 error details: $errorData');
                
                // If the error contains field validation errors
                if (errorData is Map) {
                  // Check for common field error messages
                  final missingFields = <String>[];
                  errorData.forEach((key, value) {
                    if (value is List && value.isNotEmpty) {
                      missingFields.add('$key (${value.first})');
                    } else if (value is String) {
                      missingFields.add('$key ($value)');
                    }
                  });
                  
                  if (missingFields.isNotEmpty) {
                    lastException = Exception('Missing required fields: ${missingFields.join(", ")}');
                    continue;
                  }
                }
                
                // If we couldn't determine specific fields
                if (response.body.toLowerCase().contains('no face')) {
                  throw Exception('No face detected in the image. Please try again with a clearer image.');
                } else {
                  lastException = Exception('Bad request: ${response.body}');
                  continue;
                }
              } catch (e) {
                lastException = Exception('Bad request: ${response.body}');
                continue;
              }
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