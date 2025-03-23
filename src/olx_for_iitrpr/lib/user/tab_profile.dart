import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'my_listings.dart';
import 'my_donations.dart';
import 'my_purchases.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Map<String, dynamic>? userData;
  String errorMessage = '';
  bool isLoading = true;
  static const cacheDuration = Duration(minutes: 5); // Time to live for cached data
  static const String cacheKey = 'user_profile_cache';
  static const String cacheTimeKey = 'user_profile_cache_time';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedData = prefs.getString(cacheKey);
    final cachedTime = prefs.getString(cacheTimeKey);

    if (cachedData != null && cachedTime != null) {
      final cacheDateTime = DateTime.parse(cachedTime);
      if (DateTime.now().difference(cacheDateTime) < cacheDuration) {
        setState(() {
          userData = json.decode(cachedData);
          isLoading = false;
        });
        return;
      }
    }
    await fetchUserData();
  }

  Future<void> fetchUserData() async {
    setState(() => isLoading = true);
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
        // Cache the data
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(cacheKey, json.encode(responseBody['user']));
        await prefs.setString(cacheTimeKey, DateTime.now().toIso8601String());

        setState(() {
          userData = responseBody['user'];
          errorMessage = '';
        });
      } else {
        throw Exception(responseBody['error'] ?? 'Failed to fetch user data');
      }
    } catch (e) {
      setState(() => errorMessage = e.toString());
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _logout() async {
    // First, clear local storage and navigate
    final authCookie = await _secureStorage.read(key: 'authCookie');
    await _secureStorage.delete(key: 'authCookie');
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/',
        (route) => false,
      );
    }

    // Then, make the API call in the background
    if (authCookie != null) {
      try {
        await http.post(
          Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/logout'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie,
          },
        );
      } catch (e) {
        print("Backend logout error: $e");
        // We don't need to handle this error as user is already logged out locally
      }
    }
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(height: 1.5),
              ),
            ),
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
            MaterialPageRoute(builder: (context) => const MyListingsScreen()),
          );
        } else if (title == 'My Purchases') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MyPurchasesPage()),
          );
        } else if (title == 'My Donations') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MyDonationsPage()),
          );
        } else if (title == 'Settings') {
          Navigator.pushNamed(context, '/settings');
        }
      },
    );
  }

  Widget _buildShimmerPlaceholder({
    required double height,
    double? width,
    EdgeInsets margin = const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
  }) {
    return Container(
      margin: margin,
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingProfile() {
    return Column(
      children: [
        const SizedBox(height: 20),
        // Avatar placeholder
        Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Username placeholder
        _buildShimmerPlaceholder(
          height: 24,
          width: 120,
          margin: const EdgeInsets.symmetric(vertical: 4),
        ),
        // Email placeholder
        _buildShimmerPlaceholder(
          height: 16,
          width: 180,
          margin: const EdgeInsets.symmetric(vertical: 4),
        ),
        const SizedBox(height: 20),
        // Info cards placeholders
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Column(
              children: [
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Static sections without shimmer
        _buildSection('My Listings', Icons.list),
        _buildSection('My Purchases', Icons.shopping_bag),
        _buildSection('My Donations', Icons.volunteer_activism),
        _buildSection('Settings', Icons.settings),
        const SizedBox(height: 20),
        // Static logout button without shimmer
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: fetchUserData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: isLoading
              ? _buildLoadingProfile()
              : Column(
                  children: [
                    const SizedBox(height: 20),
                    // Profile picture - Modified to match view_profile.dart
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: userData != null &&
                              userData!['profilePicture'] != null &&
                              userData!['profilePicture']['data'] != null
                          ? MemoryImage(
                              base64Decode(userData!['profilePicture']['data']),
                            )
                          : null,
                      child: (userData == null || userData!['profilePicture'] == null || 
                              userData!['profilePicture']['data'] == null)
                          ? const Icon(Icons.person, size: 50, color: Colors.grey)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    // Username
                    Text(
                      userData?['userName'] ?? '',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // Email
                    Text(
                      userData?['email'] ?? '',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Info cards
                    _buildInfoCard('Phone', userData?['phone'] ?? 'Not provided'),
                    _buildInfoCard(
                        'Address', _formatAddress(userData?['address'])),
                    _buildInfoCard('Member Since',
                        _formatDate(userData?['registrationDate'])),
                    const SizedBox(height: 20),
                    // Sections
                    _buildSection('My Listings', Icons.list),
                    _buildSection('My Purchases', Icons.shopping_bag),
                    _buildSection('My Donations', Icons.volunteer_activism),
                    _buildSection('Settings', Icons.settings),
                    const SizedBox(height: 20),
                    // Logout button
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
      ),
    );
  }
}
