import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendance/providers/auth_provider.dart';
import 'package:attendance/providers/profile_provider.dart';
import 'package:attendance/screens/profile_list_screen.dart';
import 'package:attendance/screens/attendance_screen.dart';
import 'package:attendance/screens/scan_screen.dart';
import 'package:attendance/screens/settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  
  final List<Widget> _screens = [
    ProfileListScreen(),
    AttendanceScreen(),
    ScanScreen(),
    SettingsScreen(),
  ];
  
  @override
  void initState() {
    super.initState();
    // Load profiles when dashboard is initialized
    Future.microtask(() => 
      Provider.of<ProfileProvider>(context, listen: false).fetchProfiles()
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance System'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Provider.of<AuthProvider>(context, listen: false).logout();
            },
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: 'Profiles',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.checklist),
            label: 'Attendance',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.camera),
            label: 'Scan',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}