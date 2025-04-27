// lib/screens/scan_screen.dart
// Updated to use the correct ESP32 URL for MJPEG streaming

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

class _ScanScreenState extends State<ScanScreen> {
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

  @override
  void initState() {
    super.initState();
    
    // Start preview when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCameraPreview();
    });
  }
  
  @override
  void dispose() {
    _stopScanning();
    _stopCameraPreview();
    _refreshTimer?.cancel();
    super.dispose();
  }
  
  void _displayStatusMessage(String message) {
    setState(() {
      _statusMessage = message;
    });
  }
  
  Future<void> _startCameraPreview() async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (settings.esp32Url == null || settings.esp32Url!.isEmpty) {
      _displayStatusMessage('ESP32 camera URL not configured');
      return;
    }
    
    // Create a new stream controller if needed
    _streamController?.close();
    _streamController = StreamController<Uint8List>();
    
    setState(() {
      _isStreamActive = true;
      _isLoadingPreview = true;
      _statusMessage = 'Connecting to camera...';
    });
    
    try {
      // Connect directly to the ESP32 root URL
      final Uri uri = Uri.parse(settings.esp32Url!);
      
      debugPrint('Connecting to camera at: $uri');
      
      // Make HTTP request to MJPEG stream
      final client = http.Client();
      final request = http.Request('GET', uri);
      final response = await client.send(request).timeout(const Duration(seconds: 10));
      
      if (response.statusCode != 200) {
        throw Exception('Failed to connect to stream: ${response.statusCode}');
      }
      
      // Check content type to confirm it's a stream
      final contentType = response.headers['content-type'] ?? '';
      debugPrint('Content type: $contentType');
      
      if (!contentType.toLowerCase().contains('multipart/x-mixed-replace')) {
        // If we don't have the right content type, try fetching individual images instead
        _displayStatusMessage('Stream not available, using polling');
        _stopCameraPreview();
        _startImagePolling();
        return;
      }

      _displayStatusMessage('Live preview active');
      setState(() {
        _isLoadingPreview = false;
      });
      
      // Process the multipart stream
      final stream = response.stream;
      
      // MJPEG boundary pattern - this can vary between cameras
      final RegExp boundaryRegExp = RegExp(r'--[a-zA-Z0-9\.]+'); 
      final RegExp contentLengthRegExp = RegExp(r'Content-Length: (\d+)');
      
      List<int> buffer = [];
      int expectedLength = -1;
      bool findingHeader = true;
      
      // Listen to the stream
      stream.listen(
        (List<int> chunk) {
          buffer.addAll(chunk);
          
          while (buffer.isNotEmpty) {
            if (findingHeader) {
              // Convert part of buffer to string to find headers
              final int searchLength = buffer.length > 1024 ? 1024 : buffer.length;
              final String headerString = String.fromCharCodes(buffer.sublist(0, searchLength));
              
              // Find boundary
              final boundaryMatch = boundaryRegExp.firstMatch(headerString);
              if (boundaryMatch == null) {
                if (buffer.length > 4096) {
                  // If buffer is too large and no boundary found, clear it
                  buffer = [];
                }
                break; // Need more data
              }
              
              // Find content length
              final contentLengthMatch = contentLengthRegExp.firstMatch(headerString);
              if (contentLengthMatch != null) {
                expectedLength = int.tryParse(contentLengthMatch.group(1) ?? '0') ?? 0;
                debugPrint('Found image with length: $expectedLength');
              } else {
                expectedLength = -1;
              }
              
              // Find end of header
              final int headerEnd = headerString.indexOf('\r\n\r\n');
              if (headerEnd > 0) {
                // Remove header from buffer
                buffer = buffer.sublist(headerEnd + 4);
                findingHeader = false;
              } else {
                break; // Need more data
              }
            } else {
              // We're processing image data
              if (expectedLength > 0) {
                // If we know content length
                if (buffer.length >= expectedLength) {
                  // We have a complete frame
                  final imageData = buffer.sublist(0, expectedLength);
                  
                  // Add frame to stream
                  if (!_streamController!.isClosed) {
                    _streamController!.add(Uint8List.fromList(imageData));
                  }
                  
                  // Remove frame from buffer
                  buffer = buffer.sublist(expectedLength);
                  findingHeader = true;
                } else {
                  break; // Need more data
                }
              } else {
                // If we don't know content length, look for next boundary
                final String dataString = String.fromCharCodes(buffer.take(Math.min(buffer.length, 200)).toList());
                final boundaryMatch = boundaryRegExp.firstMatch(dataString);
                
                if (boundaryMatch != null) {
                  // We found the next boundary, so extract the image data
                  final imageData = buffer.sublist(0, boundaryMatch.start);
                  
                  // Add frame to stream if it's a reasonable size
                  if (imageData.length > 100 && !_streamController!.isClosed) {
                    _streamController!.add(Uint8List.fromList(imageData));
                  }
                  
                  // Remove frame and boundary from buffer
                  buffer = buffer.sublist(boundaryMatch.start);
                  findingHeader = true;
                } else if (buffer.length > 1024 * 1024) {
                  // Buffer too big, something went wrong
                  buffer = [];
                  findingHeader = true;
                } else {
                  break; // Need more data
                }
              }
            }
          }
        },
        onError: (error) {
          debugPrint('Stream error: $error');
          _displayStatusMessage('Stream error: ${error.toString().split('\n')[0]}');
          _restartCameraPreview();
        },
        onDone: () {
          debugPrint('Stream ended');
          _displayStatusMessage('Stream ended');
          _restartCameraPreview();
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('Error connecting to stream: $e');
      _displayStatusMessage('Error connecting to stream: ${e.toString().split('\n')[0]}');
      setState(() {
        _isStreamActive = false;
        _isLoadingPreview = false;
      });
      
      // Try image polling as fallback
      _startImagePolling();
    }
  }
  
  void _startImagePolling() {
    debugPrint('Starting image polling');
    // Clear any existing timer
    _refreshTimer?.cancel();
    
    // Create a new timer to periodically fetch images
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _fetchSingleImage();
    });
  }
  
  Future<void> _fetchSingleImage() async {
    if (!mounted) return;
    
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (settings.esp32Url == null || settings.esp32Url!.isEmpty) return;
    
    try {
      // Request a single image from the camera
      final response = await http.get(
        Uri.parse('${settings.esp32Url}/capture'), 
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        if (!mounted) return;
        
        setState(() {
          _previewImageBytes = response.bodyBytes;
          _isLoadingPreview = false;
        });
        
        // Don't update the message if scanning is active
        if (!_isScanning) {
          _displayStatusMessage('Preview refreshed');
        }
      }
    } catch (e) {
      // Silently fail during polling
      debugPrint('Image polling error: $e');
    }
  }
  
  void _stopCameraPreview() {
    _streamController?.close();
    _streamController = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    
    setState(() {
      _isStreamActive = false;
    });
  }
  
  void _restartCameraPreview() {
    if (!mounted) return;
    
    _stopCameraPreview();
    
    // Restart after a short delay
    Future.delayed(Duration(seconds: 2), () {
      if (mounted) _startCameraPreview();
    });
  }
  
  void _startScanning() {
    if (_isScanning) return;
    
    setState(() {
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
    _scanTimer?.cancel();
    _scanTimer = null;
    
    setState(() {
      _isScanning = false;
      _statusMessage = 'Scan stopped';
    });
    
    Provider.of<AttendanceProvider>(context, listen: false).stopScanning();
  }
  
  Future<void> _captureScan() async {
    final settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    
    if (settingsProvider.esp32Url == null || settingsProvider.esp32Url!.isEmpty) {
      debugPrint('_captureScan: ESP32 URL not configured');
      setState(() {
        _statusMessage = 'ESP32 camera URL not configured';
      });
      _stopScanning();
      return;
    }
    
    debugPrint('_captureScan: Starting scan with ESP32 URL: ${settingsProvider.esp32Url}');
    
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
    setState(() {
      _statusMessage = 'Processing...';
    });

    try {
      // No need to fetch a preview - we already have the live stream
      
      final response = await ApiService.recognizeFace();
      
      setState(() {
        _scanCount++;
        _lastScanTime = DateTime.now();
      });

      if (response['success']) {
        final bool recognized = response['recognized'] ?? false;
        final String name = response['name'] ?? 'Unknown';
        
        setState(() {
          if (recognized) {
            _statusMessage = 'Recognized: $name';
            if (!_recognizedProfiles.contains(name)) {
              _recognizedProfiles.add(name);
            }
          } else {
            _statusMessage = 'Not recognized';
          }
        });
      } else {
        setState(() {
          _statusMessage = 'Error: ${response['message'] ?? 'Unknown error'}';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString().split('\n')[0]}';
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
                      child: _isLoadingPreview
                          ? const Center(child: CircularProgressIndicator())
                          : _isStreamActive
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: StreamBuilder<Uint8List>(
                                    stream: _streamController?.stream,
                                    builder: (context, snapshot) {
                                      if (snapshot.hasError) {
                                        return Center(
                                          child: Text('Stream error: ${snapshot.error}'),
                                        );
                                      }
                                      
                                      if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
                                        if (_previewImageBytes != null) {
                                          // Show the polled image while waiting for stream
                                          return Image.memory(
                                            _previewImageBytes!,
                                            fit: BoxFit.contain,
                                          );
                                        }
                                        
                                        return const Center(
                                          child: CircularProgressIndicator(),
                                        );
                                      }
                                      
                                      return Image.memory(
                                        snapshot.data!,
                                        gaplessPlayback: true,
                                        fit: BoxFit.contain,
                                      );
                                    },
                                  ),
                                )
                              : _previewImageBytes != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        _previewImageBytes!,
                                        fit: BoxFit.contain,
                                      ),
                                    )
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: const [
                                        Icon(Icons.camera_alt, size: 48, color: Colors.grey),
                                        SizedBox(height: 16),
                                        Text(
                                          'No preview available',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ],
                                    ),
                    ),
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
}

// Add this extension to support Math.min function
extension Math on num {
  static int min(int a, int b) => a < b ? a : b;
}