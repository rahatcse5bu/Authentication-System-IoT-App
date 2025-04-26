// lib/screens/scan_screen.dart
// Updated to use the correct API method for face recognition

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


import '../providers/attendance_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';

class ScanScreen extends StatefulWidget {
  @override
  _ScanScreenState createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  Timer? _scanTimer;
  File? _currentImage;
  String _statusMessage = 'Ready to scan';
  bool _isScanning = false;
  List<Map<String, dynamic>> _recognizedProfiles = [];
  DateTime? _lastScanTime;
  int _scanCount = 0;
  
  @override
  void dispose() {
    _stopScanning();
    super.dispose();
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
      setState(() {
        _statusMessage = 'ESP32 camera URL not configured';
      });
      _stopScanning();
      return;
    }
    
    try {
      setState(() {
        _statusMessage = 'Capturing image...';
      });
      
      // Update scan stats
      _scanCount++;
      _lastScanTime = DateTime.now();
      
      setState(() {
        _statusMessage = 'Processing image...';
      });
      
      // Call the API to mark attendance with face recognition
      // Using the correct method that returns a Map
      final result = await ApiService.markAttendanceWithFaceRecognition();
      
      if (result['results'] != null && result['results'].isNotEmpty) {
        // Add recognized profiles to the list
        for (var profile in result['results']) {
          // Check if profile is already in the list
          final existingIndex = _recognizedProfiles.indexWhere(
            (p) => p['profile_id'] == profile['profile_id']
          );
          
          if (existingIndex >= 0) {
            // Update existing profile
            _recognizedProfiles[existingIndex] = profile;
          } else {
            // Add new profile
            _recognizedProfiles.add(profile);
          }
        }
        
        setState(() {
          _statusMessage = '${result['results'].length} profile(s) recognized';
        });
      } else {
        setState(() {
          _statusMessage = 'No profiles recognized';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
    }
  }
  
  Future<void> _singleCapture() async {
    try {
      setState(() {
        _statusMessage = 'Capturing single image...';
        _lastScanTime = DateTime.now();
      });
      
      // Process a single attendance scan
      // Using the correct method that returns a Map
      final result = await ApiService.markAttendanceWithFaceRecognition();
      
      if (result['results'] != null && result['results'].isNotEmpty) {
        // Add recognized profiles to the list
        for (var profile in result['results']) {
          // Check if profile is already in the list
          final existingIndex = _recognizedProfiles.indexWhere(
            (p) => p['profile_id'] == profile['profile_id']
          );
          
          if (existingIndex >= 0) {
            // Update existing profile
            _recognizedProfiles[existingIndex] = profile;
          } else {
            // Add new profile
            _recognizedProfiles.add(profile);
          }
        }
        
        setState(() {
          _statusMessage = '${result['results'].length} profile(s) recognized';
        });
      } else {
        setState(() {
          _statusMessage = 'No profiles recognized';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
    }
  }
  
  void _clearRecognizedProfiles() {
    setState(() {
      _recognizedProfiles = [];
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, _) {
          if (settingsProvider.esp32Url == null || settingsProvider.esp32Url!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.camera_alt,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'ESP32 camera URL not configured',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      // Navigate to settings tab
                      DefaultTabController.of(context)?.animateTo(3);
                    },
                    child: const Text('Configure Settings'),
                  ),
                ],
              ),
            );
          }
          
          return Column(
            children: [
              // Status bar
              Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                child: Row(
                  children: [
                    Icon(
                      _isScanning ? Icons.camera : Icons.camera_alt,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _statusMessage,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (_lastScanTime != null)
                            Text(
                              'Last scan: ${_lastScanTime!.hour.toString().padLeft(2, '0')}:${_lastScanTime!.minute.toString().padLeft(2, '0')}:${_lastScanTime!.second.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    if (_isScanning)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Scan #$_scanCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
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
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Single Capture'),
                        onPressed: _isScanning ? null : _singleCapture,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
                        label: Text(_isScanning ? 'Stop Scanning' : 'Start Scanning'),
                        onPressed: _isScanning ? _stopScanning : _startScanning,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isScanning ? Colors.red : Theme.of(context).primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Recognized profiles
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Recognized Profiles (${_recognizedProfiles.length})',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton.icon(
                            icon: const Icon(Icons.clear_all),
                            label: const Text('Clear'),
                            onPressed: _recognizedProfiles.isEmpty ? null : _clearRecognizedProfiles,
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Expanded(
                      child: _recognizedProfiles.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.face,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No profiles recognized yet',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Start scanning to mark attendance',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: _recognizedProfiles.length,
                              itemBuilder: (context, index) {
                                final profile = _recognizedProfiles[index];
                                final isTimeOut = profile['action'] == 'time_out';
                                
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: isTimeOut ? Colors.orange : Colors.green,
                                    child: Icon(
                                      isTimeOut ? Icons.logout : Icons.login,
                                      color: Colors.white,
                                    ),
                                  ),
                                  title: Text(profile['name']),
                                  subtitle: Text(
                                    '${isTimeOut ? 'Time Out' : 'Time In'}: ${profile['time'].substring(11, 19)}',
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isTimeOut ? Colors.orange.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      isTimeOut ? 'OUT' : 'IN',
                                      style: TextStyle(
                                        color: isTimeOut ? Colors.orange : Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                );
                              },
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