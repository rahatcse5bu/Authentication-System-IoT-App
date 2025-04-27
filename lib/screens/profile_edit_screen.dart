import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '../models/profile.dart';
import '../providers/profile_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';

class ProfileEditScreen extends StatefulWidget {
  final Profile? profile;
  
  const ProfileEditScreen({Key? key, this.profile}) : super(key: key);
  
  @override
  _ProfileEditScreenState createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _bloodGroupController = TextEditingController();
  final _regNumberController = TextEditingController();
  final _universityController = TextEditingController();
  
  File? _imageFile;
  bool _isProcessing = false;
  
  // ESP32 Camera preview variables
  bool _showCameraPreview = false;
  Uint8List? _previewImageBytes;
  Timer? _previewTimer;
  StreamController<Uint8List>? _streamController;
  bool _isStreamActive = false;
  bool _isLoadingPreview = false;
  
  // Animation controller for smooth transitions
  late AnimationController _fadeController;
  
  // Cached provider reference
  SettingsProvider? _settingsProvider;
  String? _cachedEsp32Url;
  bool _isDisposing = false;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeController.value = 1.0;
    
    if (widget.profile != null) {
      _nameController.text = widget.profile!.name;
      _emailController.text = widget.profile!.email;
      _bloodGroupController.text = widget.profile!.bloodGroup;
      _regNumberController.text = widget.profile!.regNumber;
      _universityController.text = widget.profile!.university;
    }
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache provider references for safer access during disposal
    _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _cachedEsp32Url = _settingsProvider?.esp32Url;
  }
  
  @override
  void dispose() {
    _isDisposing = true;
    _nameController.dispose();
    _emailController.dispose();
    _bloodGroupController.dispose();
    _regNumberController.dispose();
    _universityController.dispose();
    _stopCameraPreview();
    if (_previewTimer != null) {
      _previewTimer!.cancel();
      _previewTimer = null;
    }
    _fadeController.dispose();
    super.dispose();
  }
  
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        final File imageFile = File(pickedFile.path);
        debugPrint('Image picked from: ${imageFile.path}');
        
        // Verify file exists and has content
        if (await imageFile.exists()) {
          final size = await imageFile.length();
          debugPrint('Image size: $size bytes');
          
          if (size > 0) {
            setState(() {
              _imageFile = imageFile;
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Selected image is empty')),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access the selected image')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }
  
  Future<void> _toggleESP32Camera() async {
    setState(() {
      _showCameraPreview = !_showCameraPreview;
    });
    
    if (_showCameraPreview) {
      await _startCameraPreview();
    } else {
      _stopCameraPreview();
    }
  }
  
  Future<void> _startCameraPreview() async {
    if (!mounted || _isDisposing) return;
    
    try {
      // Use cached ESP32 URL to prevent context access during disposal
      final String? esp32Url = _cachedEsp32Url ?? _settingsProvider?.esp32Url;
      if (esp32Url == null || esp32Url.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ESP32 camera URL not configured. Please check settings.')),
        );
        setState(() {
          _showCameraPreview = false;
        });
        return;
      }
      
      // Update cached URL
      _cachedEsp32Url = esp32Url;
      
      // Fade out current preview
      _fadeController.reverse();
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (!mounted) return;
      
      // Create stream controller
      if (_streamController != null) {
        _streamController!.close();
      }
      _streamController = StreamController<Uint8List>.broadcast();
      
      setState(() {
        _isStreamActive = true;
        _isLoadingPreview = true;
      });
      
      try {
        // Try direct image capture first for immediate feedback - use base URL
        await _fetchSingleImage();
        
        // No need to try MJPEG streaming since it doesn't work
        _fadeController.forward();
        
        // Start image polling
        _startImagePolling();
      } catch (e) {
        debugPrint('Profile screen connection error: $e');
        
        if (!mounted) return;
        
        // Try a different approach
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Using alternative connection method')),
        );
        _startImagePolling();
        _fadeController.forward();
      }
    } catch (e) {
      debugPrint('Error in startCameraPreview: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error connecting to camera: ${e.toString().split('\n')[0]}')),
        );
        setState(() {
          _showCameraPreview = false;
          _isLoadingPreview = false;
        });
      }
    }
  }
  
  void _processMjpegStream(Stream<List<int>> stream) {
    if (!mounted || !_isStreamActive || _streamController == null || _streamController!.isClosed) return;
    
    // More flexible boundary patterns
    final List<RegExp> boundaryRegExps = [
      RegExp(r'--[a-zA-Z0-9\.\-_]+'), // Standard boundary
      RegExp(r'Content-Type: image/jpeg'), // Some cameras use this as marker
    ];
    final RegExp headerEndRegExp = RegExp(r'\r\n\r\n|\n\n');
    
    List<int> buffer = [];
    bool inHeader = true;
    bool loggedFirstFrame = false;
    int frameCount = 0;
    
    setState(() {
      _isLoadingPreview = false;
    });
    
    stream.listen(
      (List<int> chunk) {
        if (!mounted || !_isStreamActive || _streamController == null || _streamController!.isClosed) return;
        
        buffer.addAll(chunk);
        
        // Log first chunk for debugging
        if (!loggedFirstFrame && buffer.length > 50) {
          loggedFirstFrame = true;
          final String bufferStart = String.fromCharCodes(buffer.take(50).toList());
          debugPrint('First 50 chars of buffer: $bufferStart');
        }
        
        while (buffer.isNotEmpty) {
          if (inHeader) {
            // Find end of headers - try different patterns
            final String bufferStr = String.fromCharCodes(buffer.take(Math.min(buffer.length, 512)).toList());
            
            // Check for standard header endings
            final Match? match = headerEndRegExp.firstMatch(bufferStr);
            int headerEnd = -1;
            
            if (match != null) {
              headerEnd = match.end;
            } else {
              // Check for raw JPEG start
              for (int i = 0; i < buffer.length - 3; i++) {
                if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8 && buffer[i + 2] == 0xFF) {
                  headerEnd = i;
                  debugPrint('Found direct JPEG start at position $i');
                  break;
                }
              }
            }
            
            if (headerEnd >= 0) {
              // Remove header from buffer
              buffer = buffer.sublist(headerEnd);
              inHeader = false;
            } else if (buffer.length > 8192) {
              // Buffer too large without finding header end, reset
              buffer = buffer.sublist(buffer.length - 1024);
              debugPrint('Buffer too large, trimming');
            } else {
              break; // Need more data
            }
          } else {
            // In image data, look for next boundary
            Match? boundaryMatch = null;
            int boundaryPos = -1;
            
            // Try to find boundary with regex
            final String bufferStr = String.fromCharCodes(buffer.take(Math.min(buffer.length, 200)).toList());
            for (final regex in boundaryRegExps) {
              final match = regex.firstMatch(bufferStr);
              if (match != null) {
                boundaryMatch = match;
                boundaryPos = match.start;
                break;
              }
            }
            
            // If regex didn't find anything, check for raw JPEG markers
            if (boundaryMatch == null) {
              // Look for next JPEG start marker
              for (int i = 2; i < buffer.length - 3; i++) {
                if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8 && buffer[i + 2] == 0xFF) {
                  boundaryPos = i;
                  break;
                }
                
                // Also check for JPEG EOI marker followed by boundary text
                if (i > 0 && buffer[i - 1] == 0xFF && buffer[i] == 0xD9 && 
                    // Make sure we have some reasonable data
                    i > 1000) {
                  for (int j = i + 1; j < Math.min(i + 20, buffer.length - 1); j++) {
                    if (buffer[j] == 45 && buffer[j + 1] == 45) { // "--" in ASCII
                      boundaryPos = i + 1;
                      break;
                    }
                  }
                  if (boundaryPos >= 0) break;
                }
              }
            }
            
            if (boundaryPos > 0) {
              // We have a complete frame
              final List<int> frameData = buffer.sublist(0, boundaryPos);
              
              // If frame looks valid, process it
              if (frameData.length > 100) {
                final imageBytes = Uint8List.fromList(frameData);
                frameCount++;
                
                // Store the latest image for capture
                _previewImageBytes = imageBytes;
                
                // Add to stream
                if (_streamController != null && !_streamController!.isClosed) {
                  _streamController!.add(imageBytes);
                }
                
                if (frameCount % 30 == 0) {
                  debugPrint('Processed $frameCount frames');
                }
              }
              
              // Remove frame and start looking for next header
              buffer = buffer.sublist(boundaryPos);
              inHeader = true;
            } else if (buffer.length > 200000) {
              // Buffer too big with no boundary, something went wrong
              debugPrint('Buffer too large without finding boundary: ${buffer.length} bytes');
              buffer = buffer.sublist(buffer.length - 1024);
              inHeader = true;
            } else {
              break; // Need more data
            }
          }
        }
      },
      onError: (error) {
        debugPrint('Stream error: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Camera stream error: ${error.toString().split('\n')[0]}')),
          );
          _startImagePolling(); // Fallback to polling
        }
      },
      onDone: () {
        debugPrint('Stream ended');
        if (mounted && _showCameraPreview) {
          _startImagePolling(); // Fallback to polling
        }
      },
      cancelOnError: false,
    );
  }
  
  void _startImagePolling() {
    if (!mounted || !_showCameraPreview) return;
    
    debugPrint('Starting image polling for profile');
    // Clear any existing timer
    _previewTimer?.cancel();
    
    setState(() {
      _isLoadingPreview = false;
    });
    
    // Try to get first image immediately
    _fetchSingleImage();
    
    // Create a new timer to periodically fetch images
    _previewTimer = Timer.periodic(const Duration(milliseconds: 750), (_) {
      if (mounted && _showCameraPreview) {
        _fetchSingleImage();
      } else if (_previewTimer != null) {
        _previewTimer!.cancel();
        _previewTimer = null;
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
        debugPrint('Profile screen: Detected HTML content instead of image');
        return false;
      }
    }
    
    // If we can't definitively say it's bad, let's try it as an image
    return bytes.length > 1000; // At least some reasonable size for an image
  }
  
  Future<void> _fetchSingleImage() async {
    if (!mounted || _isDisposing || !_showCameraPreview) return;
    
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
          
          debugPrint('Profile screen: Fetching image from: $url');
          
          // Request a single image from the camera with increased timeout
          final response = await http.get(
            Uri.parse(url),
          ).timeout(
            const Duration(seconds: 5), 
            onTimeout: () {
              debugPrint('Profile screen: Image fetch timeout from $url');
              throw TimeoutException('Image fetch timeout');
            },
          );
          
          if (response.statusCode == 200 && response.bodyBytes.length > 100) {
            if (!mounted || _isDisposing || !_showCameraPreview) return;
            
            final imageBytes = response.bodyBytes;
            debugPrint('Profile screen: Received image, size: ${imageBytes.length} bytes');
            
            // Check Content-Type header (more reliable than guessing)
            final contentType = response.headers['content-type'] ?? '';
            final isImageContentType = contentType.toLowerCase().contains('image');
            
            // Validate the image data with our custom validator
            final bool isValidImage = _isValidJpegImage(imageBytes);
                
            if (isValidImage) {
              debugPrint('Profile screen: Valid image detected from $url');
              
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
                debugPrint('Profile screen: Error processing image: $e');
                // If we get an error processing this image, try the next endpoint
                continue;
              }
            } else {
              debugPrint('Profile screen: Invalid image format from $url, skipping');
              continue; // Try next endpoint
            }
          } else {
            debugPrint('Profile screen: Invalid response from $url: ${response.statusCode}, size: ${response.bodyBytes.length}');
          }
        } catch (e) {
          debugPrint('Profile screen: Error fetching from $url: $e');
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
      
      if (_previewTimer != null) {
        _previewTimer!.cancel();
        _previewTimer = null;
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
  
  Future<void> _captureFromESP32() async {
    // If camera preview is active and we have a preview image, use it directly
    if (_showCameraPreview && _previewImageBytes != null) {
      try {
        setState(() {
          _isProcessing = true;
        });
        
        // Use application documents directory instead of temporary directory
        final appDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final imagePath = '${appDir.path}/esp32_profile_$timestamp.jpg';
        
        final imageFile = File(imagePath);
        await imageFile.writeAsBytes(_previewImageBytes!);
        
        debugPrint('ESP32 image captured to: ${imageFile.path}');
        
        // Verify file exists and has content
        if (await imageFile.exists()) {
          final size = await imageFile.length();
          debugPrint('ESP32 image size: $size bytes');
          
          if (size > 0) {
            setState(() {
              _imageFile = imageFile;
              _isProcessing = false;
              _showCameraPreview = false; // Close preview after capture
            });
            _stopCameraPreview();
          } else {
            setState(() {
              _isProcessing = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Captured image is empty')),
            );
          }
        } else {
          setState(() {
            _isProcessing = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access the captured image')),
          );
        }
      } catch (e) {
        setState(() {
          _isProcessing = false;
        });
        
        debugPrint('Error saving ESP32 preview image: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving preview image: $e')),
        );
      }
    } else {
      // If preview isn't active, capture directly from API
      try {
        setState(() {
          _isProcessing = true;
        });
        
        // Get the captured image from API
        final tempFile = await ApiService.captureImage();
        debugPrint('ESP32 image captured to temp location: ${tempFile.path}');
        
        // Verify file exists and has content
        if (await tempFile.exists()) {
          final size = await tempFile.length();
          debugPrint('ESP32 image size: $size bytes');
          
          if (size > 0) {
            // Copy to a more permanent location
            final appDir = await getApplicationDocumentsDirectory();
            final timestamp = DateTime.now().millisecondsSinceEpoch;
            final imagePath = '${appDir.path}/esp32_profile_$timestamp.jpg';
            
            // Copy file to permanent location
            final bytes = await tempFile.readAsBytes();
            final permanentFile = File(imagePath);
            await permanentFile.writeAsBytes(bytes);
            
            debugPrint('Image copied to permanent location: ${permanentFile.path}');
            
            setState(() {
              _imageFile = permanentFile;
              _isProcessing = false;
            });
          } else {
            setState(() {
              _isProcessing = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Captured image is empty')),
            );
          }
        } else {
          setState(() {
            _isProcessing = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access the captured image')),
          );
        }
      } catch (e) {
        setState(() {
          _isProcessing = false;
        });
        
        debugPrint('Error capturing ESP32 image: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error capturing image: $e')),
        );
      }
    }
  }
  
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    if (_imageFile == null && widget.profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or capture an image')),
      );
      return;
    }
    
    // Check if image file exists
    if (_imageFile != null) {
      try {
        if (!await _imageFile!.exists()) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Image file not found: ${_imageFile!.path}')),
          );
          return;
        }
        
        final size = await _imageFile!.length();
        debugPrint('Image file size: $size bytes');
        
        if (size == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image file is empty. Please select another image.')),
          );
          return;
        }
      } catch (e) {
        debugPrint('Error checking image file: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error with image file: $e')),
        );
        return;
      }
    }
    
    setState(() {
      _isProcessing = true;
    });
    
    try {
      final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
      
      if (widget.profile == null) {
        // Create new profile
        debugPrint('ProfileEditScreen: Creating new profile');
        final newProfile = Profile(
          id: '', // Will be assigned by backend
          name: _nameController.text,
          email: _emailController.text,
          bloodGroup: _bloodGroupController.text,
          regNumber: _regNumberController.text,
          university: _universityController.text,
          imageUrl: '', // Will be assigned by backend
          registrationDate: DateTime.now(),
        );
        
        debugPrint('ProfileEditScreen: Calling profileProvider.createProfile');
        final success = await profileProvider.createProfile(newProfile, _imageFile!);
        
        if (success) {
          debugPrint('ProfileEditScreen: Profile created successfully');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile created successfully')),
          );
          Navigator.pop(context);
        } else {
          debugPrint('ProfileEditScreen: Profile creation failed');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create profile: ${profileProvider.error}')),
          );
        }
      } else {
        // Update existing profile
        debugPrint('ProfileEditScreen: Updating existing profile ${widget.profile!.id}');
        final updatedProfile = widget.profile!.copyWith(
          name: _nameController.text,
          email: _emailController.text,
          bloodGroup: _bloodGroupController.text,
          regNumber: _regNumberController.text,
          university: _universityController.text,
        );
        
        // Only pass the image file if a new one was selected
        File? imageToUpload = _imageFile;
        if (imageToUpload != null) {
          debugPrint('ProfileEditScreen: New image selected for update: ${imageToUpload.path}');
        } else {
          debugPrint('ProfileEditScreen: No new image selected, using existing image');
        }
        
        debugPrint('ProfileEditScreen: Calling profileProvider.updateProfile');
        final success = await profileProvider.updateProfile(
          updatedProfile, 
          imageFile: imageToUpload,
        );
        
        if (success) {
          debugPrint('ProfileEditScreen: Profile updated successfully');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile updated successfully')),
          );
          Navigator.pop(context);
        } else {
          debugPrint('ProfileEditScreen: Profile update failed');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update profile: ${profileProvider.error}')),
          );
        }
      }
    } catch (e) {
      debugPrint('ProfileEditScreen error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }
  
  void _restartCameraPreview() {
    _stopCameraPreview();
    Future.delayed(Duration(milliseconds: 500), () {
      if (mounted) _startCameraPreview();
    });
  }
  
  // Build camera preview with simplified approach
  Widget _buildCameraPreview() {
    if (_isLoadingPreview) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // Use a simple direct image display approach
    if (_previewImageBytes != null) {
      debugPrint('Profile screen: Using simplified image display');
      
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
              debugPrint('Profile screen: Error rendering image: $error');
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
  
  @override
  Widget build(BuildContext context) {
    // Update cached settings provider when building
    if (!_isDisposing) {
      _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      _cachedEsp32Url = _settingsProvider?.esp32Url;
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile == null ? 'Add Profile' : 'Edit Profile'),
      ),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Profile image selection or camera preview
                    if (_showCameraPreview) ...[
                      Container(
                        height: 250,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: FadeTransition(
                          opacity: _fadeController,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _buildCameraPreview(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _captureFromESP32,
                            icon: const Icon(Icons.camera),
                            label: const Text('Capture'),
                          ),
                          ElevatedButton.icon(
                            onPressed: _toggleESP32Camera,
                            icon: const Icon(Icons.close),
                            label: const Text('Close Camera'),
                          ),
                        ],
                      ),
                    ] else ...[
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              builder: (BuildContext context) {
                                return SafeArea(
                                  child: Wrap(
                                    children: <Widget>[
                                      ListTile(
                                        leading: const Icon(Icons.photo_library),
                                        title: const Text('Photo Library'),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _pickImage(ImageSource.gallery);
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.photo_camera),
                                        title: const Text('Camera'),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _pickImage(ImageSource.camera);
                                        },
                                      ),
                                      ListTile(
                                        leading: const Icon(Icons.videocam),
                                        title: const Text('ESP32 Camera'),
                                        onTap: () {
                                          Navigator.pop(context);
                                          _toggleESP32Camera();
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              shape: BoxShape.circle,
                            ),
                            child: _imageFile != null
                                ? ClipOval(
                                    child: Image.file(
                                      _imageFile!,
                                      width: 150,
                                      height: 150,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : widget.profile != null
                                    ? ClipOval(
                                        child: Image.network(
                                          widget.profile!.imageUrl,
                                          width: 150,
                                          height: 150,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Center(
                                              child: Text(
                                                widget.profile!.name[0],
                                                style: const TextStyle(fontSize: 50),
                                              ),
                                            );
                                          },
                                        ),
                                      )
                                    : const Icon(
                                        Icons.add_a_photo,
                                        size: 50,
                                        color: Colors.grey,
                                      ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter email';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bloodGroupController,
                      decoration: const InputDecoration(
                        labelText: 'Blood Group',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _regNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Registration Number',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter registration number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _universityController,
                      decoration: const InputDecoration(
                        labelText: 'University',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _saveProfile,
                      child: Text(widget.profile == null ? 'Create Profile' : 'Update Profile'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// Helper extension for math functions
extension Math on num {
  static int min(int a, int b) => a < b ? a : b;
}
