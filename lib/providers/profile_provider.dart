import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:attendance/models/profile.dart';
import 'package:attendance/services/api_service.dart';

class ProfileProvider with ChangeNotifier {
  List<Profile> _profiles = [];
  bool _isLoading = false;
  String? _error;
  
  List<Profile> get profiles => _profiles;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  Future<void> fetchProfiles() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _profiles = await ApiService.getProfiles();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
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
  
  Future<bool> createProfile(Profile profile, File imageFile) async {
    debugPrint('ProfileProvider.createProfile: Starting profile creation');
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      debugPrint('ProfileProvider.createProfile: Calling ApiService.createProfile');
      final newProfile = await ApiService.createProfile(profile, imageFile);
      
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
  
  Future<bool> updateProfile(Profile profile, {File? imageFile}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final updatedProfile = await ApiService.updateProfile(profile, imageFile: imageFile);
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
}