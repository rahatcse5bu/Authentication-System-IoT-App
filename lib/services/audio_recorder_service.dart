import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioRecorderService {
  static final AudioRecorderService _instance = AudioRecorderService._internal();
  factory AudioRecorderService() => _instance;
  
  AudioRecorderService._internal();
  
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _recordedFilePath;
  StreamSubscription<RecordState>? _recordSub;
  
  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  String? get recordedFilePath => _recordedFilePath;
  
  Future<bool> checkPermissions() async {
    try {
      // Use a try-catch block specifically for the permission request
      try {
        final microphoneStatus = await Permission.microphone.request();
        debugPrint('Microphone permission status: ${microphoneStatus.toString()}');
        return microphoneStatus.isGranted;
      } catch (permissionError) {
        debugPrint('Specific error requesting microphone permission: $permissionError');
        
        // Try an alternative approach
        final microphoneStatus = await Permission.microphone.status;
        if (microphoneStatus.isDenied) {
          openAppSettings();
          return false;
        }
        return microphoneStatus.isGranted;
      }
    } catch (e) {
      debugPrint('Error requesting microphone permission: $e');
      return false;
    }
  }
  
  Future<bool> startRecording() async {
    try {
      // Clear previous recording
      if (_recordedFilePath != null) {
        final file = File(_recordedFilePath!);
        if (await file.exists()) {
          await file.delete();
        }
        _recordedFilePath = null;
      }
      
      // Check permissions
      if (!await checkPermissions()) {
        throw Exception('Microphone permission denied');
      }
      
      // Check and request microphone permission
      final isPermitted = await _audioRecorder.hasPermission();
      if (!isPermitted) {
        throw Exception('Audio recording permissions not granted');
      }
      
      // Prepare destination path
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${appDir.path}/voice_record_$timestamp.wav';
      
      // Configure recording
      await _audioRecorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,  // Using WAV format for quality
          bitRate: 128000,
          sampleRate: 44100,
        ), 
        path: filePath,
      );
      
      // Get the recorder state
      _recordSub?.cancel();
      _recordSub = _audioRecorder.onStateChanged().listen((recordState) {
        debugPrint('Recording state: $recordState');
      });
      
      _isRecording = true;
      _recordedFilePath = filePath;
      
      return true;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      return false;
    }
  }
  
  Future<String?> stopRecording() async {
    try {
      if (!_isRecording) return _recordedFilePath;
      
      final filePath = await _audioRecorder.stop();
      _isRecording = false;
      _recordedFilePath = filePath;
      
      _recordSub?.cancel();
      _recordSub = null;
      
      debugPrint('Recording stopped, saved to: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _isRecording = false;
      return null;
    }
  }
  
  Future<bool> playRecording() async {
    try {
      if (_recordedFilePath == null) return false;
      
      if (_isPlaying) {
        await _audioPlayer.stop();
      }
      
      await _audioPlayer.play(DeviceFileSource(_recordedFilePath!));
      _isPlaying = true;
      
      // Listen for completion
      _audioPlayer.onPlayerComplete.listen((event) {
        _isPlaying = false;
      });
      
      return true;
    } catch (e) {
      debugPrint('Error playing recording: $e');
      return false;
    }
  }
  
  Future<void> stopPlaying() async {
    if (!_isPlaying) return;
    
    await _audioPlayer.stop();
    _isPlaying = false;
  }
  
  Future<void> dispose() async {
    await _recordSub?.cancel();
    await _audioRecorder.dispose();
    await _audioPlayer.dispose();
    _isRecording = false;
    _isPlaying = false;
  }
} 