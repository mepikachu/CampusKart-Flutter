import 'package:flutter/material.dart';

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
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
            const Text(
              'John Doe',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const Text(
              'john.doe@example.com',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            _buildInfoCard('Phone', '+1 234 567 890'),
            _buildInfoCard('Address', '123 Main St, City, Country'),
            _buildInfoCard('Member Since', 'January 1, 2023'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Add edit profile functionality
              },
              child: const Text('Edit Profile'),
            ),
            const SizedBox(height: 20),
            _buildSection('My Listings', Icons.list),
            _buildSection('My Purchases', Icons.shopping_bag),
            _buildSection('My Donations', Icons.volunteer_activism),
            _buildSection('Settings', Icons.settings),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Add logout functionality
                Navigator.pushReplacementNamed(context, '/');
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Logout'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, String value) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
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
        // Add navigation to respective sections
      },
    );
  }
}
