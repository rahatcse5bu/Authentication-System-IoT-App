import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendance/providers/auth_provider.dart';
import 'package:attendance/providers/settings_provider.dart';
import 'package:attendance/providers/profile_provider.dart';
import 'package:attendance/providers/attendance_provider.dart';
import 'package:attendance/screens/login_screen.dart';
import 'package:attendance/screens/dashboard_screen.dart';
import 'package:attendance/utils/app_theme.dart';
import 'package:attendance/services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize API service before running the app
  await ApiService.initialize();
  debugPrint('Main: API Service initialized');
  
  runApp(MyApp());
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
            darkTheme: AppTheme.darkTheme,
            themeMode: settingsProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: Consumer<AuthProvider>(
              builder: (context, authProvider, _) {
                return authProvider.isLoggedIn 
                    ? DashboardScreen() 
                    : LoginScreen();
              },
            ),
          );
        },
      ),
    );
  }
}