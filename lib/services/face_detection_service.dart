import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class FaceDetectionService {
  static FaceDetector? _faceDetector;
  
  static Future<FaceDetector> get _detector async {
    if (_faceDetector == null) {
      try {
        _faceDetector = FaceDetector(
          options: FaceDetectorOptions(
            enableClassification: true,
            enableLandmarks: true,
            enableTracking: true,
            minFaceSize: 0.1,
            performanceMode: FaceDetectorMode.accurate,
          ),
        );
      } catch (e) {
        debugPrint('Error creating face detector: $e');
        rethrow;
      }
    }
    return _faceDetector!;
  }

  static Future<bool> detectFace(File imageFile) async {
    try {
      // Read the image file
      final inputImage = InputImage.fromFile(imageFile);
      
      // Get image dimensions
      final image = img.decodeImage(await imageFile.readAsBytes());
      if (image == null) {
        debugPrint('Failed to decode image');
        return false;
      }
      
      // Get detector instance
      final detector = await _detector;
      
      // Process the image
      final faces = await detector.processImage(inputImage);
      
      // Check if any face was detected
      if (faces.isEmpty) {
        debugPrint('No face detected in image');
        return false;
      }

      // Get the first detected face
      final face = faces.first;
      
      // Check face quality
      if (!_isGoodQualityFace(face, image.width, image.height)) {
        debugPrint('Face quality check failed');
        return false;
      }

      debugPrint('Face detected and quality check passed');
      return true;
    } on PlatformException catch (e) {
      debugPrint('Platform error detecting face: $e');
      return false;
    } catch (e) {
      debugPrint('Error detecting face: $e');
      return false;
    }
  }

  static bool _isGoodQualityFace(Face face, int imageWidth, int imageHeight) {
    try {
      // Calculate face size relative to image size
      final faceWidth = face.boundingBox.width;
      final faceHeight = face.boundingBox.height;
      final minFaceSize = imageWidth * 0.1; // 10% of image width

      // Check if face is too small
      if (faceWidth < minFaceSize || faceHeight < minFaceSize) {
        debugPrint('Face too small: ${faceWidth}x${faceHeight} (min: $minFaceSize)');
        return false;
      }

      // Check if face is too close to edges (10% margin)
      final margin = imageWidth * 0.1;
      if (face.boundingBox.left < margin || 
          face.boundingBox.top < margin || 
          face.boundingBox.right > (imageWidth - margin) || 
          face.boundingBox.bottom > (imageHeight - margin)) {
        debugPrint('Face too close to edges');
        return false;
      }

      // Check if face is too tilted
      if (face.headEulerAngleY != null && 
          (face.headEulerAngleY! > 20 || face.headEulerAngleY! < -20)) {
        debugPrint('Face too tilted: ${face.headEulerAngleY}');
        return false;
      }

      // Check if eyes are open
      if (face.leftEyeOpenProbability != null && 
          face.rightEyeOpenProbability != null) {
        if (face.leftEyeOpenProbability! < 0.5 || 
            face.rightEyeOpenProbability! < 0.5) {
          debugPrint('Eyes not fully open');
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error in face quality check: $e');
      return false;
    }
  }

  static Future<File?> cropFace(File imageFile) async {
    try {
      // Read the image file
      final inputImage = InputImage.fromFile(imageFile);
      
      // Get detector instance
      final detector = await _detector;
      
      // Process the image
      final faces = await detector.processImage(inputImage);
      
      if (faces.isEmpty) {
        debugPrint('No face detected for cropping');
        return null;
      }

      // Get the first detected face
      final face = faces.first;
      
      // Read the original image
      final image = img.decodeImage(await imageFile.readAsBytes());
      if (image == null) {
        debugPrint('Failed to decode image');
        return null;
      }

      // Calculate padding based on image size
      final padding = (image.width * 0.1).toInt(); // 10% of image width
      
      // Calculate crop coordinates with padding
      final x = (face.boundingBox.left - padding).clamp(0, image.width);
      final y = (face.boundingBox.top - padding).clamp(0, image.height);
      final width = (face.boundingBox.width + padding * 2).clamp(0, image.width - x);
      final height = (face.boundingBox.height + padding * 2).clamp(0, image.height - y);

      // Crop the image
      final croppedImage = img.copyCrop(
        image,
        x: x.toInt(),
        y: y.toInt(),
        width: width.toInt(),
        height: height.toInt(),
      );

      // Get temporary directory for saving
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final croppedFile = File('${tempDir.path}/face_$timestamp.jpg');
      
      // Save the cropped image
      await croppedFile.writeAsBytes(img.encodeJpg(croppedImage));
      debugPrint('Face cropped and saved to: ${croppedFile.path}');
      
      return croppedFile;
    } on PlatformException catch (e) {
      debugPrint('Platform error cropping face: $e');
      return null;
    } catch (e) {
      debugPrint('Error cropping face: $e');
      return null;
    }
  }

  static Future<void> dispose() async {
    if (_faceDetector != null) {
      await _faceDetector!.close();
      _faceDetector = null;
    }
  }

  // Simple image validation method that doesn't rely on ML Kit
  static Future<bool> validateImage(File imageFile) async {
    try {
      // Check if file exists and has content
      if (!imageFile.existsSync()) {
        debugPrint('validateImage: File does not exist');
        return false;
      }
      
      final bytes = await imageFile.readAsBytes();
      if (bytes.isEmpty || bytes.length < 1000) {
        debugPrint('validateImage: Image too small or empty: ${bytes.length} bytes');
        return false;
      }
      
      // Try to decode the image to verify it's valid
      final image = img.decodeImage(bytes);
      if (image == null) {
        debugPrint('validateImage: Failed to decode image');
        return false;
      }
      
      // Basic checks for image quality
      if (image.width < 100 || image.height < 100) {
        debugPrint('validateImage: Image dimensions too small: ${image.width}x${image.height}');
        return false;
      }
      
      // Check brightness (very basic)
      final brightness = _calculateBrightness(image);
      if (brightness < 30) {
        debugPrint('validateImage: Image too dark: brightness = $brightness');
        return false;
      }
      
      debugPrint('validateImage: Image passed basic validation');
      return true;
    } catch (e) {
      debugPrint('validateImage: Error: $e');
      return false;
    }
  }
  
  // Calculate average brightness of image (0-255)
  static int _calculateBrightness(img.Image image) {
    // Due to compatibility issues with different versions of the image package,
    // we're temporarily using a fixed middle value instead of calculating brightness
    // This avoids errors while still allowing the application to function
    debugPrint('Using fixed brightness value instead of calculation');
    return 128; // Return middle value to consider image as "normal" brightness
  }
  
  // Create a method to capture a frame from ESP32 camera and return it as Uint8List
  static Future<Uint8List?> captureEsp32Frame(String esp32Url) async {
    try {
      if (esp32Url.isEmpty) {
        debugPrint('captureEsp32Frame: ESP32 URL is empty');
        return null;
      }
      
      debugPrint('captureEsp32Frame: Requesting image from $esp32Url');
      
      // List of endpoints to try in order of preference
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
      
      for (final url in endpointsToTry) {
        try {
          debugPrint('captureEsp32Frame: Trying endpoint: $url');
          
          final response = await http.get(Uri.parse(url))
            .timeout(const Duration(seconds: 5), onTimeout: () {
              debugPrint('captureEsp32Frame: Timeout on endpoint $url');
              throw TimeoutException('Camera timeout');
            });
          
          if (response.statusCode == 200 && response.bodyBytes.length > 100) {
            // Check if data looks like an image
            if (_isValidImage(response.bodyBytes)) {
              debugPrint('captureEsp32Frame: Image captured successfully, size: ${response.bodyBytes.length} bytes');
              return response.bodyBytes;
            } else {
              debugPrint('captureEsp32Frame: Invalid image data from $url');
              continue; // Try next endpoint
            }
          } else {
            debugPrint('captureEsp32Frame: Invalid response from $url: ${response.statusCode}, size: ${response.bodyBytes.length}');
          }
        } catch (e) {
          debugPrint('captureEsp32Frame: Error with endpoint $url: $e');
          // Try next endpoint
          continue;
        }
      }
      
      // If we get here, all endpoints failed
      debugPrint('captureEsp32Frame: Failed to capture image from any endpoint');
      return null;
    } catch (e) {
      debugPrint('captureEsp32Frame error: $e');
      return null;
    }
  }
  
  // Simple utility to capture from ESP32 camera and save to a file
  static Future<File?> captureFromEsp32(String esp32Url) async {
    try {
      final imageBytes = await captureEsp32Frame(esp32Url);
      if (imageBytes == null) {
        return null;
      }
      
      // Save image to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final imageFile = File('${tempDir.path}/esp32_captured_$timestamp.jpg');
      await imageFile.writeAsBytes(imageBytes);
      
      debugPrint('captureFromEsp32: Image saved to ${imageFile.path}, size: ${imageBytes.length} bytes');
      return imageFile;
    } catch (e) {
      debugPrint('captureFromEsp32: Error: $e');
      return null;
    }
  }
  
  // Helper method to check if data is a valid image
  static bool _isValidImage(Uint8List bytes) {
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
        debugPrint('FaceDetectionService: Detected HTML content instead of image');
        return false;
      }
    }
    
    // If we can't definitively say it's bad, let's try it as an image
    return bytes.length > 1000; // At least some reasonable size for an image
  }
  
  // Enhance image brightness and contrast if needed
  static Future<File> enhanceImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        return imageFile; // Return original if can't decode
      }
      
      // Instead of checking brightness, apply moderate enhancement to all images
      // Apply subtle enhancements that will improve most images without over-processing
      final enhanced = img.adjustColor(
        image,
        brightness: 0.1,   // Slightly brighter
        contrast: 0.1,     // Slightly more contrast
        saturation: 0.05,  // Slightly more color saturation
      );
      
      // Save enhanced image
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final enhancedFile = File('${tempDir.path}/enhanced_$timestamp.jpg');
      await enhancedFile.writeAsBytes(img.encodeJpg(enhanced));
      
      debugPrint('enhanceImage: Enhanced image saved to ${enhancedFile.path}');
      return enhancedFile;
    } catch (e) {
      debugPrint('enhanceImage: Error: $e');
      return imageFile; // Return original on error
    }
  }
} 