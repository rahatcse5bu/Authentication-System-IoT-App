// lib/screens/scan_screen.dart
// Updated to use the correct API method for face recognition

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
  
  // Preview image variables
  Uint8List? _previewImageBytes;
  bool _isLoadingPreview = false;

  @override
  void initState() {
    super.initState();
    // No need to initialize _apiService again as it's already done in the field declaration
    
    // Fetch preview image on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchPreview(showLoadingIndicator: true);
    });
  }
  
  @override
  void dispose() {
    _stopScanning();
    super.dispose();
  }
  
  void _displayStatusMessage(String message) {
    setState(() {
      _statusMessage = message;
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
    
    if (settingsProvider.esp32Url!.isEmpty) {
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
        _statusMessage = 'Capturing image...';
      });
      
      // Update scan stats
      _scanCount++;
      _lastScanTime = DateTime.now();
      debugPrint('_captureScan: Scan #$_scanCount at ${_lastScanTime.toString()}');
      
      setState(() {
        _statusMessage = 'Processing image...';
      });
      
      // Call the API to mark attendance with face recognition
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
      await _fetchPreview(); // Get preview image first
      
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
  
  Future<void> _fetchPreview({bool showLoadingIndicator = true}) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (settings.esp32Url!.isEmpty) {
      setState(() {
        _statusMessage = 'ESP32 camera URL not configured';
        _isLoadingPreview = false;
      });
      return;
    }

    if (showLoadingIndicator) {
      setState(() {
        _isLoadingPreview = true;
      });
    }

    try {
      final response = await http.get(
        Uri.parse('${settings.esp32Url}/capture'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          _previewImageBytes = response.bodyBytes;
          _isLoadingPreview = false;
        });
      } else {
        setState(() {
          _previewImageBytes = null;
          _isLoadingPreview = false;
          _statusMessage = 'Error fetching preview: HTTP ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _previewImageBytes = null;
        _isLoadingPreview = false;
        _statusMessage = 'Error fetching preview: ${e.toString().split('\n')[0]}';
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
                _previewImageBytes = null;
              });
              _fetchPreview(showLoadingIndicator: true);
            },
            tooltip: 'Reset',
          ),
        ],
      ),
      body: Consumer2<ProfileProvider, SettingsProvider>(
        builder: (context, profileProvider, settingsProvider, child) {
          // Check if ESP32 URL is configured
          if (settingsProvider.esp32Url!.isEmpty) {
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
                          _isScanning ? Icons.sync : Icons.info_outline,
                          color: _isScanning ? Colors.green : Colors.blue,
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
                        onPressed: _isLoadingPreview ? null : () => _fetchPreview(showLoadingIndicator: true),
                        tooltip: 'Refresh preview',
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