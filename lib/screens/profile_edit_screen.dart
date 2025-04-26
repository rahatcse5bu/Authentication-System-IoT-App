import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendance/models/profile.dart';
import 'package:attendance/providers/profile_provider.dart';
import 'package:attendance/services/api_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

class ProfileEditScreen extends StatefulWidget {
  final Profile? profile;
  
  const ProfileEditScreen({Key? key, this.profile}) : super(key: key);
  
  @override
  _ProfileEditScreenState createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _bloodGroupController = TextEditingController();
  final _regNumberController = TextEditingController();
  final _universityController = TextEditingController();
  
  File? _imageFile;
  bool _isProcessing = false;
  
  @override
  void initState() {
    super.initState();
    
    if (widget.profile != null) {
      _nameController.text = widget.profile!.name;
      _emailController.text = widget.profile!.email;
      _bloodGroupController.text = widget.profile!.bloodGroup;
      _regNumberController.text = widget.profile!.regNumber;
      _universityController.text = widget.profile!.university;
    }
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _bloodGroupController.dispose();
    _regNumberController.dispose();
    _universityController.dispose();
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
  
  Future<void> _captureFromESP32() async {
    try {
      setState(() {
        _isProcessing = true;
      });
      
      final File imageFile = await ApiService.captureImage();
      debugPrint('ESP32 image captured to: ${imageFile.path}');
      
      // Verify file exists and has content
      if (await imageFile.exists()) {
        final size = await imageFile.length();
        debugPrint('ESP32 image size: $size bytes');
        
        if (size > 0) {
          setState(() {
            _imageFile = imageFile;
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
  
  @override
  Widget build(BuildContext context) {
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
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (BuildContext context) {
                              return SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
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
                                      leading: const Icon(Icons.wifi_tethering),
                                      title: const Text('ESP32 Camera'),
                                      onTap: () {
                                        Navigator.pop(context);
                                        _captureFromESP32();
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
                                            child: Text(widget.profile!.name[0],
                                                style: TextStyle(fontSize: 50)),
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
                    if (widget.profile != null) ...[
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Profile'),
                              content: const Text('Are you sure you want to delete this profile?'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    Navigator.pop(context);
                                    setState(() {
                                      _isProcessing = true;
                                    });
                                    
                                    try {
                                      final success = await Provider.of<ProfileProvider>(context, listen: false)
                                          .deleteProfile(widget.profile!.id);
                                      
                                      if (success) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Profile deleted')),
                                        );
                                        Navigator.pop(context);
                                      }
                                    } finally {
                                      setState(() {
                                        _isProcessing = false;
                                      });
                                    }
                                  },
                                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('Delete Profile', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
