// lib/screens/scan_screen.dart
// Updated with stable preview, automatic preview control based on scan state

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

import '../providers/attendance_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/face_detection_service.dart';

class ScanScreen extends StatefulWidget {
  @override
  _ScanScreenState createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with SingleTickerProviderStateMixin {
  ApiService _apiService = ApiService();
  Timer? _scanTimer;
  bool _isScanning = false;
  String _statusMessage = 'Ready to scan';
  int _scanCount = 0;
  DateTime? _lastScanTime;
  List<String> _recognizedProfiles = [];
  
  // Stream controller for MJPEG streaming
  StreamController<Uint8List>? _streamController;
  bool _isStreamActive = false;
  
  // Preview image variables
  Uint8List? _previewImageBytes;
  bool _isLoadingPreview = false;
  
  // For manual refresh of preview
  Timer? _refreshTimer;
  
  // Double buffering to reduce flicker
  Uint8List? _currentFrame;
  DateTime _lastFrameTime = DateTime.now();
  bool _processingFrame = false;
  
  // Animation controller for smooth transitions
  late AnimationController _fadeController;
  bool _previewEnabled = true;
  
  // Cached provider references
  SettingsProvider? _settingsProvider;
  String? _cachedEsp32Url;
  bool _isDisposing = false;
  
  bool _isFaceDetected = false;
  String _faceDetectionMessage = '';
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    
    // Initialize fade controller for smoother transitions
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeController.value = 1.0;
    
    // Start preview when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _previewEnabled) {
        _startCameraPreview();
      }
    });
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache provider reference for safer access during disposal
    _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _cachedEsp32Url = _settingsProvider?.esp32Url;
  }
  
  @override
  void dispose() {
    _isDisposing = true;
    _stopScanning();
    _stopCameraPreview();
    if (_refreshTimer != null) {
      _refreshTimer!.cancel();
      _refreshTimer = null;
    }
    _fadeController.dispose();
    super.dispose();
  }
  
  void _displayStatusMessage(String message) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
    });
  }
  
  void _togglePreview() {
    if (!mounted) return;
    setState(() {
      _previewEnabled = !_previewEnabled;
    });
    
    if (_previewEnabled) {
      _startCameraPreview();
    } else {
      _stopCameraPreview();
    }
  }
  
  Future<void> _startCameraPreview() async {
    if (!mounted || _isDisposing || !_previewEnabled) return;
    
    try {
      // Use cached ESP32 URL instead of accessing provider directly
      final String? esp32Url = _cachedEsp32Url ?? _settingsProvider?.esp32Url;
      if (esp32Url == null || esp32Url.isEmpty) {
        _displayStatusMessage('ESP32 camera URL not configured');
        return;
      }
      
      // Update cached URL
      _cachedEsp32Url = esp32Url;
      
      // Don't restart if already active
      if (_isStreamActive) return;
      
      // Fade out current preview
      _fadeController.reverse();
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (!mounted) return;
      
      // Create a new stream controller if needed
      if (_streamController != null) {
        _streamController!.close();
      }
      _streamController = StreamController<Uint8List>.broadcast();
      
      setState(() {
        _isStreamActive = true;
        _isLoadingPreview = true;
        _statusMessage = 'Connecting to camera...';
      });
      
      try {
        // Try direct image capture first for immediate feedback
        // Use base URL directly instead of /capture
        await _fetchSingleImage();
        
        // No need to try MJPEG streaming since it doesn't work
        _displayStatusMessage('Camera preview active');
        _fadeController.forward();
        
        // Start polling with base URL
        _startImagePolling();
      } catch (e) {
        debugPrint('Stream connection error: $e');
        
        // Try with a different approach - direct snapshot instead of stream
        if (mounted) {
          _displayStatusMessage('Trying alternative connection method...');
          _startImagePolling();
        }
      }
    } catch (e) {
      debugPrint('Error in _startCameraPreview: $e');
      if (mounted) {
        _displayStatusMessage('Camera error: ${e.toString().split('\n')[0]}');
      }
    }
  }
  
  // Update frame with throttling to prevent flickering
  void _updateFrameBuffer(Uint8List newFrame) {
    if (!mounted || !_isStreamActive || _processingFrame || _streamController == null || _streamController!.isClosed) return;
    
    try {
      final now = DateTime.now();
      final elapsed = now.difference(_lastFrameTime);
      
      // Throttle updates to reduce flickering (max 10 frames per second)
      if (elapsed.inMilliseconds < 100) { // ~10 FPS
        _currentFrame = newFrame;
        return;
      }
      
      _processingFrame = true;
      _lastFrameTime = now;
      _currentFrame = newFrame;
      
      // Save also as preview image for fallback
      _previewImageBytes = newFrame;
      
      // Push frame to stream if it exists and isn't closed
      if (_streamController != null && !_streamController!.isClosed) {
        _streamController!.add(newFrame);
      }
    } catch (e) {
      debugPrint('Error updating frame buffer: $e');
    } finally {
      _processingFrame = false;
    }
  }
  
  void _startImagePolling() {
    if (!mounted || !_previewEnabled) return;
    
    debugPrint('Starting image polling');
    // Clear any existing timer
    if (_refreshTimer != null) {
      _refreshTimer!.cancel();
    }
    
    // Try to get first image immediately
    _fetchSingleImage();
    
    // Create a new timer to periodically fetch images
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 750), (_) {
      if (mounted && _previewEnabled) {
        _fetchSingleImage();
      } else if (_refreshTimer != null) {
        _refreshTimer!.cancel();
        _refreshTimer = null;
      }
    });
  }
  
  // Helper method to check if data is a valid JPEG image
  bool _isValidJpegImage(Uint8List bytes) {
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
        debugPrint('Detected HTML content instead of image');
        return false;
      }
    }
    
    // If we can't definitively say it's bad, let's try it as an image
    return bytes.length > 1000; // At least some reasonable size for an image
  }

  Future<void> _fetchSingleImage() async {
    if (!mounted || _isDisposing || !_previewEnabled) return;
    
    try {
      // Use cached ESP32 URL to prevent context access during disposal
      final String? esp32Url = _cachedEsp32Url ?? _settingsProvider?.esp32Url;
      if (esp32Url == null || esp32Url.isEmpty) return;
      
      // Try different endpoints - prioritize /capture endpoint first based on reliability
      List<String> endpointsToTry = [];
      
      // Try /capture endpoint first
      if (!esp32Url.toLowerCase().contains("capture")) {
        if (esp32Url.endsWith("/")) {
          endpointsToTry.add('${esp32Url}capture');
        } else {
          endpointsToTry.add('${esp32Url}/capture');
        }
      }
      
      // Then try base URL
      endpointsToTry.add(esp32Url);
      
      // Then try /jpg endpoint 
      if (!esp32Url.toLowerCase().contains("jpg")) {
        if (esp32Url.endsWith("/")) {
          endpointsToTry.add('${esp32Url}jpg');
        } else {
          endpointsToTry.add('${esp32Url}/jpg');
        }
      }
      
      // Also try /camera/snapshot endpoint (some ESP32 cams use this)
      if (esp32Url.endsWith("/")) {
        endpointsToTry.add('${esp32Url}camera/snapshot');
      } else {
        endpointsToTry.add('${esp32Url}/camera/snapshot');
      }
      
      Exception? lastException;
      
      for (final url in endpointsToTry) {
        try {
          if (!mounted || _isDisposing) return;
          
          debugPrint('Scan screen: Fetching image from: $url');
          
          // Request a single image from the camera with increased timeout
          final response = await http.get(
            Uri.parse(url),
          ).timeout(
            const Duration(seconds: 5), 
            onTimeout: () {
              debugPrint('Scan screen: Image fetch timeout from $url');
              throw TimeoutException('Image fetch timeout');
            },
          );
          
          if (response.statusCode == 200 && response.bodyBytes.length > 100) {
            if (!mounted || _isDisposing || !_previewEnabled) return;
            
            final imageBytes = response.bodyBytes;
            debugPrint('Scan screen: Received image, size: ${imageBytes.length} bytes');
            
            // Check Content-Type header (more reliable than guessing)
            final contentType = response.headers['content-type'] ?? '';
            final isImageContentType = contentType.toLowerCase().contains('image');
            
            // Validate the image data with our custom validator
            final bool isValidImage = _isValidJpegImage(imageBytes);
                
            if (isValidImage) {
              debugPrint('Scan screen: Valid image detected from $url');
              
              try {
                // Update state with image data directly
                setState(() {
                  _previewImageBytes = imageBytes;
                  _isLoadingPreview = false;
                  
                  // Recreate stream controller if needed
                  if (_streamController == null || _streamController!.isClosed) {
                    _streamController = StreamController<Uint8List>.broadcast();
                    _isStreamActive = true;
                  }
                });
                
                // Success, stop trying more endpoints
                return;
              } catch (e) {
                debugPrint('Scan screen: Error processing image: $e');
                // If we get an error processing this image, try the next endpoint
                continue;
              }
            } else {
              debugPrint('Scan screen: Invalid image format from $url, skipping');
              continue; // Try next endpoint
            }
          } else {
            debugPrint('Scan screen: Invalid response from $url: ${response.statusCode}, size: ${response.bodyBytes.length}');
          }
        } catch (e) {
          debugPrint('Scan screen: Error fetching from $url: $e');
          lastException = e as Exception;
          // Try next endpoint
          continue;
        }
      }
      
      // If we get here, all endpoints failed
      throw lastException ?? Exception('All endpoints failed');
    } catch (e) {
      // Silently fail during polling
      debugPrint('Image polling error: $e');
    }
  }
  
  void _stopCameraPreview() {
    try {
      if (_streamController != null) {
        _streamController!.close();
        _streamController = null;
      }
      
      if (_refreshTimer != null) {
        _refreshTimer!.cancel();
        _refreshTimer = null;
      }
      
      if (mounted) {
        setState(() {
          _isStreamActive = false;
          _isLoadingPreview = false;
        });
      }
    } catch (e) {
      debugPrint('Error stopping camera preview: $e');
    }
  }
  
  void _restartCameraPreview() {
    _stopCameraPreview();
    Future.delayed(Duration(milliseconds: 500), () {
      if (mounted) _startCameraPreview();
    });
  }
  
  void _startScanning() {
    if (_isScanning) return;
    
    // Make sure preview is active
    if (!_isStreamActive && _previewEnabled) {
      _startCameraPreview();
      
      // Give the camera a moment to initialize
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _startScanningProcess();
      });
    } else {
      _startScanningProcess();
    }
  }
  
  void _startScanningProcess() {
    if (!mounted) return;
    
    setState(() {
      _previewEnabled = true;
      _isScanning = true;
      _statusMessage = 'Scanning...';
      _recognizedProfiles = [];
      _scanCount = 0;
      _lastScanTime = DateTime.now();
    });
    
    Provider.of<AttendanceProvider>(context, listen: false).startScanning();
    
    // Scan every 3 seconds
    _scanTimer = Timer.periodic(const Duration(seconds: 3), (_) => _captureScan());
  }
  
  void _stopScanning() {
    if (_scanTimer != null) {
      _scanTimer!.cancel();
      _scanTimer = null;
    }
    
    if (mounted) {
      setState(() {
        _isScanning = false;
        _statusMessage = 'Scan stopped';
      });
      
      Provider.of<AttendanceProvider>(context, listen: false).stopScanning();
      
      // Auto-stop preview if requested
      if (!_previewEnabled) {
        _stopCameraPreview();
      }
    }
  }
  
  Future<void> _captureScan() async {
    if (!mounted || _isDisposing) return;
    
    setState(() {
      _isFaceDetected = false;
      _faceDetectionMessage = 'Capturing image...';
    });
    
    try {
      debugPrint('_captureScan: Starting scan with ESP32 URL: $_cachedEsp32Url');
      debugPrint('_captureScan: Scan #${_scanCount + 1} at ${DateTime.now()}');
      
      // Check if ESP32 URL is configured
      if (_cachedEsp32Url == null || _cachedEsp32Url!.isEmpty) {
        setState(() {
          _faceDetectionMessage = 'ESP32 URL not configured';
        });
        return;
      }
      
      // Try using FaceDetectionService first for more reliable capture
      final imageBytes = await FaceDetectionService.captureEsp32Frame(_cachedEsp32Url!);
      File? imageFile;
      
      if (imageBytes != null) {
        // Save to a file
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final imagePath = '${tempDir.path}/esp32_scan_$timestamp.jpg';
        imageFile = File(imagePath);
        await imageFile.writeAsBytes(imageBytes);
        debugPrint('_captureScan: Image captured using FaceDetectionService: ${imageFile.path}');
      } else {
        // Fallback to ApiService if FaceDetectionService failed
        imageFile = await ApiService.captureImage();
        debugPrint('_captureScan: Image captured using ApiService: ${imageFile.path}');
      }
      
      // Skip face detection and proceed directly to recognition
      setState(() {
        _faceDetectionMessage = 'Recognizing face...';
      });
      
      // Mark attendance with the captured image
      debugPrint('_captureScan: Calling ApiService.markAttendanceWithFaceRecognition');
      final result = await ApiService.markAttendanceWithFaceRecognition(imageFile, _cachedEsp32Url);
      
      // Check if we got a successful response but with empty results
      if (result.containsKey('empty_results') && result['empty_results'] == true) {
        // Stop the scanning process after attendance
        _stopScanning();
        
        setState(() {
          _scanCount++;
          _lastScanTime = DateTime.now();
          _faceDetectionMessage = 'Attendance processed but no profile data returned';
          _statusMessage = 'Attendance processed';
        });
        
        // No popup for empty results case
        return;
      }
      
      // Extract profile information
      final String profileName = result['profile_name'] ?? 'Unknown';
      final String regNumber = result['reg_number'] ?? '';
      final String displayName = regNumber.isNotEmpty ? '$profileName ($regNumber)' : profileName;
      
      // Get additional information from the new API response
      final String action = result['action'] ?? 'time_in';
      final String actionDisplay = action == 'time_in' ? 'Time In' : (action == 'time_out' ? 'Time Out' : action);
      final double confidence = result['confidence'] is double ? result['confidence'] as double : 0.0;
      final String timeStr = result['time'] ?? DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final String email = result['email'] ?? '';
      final String university = result['university'] ?? '';
      final String bloodGroup = result['blood_group'] ?? '';
      final String profileImage = result['profile_image'] ?? '';
      
      // Stop the scanning process after successful attendance
      _stopScanning();
      
      setState(() {
        _scanCount++;
        _lastScanTime = DateTime.now();
        _isFaceDetected = true;
        _faceDetectionMessage = 'Attendance marked for $displayName!';
        _statusMessage = 'Attendance marked successfully';
      });
      
      if (mounted) {
        // Show center dialog instead of bottom SnackBar
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => AlertDialog(
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 24),
                const SizedBox(width: 8),
                const Text('Success', style: TextStyle(color: Colors.green)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Profile image if available
                  if (profileImage.isNotEmpty)
                    Container(
                      width: 100,
                      height: 100,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(
                          image: NetworkImage(profileImage),
                          fit: BoxFit.cover,
                        ),
                        border: Border.all(color: Colors.grey.shade300, width: 3),
                      ),
                    )
                  else
                    Container(
                      width: 100,
                      height: 100,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade200,
                        border: Border.all(color: Colors.grey.shade300, width: 3),
                      ),
                      child: const Icon(Icons.person, size: 60, color: Colors.grey),
                    ),
                  
                  // Profile name
                  Text(
                    profileName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                  
                  // Action type with nice badge
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: action == 'time_in' ? Colors.blue.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: action == 'time_in' ? Colors.blue.shade200 : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          action == 'time_in' ? Icons.login : Icons.logout,
                          color: action == 'time_in' ? Colors.blue : Colors.orange,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          actionDisplay,
                          style: TextStyle(
                            color: action == 'time_in' ? Colors.blue : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Profile details table
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Registration number
                        if (regNumber.isNotEmpty)
                          _buildDetailRow('ID', regNumber),
                          
                        // Email
                        if (email.isNotEmpty)
                          _buildDetailRow('Email', email),
                          
                        // University
                        if (university.isNotEmpty)
                          _buildDetailRow('University', university),
                          
                        // Blood group
                        if (bloodGroup.isNotEmpty)
                          _buildDetailRow('Blood Group', bloodGroup),
                          
                        // Time
                        _buildDetailRow('Time', timeStr),
                        
                        // Confidence score with color indicator
                        if (confidence > 0)
                          _buildDetailRow(
                            'Match',
                            '${confidence.toStringAsFixed(1)}%',
                            valueColor: confidence > 90 ? Colors.green : (confidence > 75 ? Colors.orange : Colors.red),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('_captureScan error: $e');
      
      // Stop the scanning process after an error
      _stopScanning();
      
      setState(() {
        _isFaceDetected = false;
        _faceDetectionMessage = 'Error: ${e.toString()}';
        _statusMessage = 'Error marking attendance';
      });
      
      // No popup for errors
    }
  }
  
  Future<void> _singleCapture() async {
    if (!mounted || _isDisposing) return;
    
    setState(() {
      _isProcessing = true;
      _isFaceDetected = false;
      _faceDetectionMessage = 'Capturing image...';
    });
    
    try {
      debugPrint('_singleCapture: Starting capture');
      
      // Check if ESP32 URL is configured
      if (_cachedEsp32Url == null || _cachedEsp32Url!.isEmpty) {
        setState(() {
          _isProcessing = false;
          _faceDetectionMessage = 'ESP32 URL not configured';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ESP32 camera URL not configured')),
        );
        return;
      }
      
      // Try using FaceDetectionService first for more reliable capture
      final imageBytes = await FaceDetectionService.captureEsp32Frame(_cachedEsp32Url!);
      File? imageFile;
      
      if (imageBytes != null) {
        // Save to a file
        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final imagePath = '${tempDir.path}/esp32_scan_$timestamp.jpg';
        imageFile = File(imagePath);
        await imageFile.writeAsBytes(imageBytes);
        debugPrint('_singleCapture: Image captured using FaceDetectionService: ${imageFile.path}');
      } else {
        // Fallback to ApiService if FaceDetectionService failed
        imageFile = await ApiService.captureImage();
        debugPrint('_singleCapture: Image captured using ApiService: ${imageFile.path}');
      }
      
      // Skip face detection and proceed directly to recognition
      // Mark attendance with the captured image
      debugPrint('_singleCapture: Calling ApiService.markAttendanceWithFaceRecognition');
      
      setState(() {
        _faceDetectionMessage = 'Recognizing face...';
      });
      
      final result = await ApiService.markAttendanceWithFaceRecognition(imageFile, _cachedEsp32Url);
      
      // Check if we got a successful response but with empty results
      if (result.containsKey('empty_results') && result['empty_results'] == true) {
        setState(() {
          _scanCount++;
          _lastScanTime = DateTime.now();
          _faceDetectionMessage = 'Attendance processed but no profile data returned';
          _statusMessage = 'Attendance processed';
        });
        
        // No popup for empty results
        return;
      }
      
      // Extract profile information
      final String profileName = result['profile_name'] ?? 'Unknown';
      final String regNumber = result['reg_number'] ?? '';
      final String displayName = regNumber.isNotEmpty ? '$profileName ($regNumber)' : profileName;
      
      // Get additional information from the new API response
      final String action = result['action'] ?? 'time_in';
      final String actionDisplay = action == 'time_in' ? 'Time In' : (action == 'time_out' ? 'Time Out' : action);
      final double confidence = result['confidence'] is double ? result['confidence'] as double : 0.0;
      final String timeStr = result['time'] ?? DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      final String email = result['email'] ?? '';
      final String university = result['university'] ?? '';
      final String bloodGroup = result['blood_group'] ?? '';
      final String profileImage = result['profile_image'] ?? '';
      
      setState(() {
        _scanCount++;
        _lastScanTime = DateTime.now();
        _isFaceDetected = true;
        _faceDetectionMessage = 'Attendance marked for $displayName!';
        _statusMessage = 'Attendance marked successfully';
      });
      
      if (mounted) {
        // Show center dialog instead of bottom SnackBar
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (context) => AlertDialog(
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 24),
                const SizedBox(width: 8),
                const Text('Success', style: TextStyle(color: Colors.green)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Profile image if available
                  if (profileImage.isNotEmpty)
                    Container(
                      width: 100,
                      height: 100,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        image: DecorationImage(
                          image: NetworkImage(profileImage),
                          fit: BoxFit.cover,
                        ),
                        border: Border.all(color: Colors.grey.shade300, width: 3),
                      ),
                    )
                  else
                    Container(
                      width: 100,
                      height: 100,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade200,
                        border: Border.all(color: Colors.grey.shade300, width: 3),
                      ),
                      child: const Icon(Icons.person, size: 60, color: Colors.grey),
                    ),
                  
                  // Profile name
                  Text(
                    profileName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                  
                  // Action type with nice badge
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: action == 'time_in' ? Colors.blue.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: action == 'time_in' ? Colors.blue.shade200 : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          action == 'time_in' ? Icons.login : Icons.logout,
                          color: action == 'time_in' ? Colors.blue : Colors.orange,
                          size: 18,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          actionDisplay,
                          style: TextStyle(
                            color: action == 'time_in' ? Colors.blue : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Profile details table
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Registration number
                        if (regNumber.isNotEmpty)
                          _buildDetailRow('ID', regNumber),
                          
                        // Email
                        if (email.isNotEmpty)
                          _buildDetailRow('Email', email),
                          
                        // University
                        if (university.isNotEmpty)
                          _buildDetailRow('University', university),
                          
                        // Blood group
                        if (bloodGroup.isNotEmpty)
                          _buildDetailRow('Blood Group', bloodGroup),
                          
                        // Time
                        _buildDetailRow('Time', timeStr),
                        
                        // Confidence score with color indicator
                        if (confidence > 0)
                          _buildDetailRow(
                            'Match',
                            '${confidence.toStringAsFixed(1)}%',
                            valueColor: confidence > 90 ? Colors.green : (confidence > 75 ? Colors.orange : Colors.red),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('_singleCapture error: $e');
      setState(() {
        _isFaceDetected = false;
        _faceDetectionMessage = 'Error: ${e.toString()}';
        _statusMessage = 'Error marking attendance';
      });
      
      // No popup for errors
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Scan'),
        actions: [
          IconButton(
            icon: Icon(_previewEnabled ? Icons.videocam : Icons.videocam_off),
            onPressed: _isScanning ? null : _togglePreview,
            tooltip: _previewEnabled ? 'Disable Preview' : 'Enable Preview',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isScanning ? null : () {
              setState(() {
                _statusMessage = 'Ready to scan';
                _recognizedProfiles = [];
                _scanCount = 0;
                _lastScanTime = null;
              });
              // Restart camera preview
              _restartCameraPreview();
            },
            tooltip: 'Reset',
          ),
        ],
      ),
      body: Consumer2<ProfileProvider, SettingsProvider>(
        builder: (context, profileProvider, settingsProvider, child) {
          // Update cached ESP32 URL
          _cachedEsp32Url = settingsProvider.esp32Url;
          
          // Check if ESP32 URL is configured
          if (settingsProvider.esp32Url == null || settingsProvider.esp32Url!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text(
                    'ESP32 Camera not configured',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/settings');
                    },
                    child: const Text('Go to Settings'),
                  ),
                ],
              ),
            );
          }

          if (profileProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (profileProvider.profiles.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_add_disabled, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'No profiles found',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/profiles');
                    },
                    child: const Text('Create Profile'),
                  ),
                ],
              ),
            );
          }
          
          return Stack(
            children: [
              Column(
                children: [
                  // Status bar
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.grey[200],
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isScanning ? Icons.sync : (_isStreamActive ? Icons.videocam : Icons.info_outline),
                              color: _isScanning ? Colors.green : (_isStreamActive ? Colors.blue : Colors.orange),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _statusMessage,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                            Text('Scans: $_scanCount'),
                          ],
                        ),
                        if (_recognizedProfiles.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.people, size: 20, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Recognized: ${_recognizedProfiles.join(", ")}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  // Preview container
                  Expanded(
                    child: Stack(
                      children: [
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: FadeTransition(
                            opacity: _fadeController,
                            child: _isLoadingPreview
                                ? const Center(child: CircularProgressIndicator())
                                : _buildCameraPreview(),
                          ),
                        ),
                        if (_previewEnabled)
                          Positioned(
                            right: 24,
                            bottom: 24,
                            child: FloatingActionButton(
                              mini: true,
                              onPressed: _isLoadingPreview ? null : _restartCameraPreview,
                              tooltip: 'Restart preview',
                              child: const Icon(Icons.refresh),
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // Control buttons
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isScanning ? null : _singleCapture,
                            icon: const Icon(Icons.camera),
                            label: const Text('Single Capture'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isScanning ? _stopScanning : _startScanning,
                            icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
                            label: Text(_isScanning ? 'Stop Scanning' : 'Start Scanning'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isScanning ? Colors.red : Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              // Face detection status
              if (_isFaceDetected || _isProcessing)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isProcessing)
                          const CircularProgressIndicator(),
                        const SizedBox(height: 8),
                        Text(
                          _faceDetectionMessage,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // New method to build camera preview with more robust rendering
  Widget _buildCameraPreview() {
    if (_isLoadingPreview) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // Use a simple direct image display approach
    if (_previewImageBytes != null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Image.memory(
            _previewImageBytes!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            // Force rebuild on each render
            key: ValueKey('img-${DateTime.now().millisecondsSinceEpoch}'),
            // Add error handler
            errorBuilder: (context, error, stackTrace) {
              debugPrint('Scan screen: Error rendering image: $error');
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.broken_image, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    const Text('Invalid image data', style: TextStyle(color: Colors.white)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _restartCameraPreview,
                      child: const Text('Retry Connection'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }
    
    return const Center(
      child: Text('Connecting to camera...', 
        style: TextStyle(color: Colors.grey),
      ),
    );
  }

  // Helper method to build detail rows
  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text(
            label + ':',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.black87,
                fontWeight: valueColor != null ? FontWeight.bold : FontWeight.normal,
                fontSize: 14,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

// Add this extension to support Math.min function
extension Math on num {
  static int min(int a, int b) => a < b ? a : b;
}