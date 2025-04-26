import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendance/providers/profile_provider.dart';
import 'package:attendance/screens/profile_detail_screen.dart';
import 'package:attendance/screens/profile_edit_screen.dart';

class ProfileListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<ProfileProvider>(
        builder: (context, profileProvider, _) {
          if (profileProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (profileProvider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Error: ${profileProvider.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => profileProvider.fetchProfiles(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }
          
          if (profileProvider.profiles.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('No profiles found'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ProfileEditScreen()),
                    ),
                    child: const Text('Add Profile'),
                  ),
                ],
              ),
            );
          }
          
          return RefreshIndicator(
            onRefresh: () => profileProvider.fetchProfiles(),
            child: ListView.builder(
              itemCount: profileProvider.profiles.length,
              itemBuilder: (context, index) {
                final profile = profileProvider.profiles[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: NetworkImage(profile.imageUrl),
                    onBackgroundImageError: (_, __) {},
                    child: profile.imageUrl.isEmpty ? Text(profile.name[0]) : null,
                  ),
                  title: Text(profile.name),
                  subtitle: Text(profile.email),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileEditScreen(profile: profile),
                        ),
                      );
                    },
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProfileDetailScreen(profile: profile),
                      ),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ProfileEditScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}