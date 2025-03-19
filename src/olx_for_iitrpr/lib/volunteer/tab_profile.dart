import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

class VolunteerProfileTab extends StatefulWidget {
  const VolunteerProfileTab({super.key});

  @override
  State<VolunteerProfileTab> createState() => _VolunteerProfileTabState();
}

class _VolunteerProfileTabState extends State<VolunteerProfileTab> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Map<String, dynamic>? userData;
  String errorMessage = '';
  bool isLoading = true;
  static const cacheDuration = Duration(minutes: 5);
  static const String cacheKey = 'volunteer_profile_cache';
  static const String cacheTimeKey = 'volunteer_profile_cache_time';

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
    // Store authCookie before clearing
    final authCookie = await _secureStorage.read(key: 'authCookie');
    
    // Clear local storage immediately
    await _secureStorage.delete(key: 'authCookie');
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // Navigate immediately
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        '/',
        (route) => false,
      );
    }

    // Make API call in the background after navigation
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
        // Error handling not needed as user is already logged out locally
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
        // Navigation logic for the sections
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
        // Pending approval banner placeholder
        _buildShimmerPlaceholder(height: 36, margin: EdgeInsets.zero),
        const SizedBox(height: 20),
        // Avatar placeholder - matches CircleAvatar size
        Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            width: 100,  // matches CircleAvatar diameter
            height: 100,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Username placeholder - matches text size
        _buildShimmerPlaceholder(
          height: 24,
          width: 150,
          margin: const EdgeInsets.symmetric(vertical: 4),
        ),
        // Email placeholder - matches text size
        _buildShimmerPlaceholder(
          height: 16,
          width: 200,
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
                  height: 50,  // matches actual card height
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
          child: Column(
            children: [
              // Loading profile or actual profile data
              isLoading
                  ? _buildLoadingProfile()
                  : Column(
                      children: [
                        const SizedBox(height: 20),
                        if (userData != null && userData!['role'] == 'volunteer_pending')
                          Container(
                            width: double.infinity,
                            color: Colors.orange,
                            padding: const EdgeInsets.all(8),
                            child: const Text(
                              'Your volunteer application is pending approval',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 10),
                        CircleAvatar(
                          radius: 50,
                          backgroundImage: userData != null &&
                                  userData!['profilePicture'] != null &&
                                  userData!['profilePicture']['data'] != null
                              ? MemoryImage(
                                  base64Decode(userData!['profilePicture']['data']),
                                )
                              : const AssetImage('assets/default_avatar.png')
                                  as ImageProvider,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          userData?['userName'] ?? '',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          userData?['email'] ?? '',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildInfoCard('Phone', userData?['phone'] ?? 'Not provided'),
                        _buildInfoCard(
                            'Address', _formatAddress(userData?['address'])),
                        _buildInfoCard('Member Since',
                            _formatDate(userData?['registrationDate'])),
                      ],
                    ),
              
              // Static sections that don't need loading state
              const SizedBox(height: 20),
              _buildSection('My Donation Collections', Icons.volunteer_activism),
              _buildSection('Settings', Icons.settings),
              const SizedBox(height: 20),
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