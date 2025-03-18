import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'my_listings_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Map<String, dynamic>? userData;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
    // Display UI immediately with placeholders then update when data is fetched.
    fetchUserData();
  }

  Future<void> fetchUserData() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) {
        throw Exception('Not authenticated');
      }

      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/me'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      final responseBody = json.decode(response.body);
      if (response.statusCode == 200 && responseBody['success'] == true) {
        setState(() {
          userData = responseBody['user'];
        });
      } else {
        throw Exception(responseBody['error'] ?? 'Failed to fetch user data');
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
      });
    }
  }

  Future<void> _logout() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie != null) {
        await http.post(
          Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/logout'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie,
          },
        );
      }
    } catch (e) {
      print("Backend logout error: $e");
    }
    await _secureStorage.delete(key: 'authCookie');
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/',
      (route) => false,
    );
  }

  String _formatAddress(Map<String, dynamic>? address) {
    if (address == null) return 'No address';
    return '${address['street']}, ${address['city']}, ${address['state']}, ${address['zipCode']}';
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return 'Unknown';
    }
  }

  Widget _buildInfoCard(String title, String value) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(value),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.arrow_forward_ios),
      onTap: () {
        if (title == 'My Listings') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const MyListingsScreen(),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Build UI using the same default image if no profilePicture is returned.
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 50,
              backgroundImage: userData != null &&
                      userData!['profilePicture'] != null &&
                      userData!['profilePicture']['data'] != null
                  ? MemoryImage(
                      base64Decode(userData!['profilePicture']['data']),
                    )
                  : const AssetImage('assets/default_avatar.png') as ImageProvider,
            ),
            const SizedBox(height: 10),
            Text(
              userData?['userName'] ?? 'Loading...',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              userData?['email'] ?? 'Loading...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 20),
            _buildInfoCard('Phone', userData?['phone'] ?? 'Not provided'),
            _buildInfoCard('Address', _formatAddress(userData?['address'])),
            _buildInfoCard('Member Since', _formatDate(userData?['registrationDate'])),
            const SizedBox(height: 20),
            _buildSection('My Listings', Icons.list),
            _buildSection('My Purchases', Icons.shopping_bag),
            _buildSection('My Donations', Icons.volunteer_activism),
            _buildSection('Settings', Icons.settings),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _logout,
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              child: const Text('Logout'),
            ),
            const SizedBox(height: 20),
            if (errorMessage.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: $errorMessage',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
