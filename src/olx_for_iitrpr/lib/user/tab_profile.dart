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
import '../services/product_cache_service.dart';
import '../services/donation_cache_service.dart';
import '../services/lost_found_cache_service.dart';
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
      // First try to get user ID from secure storage
      final userId = await _secureStorage.read(key: 'userId');
      if (userId == null) {
        throw Exception('User ID not found');
      }

      // Try to get cached profile data
      final cachedProfile = ProfileService.getProfileData(userId);
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
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) {
        throw Exception('Not authenticated');
      }

      final response = await http.get(
        Uri.parse('$serverUrl/api/users/me'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Cache the complete response
          await ProfileService.cacheUserProfile(data);
          
          if (mounted) {
            setState(() {
              userData = data['user'];
              errorMessage = '';
            });
          }
          
          // Reload profile image if needed
          if (!isLoadingImage) {
            await _loadProfileImage();
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to load profile');
        }
      } else {
        throw Exception('Failed to load profile. Status: ${response.statusCode}');
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
    if (isLoadingImage || userData == null || userData!['_id'] == null) {
      return;
    }
    
    try {
      setState(() {
        isLoadingImage = true;
      });
      
      // Use user-specific key for image caching
      final userId = userData!['_id'];
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'profile_image_$userId';
      final timestampKey = 'profile_image_timestamp_$userId';
      
      // Check for cached image first
      final cachedImageStr = prefs.getString(cacheKey);
      
      if (cachedImageStr != null) {
        if (mounted) {
          setState(() {
            _profileImageBytes = base64Decode(cachedImageStr);
          });
        }
        
        // Check if the profile was updated recently
        final imageTimestamp = prefs.getString(timestampKey);
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
          
          // Cache in memory
          if (mounted) {
            setState(() {
              _profileImageBytes = imageBytes;
            });
          }
          
          // Save to shared preferences with user-specific keys
          await prefs.setString(cacheKey, data['image']['data']);
          await prefs.setString(timestampKey, DateTime.now().toIso8601String());
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
    final bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) => Theme(
        data: Theme.of(context).copyWith(
          dialogBackgroundColor: Colors.white,
        ),
        child: AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: Text('Logout', style: TextStyle(color: Colors.red[400])),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      ),
    ) ?? false;

    if (!confirm) return;

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final userId = await _secureStorage.read(key: 'userId');

      if (userId != null) {
        // Clear user-specific data
        await ProfileService.clearUserProfile(userId);
        
        // Clear user-specific image cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('profile_image_$userId');
        await prefs.remove('profile_image_timestamp_$userId');
      }

      // Clear all secure storage
      await _secureStorage.deleteAll();
      
      // Clear all cache services
      await ProductCacheService.clearAllCaches();
      await DonationCacheService.clearAllCaches();
      await LostFoundCacheService.clearAllCaches();

      // Clear notifications and chat data
      await _secureStorage.delete(key: 'notifications');
      await _secureStorage.delete(key: 'last_read_notification_time');
      await _secureStorage.delete(key: 'lastReadMessageIds');
      await _secureStorage.delete(key: 'conversations');
      
      // Delete all message caches
      final allKeys = await _secureStorage.readAll();
      for (String key in allKeys.keys) {
        if (key.startsWith('messages_') || 
            key.startsWith('last_message_id_') ||
            key.startsWith('profile_pic_')) {
          await _secureStorage.delete(key: key);
        }
      }

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }

      // Call server logout
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
      print('Logout error: $e');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
              fontSize: 14,
            )
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                height: 1.5,
                color: Colors.grey.shade900,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, IconData icon) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.black, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
        trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
        onTap: () {
          switch (title) {
            case 'Edit Profile':
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
              break;
            case 'My Listings':
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MyListingsScreen()),
              );
              break;
            case 'My Purchases':
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MyPurchasesPage()),
              );
              break;
            case 'My Donations':
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MyDonationsPage()),
              );
              break;
            case 'My Lost Items':
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MyLostItemsPage()),
              );
              break;
          }
        },
      ),
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
                    // Logout button at top of scrolling content
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: TextButton.icon(
                          onPressed: _logout,
                          icon: Icon(Icons.logout, color: Colors.red.shade400),
                          label: Text(
                            'Logout',
                            style: TextStyle(
                              color: Colors.red.shade400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Profile avatar
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey.shade200,
                      backgroundImage: userData?['profilePicture']?['data'] != null
                          ? MemoryImage(base64Decode(userData!['profilePicture']['data']))
                          : (_profileImageBytes != null
                              ? MemoryImage(_profileImageBytes!)
                              : null),
                      child: (userData?['profilePicture']?['data'] == null && 
                             _profileImageBytes == null)
                          ? const Icon(Icons.person, size: 50, color: Colors.grey)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      userData?['userName'] ?? 'User',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    Text(
                      userData?['email'] ?? '',
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Divider(),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoCard('Phone', userData?['phone'] ?? 'Not provided'),
                    _buildInfoCard('Address', _formatAddress(userData?['address'])),
                    _buildInfoCard('Member Since', _formatDate(userData?['registrationDate'])),
                    const SizedBox(height: 16),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Divider(),
                    ),
                    const SizedBox(height: 8),
                    // Add Edit Profile section at the top of the list
                    _buildSection('Edit Profile', Icons.edit),
                    _buildSection('My Listings', Icons.list),
                    _buildSection('My Purchases', Icons.shopping_bag),
                    _buildSection('My Donations', Icons.volunteer_activism),
                    _buildSection('My Lost Items', Icons.search),
                    const SizedBox(height: 20),
                    if (errorMessage.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          errorMessage,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    // Remove logout button from bottom
                  ],
                ),
        ),
      ),
    );
  }
}
