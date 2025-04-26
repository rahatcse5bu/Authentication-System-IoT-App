import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendance_app/providers/settings_provider.dart';
import 'package:attendance_app/providers/attendance_provider.dart';
import 'package:attendance_app/providers/profile_provider.dart';
import 'package:attendance_app/services/api_service.dart';

class ScanScreen extends StatefulWidget {
  @override
  _ScanScreenState createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  Timer? _scanTimer;
  File? _currentImage;
  String _statusMessage = 'Ready to scan';
  bool _isScanning = false;
  
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
    });
    
    Provider.of<AttendanceProvider>(context, listen: false).startScanning();
    
    // Scan every 2 seconds
    _scanTimer = Timer.periodic(const Duration(seconds: 2), (_) => _captureScan());
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
      
      final imageFile = await ApiService.captureImage();
      
      setState(() {
        _currentImage = imageFile;
        _statusMessage = 'Processing image...';
      });
      
      // In a real app, you'd send this image to your backend for face recognition
      // Here we're just simulating it with a delay
      await Future.delayed(const Duration(milliseconds: 800));
      
      // In a real implementation, your backend would return recognized profiles
      // For now, we'll just update the status
      setState(() {
        _statusMessage = 'Ready for next scan';
      });
      
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
      });
      
      final imageFile = await ApiService.captureImage();
      
      setState(() {
        _currentImage = imageFile;
        _statusMessage = 'Image captured';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
    }
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
                  const Text('ESP32 camera URL not configured'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pushNamed(context, '/settings');
                    },
                    child: const Text('Configure Settings'),
                  ),
                ],
              ),
            );
                      
          return Column(
            children: [
              Expanded(
                child: Center(
                  child: _currentImage != null
                      ? Image.file(
                          _currentImage!,
                          fit: BoxFit.contain,
                        )
                      : const Text('No image captured yet'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      _statusMessage,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Single Capture'),
                          onPressed: _isScanning ? null : _singleCapture,
                        ),
                        ElevatedButton.icon(
                          icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
                          label: Text(_isScanning ? 'Stop Scanning' : 'Start Scanning'),
                          onPressed: _isScanning ? _stopScanning : _startScanning,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isScanning ? Colors.red : null,
                          ),
                        ),
                      ],
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
