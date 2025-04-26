import 'package:flutter/foundation.dart';
import 'package:attendance/models/attendance.dart';
import 'package:attendance/services/api_service.dart';

class AttendanceProvider with ChangeNotifier {
  List<Attendance> _attendanceRecords = [];
  bool _isLoading = false;
  String? _error;
  bool _isScanning = false;
  
  List<Attendance> get attendanceRecords => _attendanceRecords;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isScanning => _isScanning;
  
  Future<void> fetchAttendance({String? date, String? profileId}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _attendanceRecords = await ApiService.getAttendance(date: date, profileId: profileId);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _error = e.toString();
      notifyListeners();
    }
  }
  
  Future<bool> markAttendance(String profileId) async {
    try {
      final attendance = await ApiService.markAttendance(profileId);
      _attendanceRecords.add(attendance);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }
  
  void startScanning() {
    _isScanning = true;
    notifyListeners();
  }
  
  void stopScanning() {
    _isScanning = false;
    notifyListeners();
  }
}