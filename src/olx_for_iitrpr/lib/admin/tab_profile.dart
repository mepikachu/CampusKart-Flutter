import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'server.dart';

class AdminProfileTab extends StatefulWidget {
  const AdminProfileTab({super.key});

  @override
  State createState() => _AdminProfileTabState();
}

class _AdminProfileTabState extends State<AdminProfileTab> {
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

  Future<void> _loadUserData() async {
    if (mounted) {
      setState(() => isLoading = true);
    }

    try {
      // Try to load from cache first
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('admin_profile');
      if (cachedData != null) {
        if (mounted) {
          setState(() {
            userData = json.decode(cachedData);
            isLoading = false;
          });
        }
        await _loadProfileImage();
      }

      // Fetch fresh data from server
      await _fetchUserData();
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'Error: ${e.toString()}';
          isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchUserData() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) throw Exception('Not authenticated');

      final response = await http.get(
        Uri.parse('$serverUrl/api/me'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Cache the data
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('admin_profile', json.encode(data['user']));

          if (mounted) {
            setState(() {
              userData = data['user'];
              errorMessage = '';
            });
          }

          // Load profile image if needed
          if (!isLoadingImage) {
            await _loadProfileImage();
          }
        }
      }
    } catch (e) {
      print('Error fetching user data: $e');
      if (mounted) {
        setState(() {
          errorMessage = e.toString();
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
      final cachedImageStr = prefs.getString('admin_profile_image');

      if (cachedImageStr != null) {
        if (mounted) {
          setState(() {
            _profileImageBytes = base64Decode(cachedImageStr);
          });
        }
      }

      // Fetch fresh image from server
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

          if (mounted) {
            setState(() {
              _profileImageBytes = imageBytes;
            });
          }

          // Cache the image
          await prefs.setString('admin_profile_image', data['image']['data']);
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

  Future<void> _logout() async {
    // Show confirmation dialog
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

      // Clear all storage
      await _secureStorage.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/login',
          (route) => false,
        );
      }

      // Logout from server
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
            width: 100,  // matches CircleAvatar diameter
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
          width: 150,
          margin: const EdgeInsets.symmetric(vertical: 4),
        ),
        // Email placeholder
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

  Widget _buildLoadingShimmer() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Avatar placeholder
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
          // Username placeholder
          _buildShimmerPlaceholder(
            height: 24,
            width: 150,
            margin: const EdgeInsets.symmetric(vertical: 4),
          ),
          // Email placeholder
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
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildErrorDisplay() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'An error occurred',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() {
                isLoading = true;
                errorMessage = '';
              });
              _loadUserData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.light(
          primary: Colors.black,
          secondary: const Color(0xFF4CAF50),
          background: Colors.white,
          surface: Colors.white,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            TextButton.icon(
              onPressed: _logout,
              icon: Icon(Icons.logout, color: Colors.red[400], size: 20),
              label: Text(
                'Logout',
                style: TextStyle(
                  color: Colors.red[400],
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: isLoading
          ? _buildLoadingShimmer()
          : errorMessage.isNotEmpty
            ? _buildErrorDisplay()
            : RefreshIndicator(
                color: Colors.black,
                onRefresh: _loadUserData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      // Profile header section with image and name
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            // Profile Image
                            CircleAvatar(
                              radius: 50,
                              backgroundColor: Colors.grey[200],
                              backgroundImage: _profileImageBytes != null
                                ? MemoryImage(_profileImageBytes!)
                                : null,
                              child: _profileImageBytes == null
                                ? const Icon(Icons.person, size: 50, color: Colors.grey)
                                : null,
                            ),
                            const SizedBox(height: 16),
                            
                            // Username
                            Text(
                              userData?['userName'] ?? 'Username',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            
                            // Email
                            Text(
                              userData?['email'] ?? 'Email',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Centered divider with specific width
                      Center(
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.9,
                          height: 1,
                          color: Colors.grey[200],
                        ),
                      ),

                      // Info sections in a box
                      Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade100,
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Phone',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                Text(
                                  userData?['phone'] ?? 'Not provided',
                                  style: const TextStyle(
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Divider(),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Address',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    _formatAddress(userData?['address']),
                                    style: const TextStyle(
                                      fontSize: 16,
                                    ),
                                    textAlign: TextAlign.end,
                                  ),
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Divider(),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Member Since',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                Text(
                                  _formatDate(userData?['createdAt']),
                                  style: const TextStyle(
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}