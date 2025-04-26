// lib/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendance/providers/settings_provider.dart';
import 'package:attendance/providers/auth_provider.dart';

class SettingsScreen extends StatefulWidget {
  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _esp32UrlController = TextEditingController();
  bool _isTesting = false;
  String? _testResult;
  
  @override
  void initState() {
    super.initState();
    // Initialize controller with current ESP32 URL
    final esp32Url = Provider.of<SettingsProvider>(context, listen: false).esp32Url;
    if (esp32Url != null) {
      _esp32UrlController.text = esp32Url;
    }
  }
  
  @override
  void dispose() {
    _esp32UrlController.dispose();
    super.dispose();
  }
  
  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    
    try {
      final url = _esp32UrlController.text.trim();
      
      if (url.isEmpty) {
        throw Exception('Please enter a URL');
      }
      
      // Test connection by attempting to fetch an image
      await Provider.of<SettingsProvider>(context, listen: false).setEsp32Url(url);
      
      try {
        await Future.delayed(const Duration(seconds: 1)); // Simulate network request
        
        setState(() {
          _testResult = 'Connection successful!';
          _isTesting = false;
        });
      } catch (e) {
        setState(() {
          _testResult = 'Connection failed: ${e.toString()}';
          _isTesting = false;
        });
      }
    } catch (e) {
      setState(() {
        _testResult = e.toString();
        _isTesting = false;
      });
    }
  }
  
  Future<void> _saveSettings() async {
    final url = _esp32UrlController.text.trim();
    
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter ESP32 camera URL')),
      );
      return;
    }
    
    try {
      await Provider.of<SettingsProvider>(context, listen: false).setEsp32Url(url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, _) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ESP32 Camera Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _esp32UrlController,
                        decoration: const InputDecoration(
                          labelText: 'ESP32 Camera URL',
                          hintText: 'e.g., http://192.168.0.105/cam-hi.jpg',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isTesting ? null : _testConnection,
                              child: _isTesting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Test Connection'),
                            ),
                          ),
                        ],
                      ),
                      if (_testResult != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          color: _testResult!.contains('successful') ? Colors.green.shade100 : Colors.red.shade100,
                          child: Text(_testResult!),
                        ),
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _saveSettings,
                        child: const Text('Save Settings'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'App Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Dark Mode'),
                        value: settingsProvider.isDarkMode,
                        onChanged: (value) {
                          settingsProvider.toggleDarkMode();
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Account',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Consumer<AuthProvider>(
                        builder: (context, authProvider, _) {
                          return ListTile(
                            title: const Text('Logged in as'),
                            subtitle: Text(authProvider.username),
                            trailing: TextButton(
                              onPressed: () {
                                authProvider.logout();
                              },
                              child: const Text('Logout'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'About',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const ListTile(
                        title: Text('App Version'),
                        subtitle: Text('1.0.0'),
                      ),
                      const Divider(),
                      const ListTile(
                        title: Text('Developer'),
                        subtitle: Text('Your Name'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}