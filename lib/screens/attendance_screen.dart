import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendance/providers/attendance_provider.dart';
import 'package:attendance/providers/profile_provider.dart';
import 'package:intl/intl.dart';

class AttendanceScreen extends StatefulWidget {
  @override
  _AttendanceScreenState createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  
  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }
  
  void _loadAttendance() {
    final dateString = DateFormat('yyyy-MM-dd').format(_selectedDate);
    Provider.of<AttendanceProvider>(context, listen: false).fetchAttendance(date: dateString);
  }
  
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadAttendance();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            DateFormat('dd MMMM yyyy').format(_selectedDate),
                            style: const TextStyle(fontSize: 16),
                          ),
                          const Icon(Icons.calendar_today),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadAttendance,
                ),
              ],
            ),
          ),
          Expanded(
            child: Consumer<AttendanceProvider>(
              builder: (context, attendanceProvider, _) {
                if (attendanceProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (attendanceProvider.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Error: ${attendanceProvider.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadAttendance,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                
                final records = attendanceProvider.attendanceRecords;
                
                if (records.isEmpty) {
                  return const Center(
                    child: Text('No attendance records found for this date'),
                  );
                }
                
                return ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: ListTile(
                        title: Text(record.profileName),
                        subtitle: Text(
                          'Time In: ${DateFormat('HH:mm:ss').format(record.timeIn)}'
                          '${record.timeOut != null ? ' | Time Out: ${DateFormat('HH:mm:ss').format(record.timeOut!)}' : ''}',
                        ),
                        leading: CircleAvatar(
                          child: Text(record.profileName[0]),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Export attendance for the selected date
          // This would typically generate a PDF or CSV
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Exporting attendance data...')),
          );
        },
        child: const Icon(Icons.download),
        tooltip: 'Export Attendance',
      ),
    );
  }
}
