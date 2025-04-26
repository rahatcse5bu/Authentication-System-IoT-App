import 'dart:io';

class Constants {
  // API URLs
  // For Android emulator, 10.0.2.2 points to the host machine's localhost
  // For iOS simulator, localhost works
  // For physical devices, you'd need the actual IP of your computer on the network
  static String get baseApiUrl {
    if (Platform.isAndroid) {
      // Android emulator uses 10.0.2.2 to access host machine's localhost
      return 'http://10.0.2.2:8000/api';
    } else {
      // iOS or other platforms
      return 'http://127.0.0.1:8000/api';
    }
  }
} 