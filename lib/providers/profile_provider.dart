import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:attendance/models/profile.dart';
import 'package:attendance/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileProvider with ChangeNotifier {
  List<Profile> _profiles = [];
  bool _isLoading = false;
  String? _error;
  
  List<Profile> get profiles => _profiles;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  ProfileProvider() {
    debugPrint('ProfileProvider: Initializing provider');
    // Check if we have an auth token before loading profiles
    _checkAuthAndLoadProfiles();
  }
  
  Future<void> _checkAuthAndLoadProfiles() async {
    debugPrint('ProfileProvider._checkAuthAndLoadProfiles: Checking authentication state');
    try {
      final prefs = await ApiService.ensureSharedPreferences();
      final token = prefs.getString('auth_token');
      
      if (token == null) {
        debugPrint('ProfileProvider._checkAuthAndLoadProfiles: No auth token found');
        _error = 'Not authenticated';
        notifyListeners();
        return;
      }
      
      debugPrint('ProfileProvider._checkAuthAndLoadProfiles: Auth token found, loading profiles');
      await fetchProfiles();
    } catch (e) {
      debugPrint('ProfileProvider._checkAuthAndLoadProfiles error: $e');
      _error = e.toString();
      notifyListeners();
    }
  }
  
  Future<void> fetchProfiles() async {
    debugPrint('ProfileProvider.fetchProfiles: Starting to fetch profiles');
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      debugPrint('ProfileProvider.fetchProfiles: Calling ApiService.getProfiles');
      _profiles = await ApiService.getProfiles();
      debugPrint('ProfileProvider.fetchProfiles: Successfully fetched ${_profiles.length} profiles');
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      debugPrint('ProfileProvider.fetchProfiles error: $_error');
      notifyListeners();
    }
  }
  
  Future<Profile?> getProfileById(String id) async {
    try {
      return await ApiService.getProfileById(id);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }
  
  Future<bool> createProfile(Profile profile, List<File> imageFiles) async {
    debugPrint('ProfileProvider.createProfile: Starting profile creation');
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      debugPrint('ProfileProvider.createProfile: Calling ApiService.createProfile');
      final newProfile = await ApiService.createProfile(profile, imageFiles);
      
      debugPrint('ProfileProvider.createProfile: Profile created successfully, adding to list');
      _profiles.add(newProfile);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      debugPrint('ProfileProvider.createProfile error: $_error');
      notifyListeners();
      return false;
    }
  }
  
  Future<bool> updateProfile(Profile profile, {List<File>? imageFiles}) async {
    debugPrint('ProfileProvider.updateProfile: Starting profile update for ID: ${profile.id}');
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      debugPrint('ProfileProvider.updateProfile: Calling ApiService.updateProfile');
      final updatedProfile = await ApiService.updateProfile(
        profile.id,
        name: profile.name,
        email: profile.email,
        bloodGroup: profile.bloodGroup,
        regNumber: profile.regNumber,
        university: profile.university,
        isActive: profile.isActive,
        imageFile: imageFiles?.isNotEmpty == true ? imageFiles!.first : null,
      );
      
      // If additional face images are provided (beyond the first one), add them
      if (imageFiles != null && imageFiles.length > 1) {
        debugPrint('ProfileProvider.updateProfile: Adding additional face images');
        for (int i = 1; i < imageFiles.length; i++) {
          await ApiService.addFaceImage(profile.id, imageFiles[i]);
        }
      }
      
      debugPrint('ProfileProvider.updateProfile: Profile updated successfully, updating list');
      final index = _profiles.indexWhere((p) => p.id == profile.id);
      if (index != -1) {
        _profiles[index] = updatedProfile;
      } else {
        debugPrint('ProfileProvider.updateProfile: Profile not found in local list, adding it');
        _profiles.add(updatedProfile);
      }
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      debugPrint('ProfileProvider.updateProfile error: $_error');
      notifyListeners();
      return false;
    }
  }
  
  Future<bool> deleteProfile(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final success = await ApiService.deleteProfile(id);
      if (success) {
        _profiles.removeWhere((profile) => profile.id == id);
      }
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }
  
  Future<bool> addEsp32CameraImages(Profile profile) async {
    debugPrint('ProfileProvider.addEsp32CameraImages: Starting to capture ESP32 images');
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      // Capture image from ESP32 camera
      final imageFile = await ApiService.captureImage();
      debugPrint('ProfileProvider.addEsp32CameraImages: Image captured successfully');
      
      // Add the captured image to the profile
      final updatedProfile = await ApiService.addFaceImages(profile.id, [imageFile]);
      
      // Update the profile in the local list
      final index = _profiles.indexWhere((p) => p.id == profile.id);
      if (index != -1) {
        _profiles[index] = updatedProfile;
      }
      
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      debugPrint('ProfileProvider.addEsp32CameraImages error: $_error');
      notifyListeners();
      return false;
    }
  }
  
  Future<void> refreshProfiles() async {
    debugPrint('ProfileProvider.refreshProfiles: Refreshing profile list');
    return fetchProfiles();
  }
}