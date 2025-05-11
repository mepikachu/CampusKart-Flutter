import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'my_listings.dart';
import 'my_donations.dart';
import 'my_purchases.dart';
import 'my_lost_items.dart';
import 'edit_profile_screen.dart';
import '../services/profile_service.dart';
import 'server.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Map<String, dynamic>? userData;
  String errorMessage = '';
  bool isLoading = true;
  bool isLoadingImage = false;
  Uint8List? _profileImageBytes;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  /// Load user profile data with caching strategy
  Future<void> _loadUserData() async {
    if (mounted) {
      setState(() => isLoading = true);
    }
    
    try {
      // First try to get cached profile data
      final cachedProfile = ProfileService.profileData;
      if (cachedProfile != null) {
        if (mounted) {
          setState(() {
            userData = cachedProfile;
            isLoading = false;
          });
        }
        await _loadProfileImage();
      }
      
      // Fetch fresh data from server in the background
      final success = await ProfileService.fetchAndUpdateProfile();
      
      if (success && mounted) {
        setState(() {
          userData = ProfileService.profileData;
          errorMessage = '';
        });
        
        // Reload profile image if needed
        if (!isLoadingImage) {
          await _loadProfileImage();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'Error: ${e.toString()}';
          isLoading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// Load and cache the user's profile image
  Future<void> _loadProfileImage() async {
    if (isLoadingImage || userData == null || userData!['profilePicture'] == null) {
      return;
    }
    
    try {
      setState(() {
        isLoadingImage = true;
      });
      
      // Check for cached image first
      final prefs = await SharedPreferences.getInstance();
      final cachedImageStr = prefs.getString('profile_image');
      
      if (cachedImageStr != null) {
        if (mounted) {
          setState(() {
            _profileImageBytes = base64Decode(cachedImageStr);
          });
        }
        
        // Check if the profile was updated recently
        final imageTimestamp = prefs.getString('profile_image_timestamp');
        if (imageTimestamp != null) {
          final lastUpdate = DateTime.parse(imageTimestamp);
          if (DateTime.now().difference(lastUpdate) <= const Duration(hours: 1)) {
            setState(() {
              isLoadingImage = false;
            });
            return; // Use cached image if it's recent
          }
        }
      }
      
      // Fetch from server if no cache or cache is old
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/users/me/profile-picture'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['image'] != null) {
          final imageBytes = base64Decode(data['image']['data']);
          
          // Cache in memory and storage
          if (mounted) {
            setState(() {
              _profileImageBytes = imageBytes;
            });
          }
          
          // Save to shared preferences
          await prefs.setString('profile_image', data['image']['data']);
          await prefs.setString('profile_image_timestamp', DateTime.now().toIso8601String());
        }
      }
    } catch (e) {
      print('Error loading profile image: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoadingImage = false;
        });
      }
    }
  }

  /// Handle user logout
  Future<void> _logout() async {
    try {
      // First, clear local storage and navigate
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // Clear all caches
      await ProfileService.clearProfile();
      await _secureStorage.delete(key: 'authCookie');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      
      if (mounted) {
        setState(() {
          userData = null;
          errorMessage = '';
          _profileImageBytes = null;
        });
        
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/login',
          (route) => false,
        );
      }

      // Then, make the API call in the background
      if (authCookie != null) {
        await http.post(
          Uri.parse('$serverUrl/api/logout'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie,
          },
        );
      }
    } catch (e) {
      print("Logout error: $e");
    }
  }

  String _formatAddress(Map<String, dynamic>? address) {
    if (address == null) return 'No address';
    return '${address['street'] ?? ''}, ${address['city'] ?? ''}, ${address['state'] ?? ''}, ${address['zipCode'] ?? ''}';
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
      elevation: 2,
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
        } else if (title == 'My Lost Items') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MyLostItemsPage()),
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
        // Static sections
        _buildSection('My Listings', Icons.list),
        _buildSection('My Purchases', Icons.shopping_bag),
        _buildSection('My Donations', Icons.volunteer_activism),
        _buildSection('My Lost Items', Icons.search),
        _buildSection('Settings', Icons.settings),
        const SizedBox(height: 20),
        // Static logout button
        TextButton(
          onPressed: null,  // Disabled while loading
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
      backgroundColor: Colors.white,
      body: RefreshIndicator(
        color: Colors.black,
        onRefresh: _loadUserData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: isLoading
              ? _buildLoadingProfile()
              : Column(
                  children: [
                    const SizedBox(height: 20),
                    // Profile picture
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: _profileImageBytes != null
                          ? MemoryImage(_profileImageBytes!)
                          : null,
                      child: _profileImageBytes == null
                          ? const Icon(Icons.person, size: 50, color: Colors.grey)
                          : isLoadingImage 
                              ? const CircularProgressIndicator()
                              : null,
                    ),
                    const SizedBox(height: 8),
                    // Edit Profile Button
                    TextButton.icon(
                      onPressed: () {
                        if (userData != null) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditProfileScreen(
                                userData: userData!,
                                onProfileUpdated: () => _loadUserData(),
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit Profile'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue,
                        textStyle: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Username
                    Text(
                      userData?['userName'] ?? 'User',
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
                    _buildInfoCard('Address', _formatAddress(userData?['address'])),
                    _buildInfoCard('Member Since', _formatDate(userData?['registrationDate'])),
                    const SizedBox(height: 20),
                    // Sections
                    _buildSection('My Listings', Icons.list),
                    _buildSection('My Purchases', Icons.shopping_bag),
                    _buildSection('My Donations', Icons.volunteer_activism),
                    _buildSection('My Lost Items', Icons.search),
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
                          errorMessage,
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
