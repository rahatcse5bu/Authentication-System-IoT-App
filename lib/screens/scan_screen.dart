// lib/screens/scan_screen.dart
// Updated with stable preview, automatic preview control based on scan state

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:ui';
import 'package:http/http.dart' as http;

import '../providers/attendance_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';

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
    
    // Use cached settings
    final String? esp32Url = _cachedEsp32Url ?? _settingsProvider?.esp32Url;
    
    if (esp32Url == null || esp32Url.isEmpty) {
      debugPrint('_captureScan: ESP32 URL not configured');
      setState(() {
        _statusMessage = 'ESP32 camera URL not configured';
      });
      _stopScanning();
      return;
    }
    
    debugPrint('_captureScan: Starting scan with ESP32 URL: ${esp32Url}');
    
    try {
      setState(() {
        _statusMessage = 'Scanning...';
      });
      
      // Update scan stats
      _scanCount++;
      _lastScanTime = DateTime.now();
      debugPrint('_captureScan: Scan #$_scanCount at ${_lastScanTime.toString()}');
      
      // Call the API to mark attendance with face recognition
      // The live preview is already running so we don't need to capture a new image
      debugPrint('_captureScan: Calling ApiService.markAttendanceWithFaceRecognition');
      final result = await ApiService.markAttendanceWithFaceRecognition();
      
      if (!mounted) return;
      
      debugPrint('_captureScan: Received result: $result');
      
      if (result.containsKey('results') && result['results'] is List && (result['results'] as List).isNotEmpty) {
        // Add recognized profiles to the list
        debugPrint('_captureScan: ${result['results'].length} profiles recognized');
        for (var profile in result['results']) {
          // Check if profile is already in the list
          final existingIndex = _recognizedProfiles.indexWhere(
            (p) => p == profile['name']
          );
          
          if (existingIndex >= 0) {
            // Update existing profile
            debugPrint('_captureScan: Updating existing profile: ${profile['name']}');
            _recognizedProfiles[existingIndex] = profile['name'];
          } else {
            // Add new profile
            debugPrint('_captureScan: Adding new profile: ${profile['name']}');
            _recognizedProfiles.add(profile['name']);
          }
        }
        
        setState(() {
          _statusMessage = '${_recognizedProfiles.length} profile(s) recognized';
        });
      } else {
        debugPrint('_captureScan: No profiles recognized in the result');
        setState(() {
          _statusMessage = 'No profiles recognized';
        });
      }
    } catch (e) {
      if (!mounted) return;
      
      debugPrint('_captureScan error: $e');
      
      String errorMsg = 'Error scanning';
      
      // Check for specific error messages
      String errorString = e.toString().toLowerCase();
      if (errorString.contains('no active profiles found')) {
        errorMsg = 'No active profiles - create a profile first';
      } else if (errorString.contains('face')) {
        errorMsg = 'No face detected in image';
      } else if (errorString.contains('network') || errorString.contains('connect')) {
        errorMsg = 'Network error: Check ESP32 connection';
      }
      
      setState(() {
        _statusMessage = errorMsg;
      });
    }
  }
  
  Future<void> _singleCapture() async {
    if (!mounted) return;
    
    // Ensure preview is active for best results
    if (!_isStreamActive) {
      _displayStatusMessage('Starting preview...');
      await _startCameraPreview();
      // Wait for preview to connect
      await Future.delayed(Duration(milliseconds: 1000));
    }
    
    if (!mounted) return;
    
    setState(() {
      _statusMessage = 'Processing...';
    });

    try {
      // Using mark_attendance endpoint instead of recognize_face which seems to be missing
      final response = await ApiService.markAttendanceWithFaceRecognition();
      
      if (!mounted) return;
      
      setState(() {
        _scanCount++;
        _lastScanTime = DateTime.now();
      });

      if (response.containsKey('results') && response['results'] is List && (response['results'] as List).isNotEmpty) {
        // Get first recognized person
        final profile = response['results'][0];
        final String name = profile['name'] ?? 'Unknown';
        
        setState(() {
          _statusMessage = 'Recognized: $name';
          if (!_recognizedProfiles.contains(name)) {
            _recognizedProfiles.add(name);
          }
        });
      } else {
        setState(() {
          _statusMessage = 'Not recognized';
        });
      }
    } catch (e) {
      if (!mounted) return;
      
      setState(() {
        _statusMessage = 'Error: ${e.toString().split('\n')[0]}';
      });
      debugPrint('Single capture error: $e');
    }
    
    // If preview is not enabled by default, turn it off after capture
    if (!_previewEnabled && !_isScanning) {
      Future.delayed(Duration(seconds: 2), () {
        if (mounted && !_isScanning) {
          _stopCameraPreview();
        }
      });
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
          
          return Column(
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
}

// Add this extension to support Math.min function
extension Math on num {
  static int min(int a, int b) => a < b ? a : b;
}