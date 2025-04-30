import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:attendance/providers/auth_provider.dart';
import 'package:attendance/providers/settings_provider.dart';
import 'package:attendance/providers/profile_provider.dart';
import 'package:attendance/providers/attendance_provider.dart';
import 'package:attendance/screens/login_screen.dart';
import 'package:attendance/screens/dashboard_screen.dart';
import 'package:attendance/screens/settings_screen.dart';
import 'package:attendance/screens/profile_list_screen.dart';
import 'package:attendance/screens/scan_screen.dart';
import 'package:attendance/utils/app_theme.dart';
import 'package:attendance/services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize ML Kit
  try {
    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,
        enableLandmarks: true,
        enableTracking: true,
        minFaceSize: 0.1,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    // Test the detector to ensure it's properly initialized
    await faceDetector.close();
  } catch (e) {
    print('Error initializing ML Kit: $e');
  }
  
  // Initialize API Service
  await ApiService.initialize();
  
  // Request permissions at app startup (optional)
  await requestInitialPermissions();
  
  runApp(MyApp());
}

Future<void> requestInitialPermissions() async {
  try {
    // Request permissions at app startup
    await [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
    ].request();
  } catch (e) {
    print('Error requesting permissions: $e');
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => AttendanceProvider()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, _) {
          return MaterialApp(
            title: 'Attendance System',
            theme: AppTheme.lightTheme,
            debugShowCheckedModeBanner: false,
            darkTheme: AppTheme.darkTheme,
            themeMode: settingsProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: Consumer<AuthProvider>(
              builder: (context, authProvider, _) {
                return authProvider.isLoggedIn 
                    ? DashboardScreen() 
                    : LoginScreen();
              },
            ),
            routes: {
              '/settings': (context) =>  SettingsScreen(),
              '/profiles': (context) =>  ProfileListScreen(),
              '/scan': (context) => ScanScreen(),
            },
          );
        },
      ),
    );
  }
}