import 'package:flutter/material.dart';
import 'package:attendance/models/profile.dart';
import 'package:attendance/providers/attendance_provider.dart';
import 'package:attendance/screens/profile_edit_screen.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class ProfileDetailScreen extends StatefulWidget {
  final Profile profile;
  
  const ProfileDetailScreen({Key? key, required this.profile}) : super(key: key);
  
  @override
  _ProfileDetailScreenState createState() => _ProfileDetailScreenState();
}

class _ProfileDetailScreenState extends State<ProfileDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => Provider.of<AttendanceProvider>(context, listen: false)
        .fetchAttendance(profileId: widget.profile.id));
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profile.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProfileEditScreen(profile: widget.profile),
                ),
              ).then((_) {
                // Refresh data when returning from edit screen
                setState(() {});
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: NetworkImage(widget.profile.imageUrl),
                    onBackgroundImageError: (_, __) {},
                    child: widget.profile.imageUrl.isEmpty
                        ? Text(
                            widget.profile.name[0],
                            style: const TextStyle(fontSize: 50),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.profile.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.profile.email,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Profile Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(),
                      _buildDetailRow('Registration Number', widget.profile.regNumber),
                      _buildDetailRow('University', widget.profile.university),
                      _buildDetailRow('Blood Group', widget.profile.bloodGroup),
                      _buildDetailRow(
                        'Registration Date',
                        DateFormat('dd MMM yyyy').format(widget.profile.registrationDate),
                      ),
                      _buildDetailRow(
                        'Status',
                        widget.profile.isActive ? 'Active' : 'Inactive',
                        valueColor: widget.profile.isActive ? Colors.green : Colors.red,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Recent Attendance',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Divider(),
                      Consumer<AttendanceProvider>(
                        builder: (context, attendanceProvider, _) {
                          if (attendanceProvider.isLoading) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(),
                              ),
                            );
                          }
                          
                          if (attendanceProvider.error != null) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text('Error: ${attendanceProvider.error}'),
                              ),
                            );
                          }
                          
                          final records = attendanceProvider.attendanceRecords;
                          
                          if (records.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Center(
                                child: Text('No attendance records found'),
                              ),
                            );
                          }
                          
                          return ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: records.length > 5 ? 5 : records.length,
                            itemBuilder: (context, index) {
                              final record = records[index];
                              return ListTile(
                                title: Text(DateFormat('dd MMM yyyy').format(record.date)),
                                subtitle: Text(
                                  'Time In: ${DateFormat('HH:mm:ss').format(record.timeIn)}'
                                  '${record.timeOut != null ? ' | Time Out: ${DateFormat('HH:mm:ss').format(record.timeOut!)}' : ''}',
                                ),
                                leading: const Icon(Icons.check_circle, color: Colors.green),
                              );
                            },
                          );
                        },
                      ),
                      TextButton(
                        onPressed: () {
                          // Navigate to full attendance history for this profile
                        },
                        child: const Text('View Full History'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}