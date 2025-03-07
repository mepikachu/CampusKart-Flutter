import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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
  bool isLoading = true;
  String errorMessage = '';

  @override
  void initState() {
    super.initState();
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
          isLoading = false;
        });
      } else {
        throw Exception(responseBody['error'] ?? 'Failed to fetch user data');
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
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
      // If logout from backend fails, log the error but proceed locally.
      print("Backend logout error: $e");
    }

    // Clear the stored authCookie
    await _secureStorage.delete(key: 'authCookie');

    // Navigate to login screen and clear the navigation stack
    Navigator.pushNamedAndRemoveUntil(
      context,
      '/',
      (route) => false,
    );
  }

  String _formatAddress(Map<String, dynamic>? address) {
    if (address == null) return 'No address';
    return '${address['street']}, ${address['city']}, '
           '${address['state']}, ${address['zipCode']}';
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown';
    final date = DateTime.parse(dateString);
    return '${date.day}/${date.month}/${date.year}';
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
        // Add other section navigations here
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage.isNotEmpty) {
      return Center(child: Text('Error: $errorMessage'));
    }

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            const CircleAvatar(
              radius: 50,
              backgroundImage: NetworkImage('https://picsum.photos/200'),
            ),
            const SizedBox(height: 10),
            // Username (large text)
            Text(
              userData?['userName'] ?? 'No Name',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            // Email in light grey color
            Text(
              userData?['email'] ?? 'No Email',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600, // A subtle grey
              ),
            ),
            const SizedBox(height: 20),
            _buildInfoCard('Phone', userData?['phone'] ?? 'Not provided'),
            _buildInfoCard('Address', _formatAddress(userData?['address'])),
            _buildInfoCard(
                'Member Since', _formatDate(userData?['registrationDate'])),
            const SizedBox(height: 20),

            // Edit Profile button removed

            _buildSection('My Listings', Icons.list),
            _buildSection('My Purchases', Icons.shopping_bag),
            _buildSection('My Donations', Icons.volunteer_activism),
            _buildSection('Settings', Icons.settings),
            const SizedBox(height: 20),

            // Logout button: a TextButton with red text
            TextButton(
              onPressed: _logout,
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              child: const Text('Logout'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
