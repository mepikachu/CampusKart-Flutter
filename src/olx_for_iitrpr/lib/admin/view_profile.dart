import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'view_product.dart';
import 'view_donation.dart';
import 'view_user_items.dart';
import 'package:shimmer/shimmer.dart';

class AdminProfileView extends StatefulWidget {
  final String userId;

  const AdminProfileView({Key? key, required this.userId}) : super(key: key);

  @override
  State<AdminProfileView> createState() => _AdminProfileViewState();
}

class _AdminProfileViewState extends State<AdminProfileView> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  bool isLoading = true;
  bool isError = false;
  String errorMessage = '';
  Map<String, dynamic>? userData;
  Map<String, List<dynamic>> userActivity = {
    'products': [],
    'donations': []
  };

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  Future<void> _fetchUserProfile() async {
    setState(() {
      isLoading = true;
      isError = false;
    });

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');

      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/users/${widget.userId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            userData = data['user'];
            if (data['activity'] != null) {
              userActivity['products'] = data['activity']['products'] ?? [];
              userActivity['donations'] = data['activity']['donations'] ?? [];
            }
            isLoading = false;
          });

          if (userData != null && userData!['profilePicture'] != null) {
            _loadProfilePicture();
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to load user profile');
        }
      }
    } catch (e) {
      setState(() {
        isError = true;
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _loadProfilePicture() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/users/profile-picture/${widget.userId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        if (response.headers['content-type']?.contains('application/json') != true) {
          if (mounted) {
            setState(() {
              if (userData != null) {
                userData!['profilePictureData'] = base64Encode(response.bodyBytes);
              }
            });
          }
        }
      }
    } catch (e) {
      print('Error loading profile picture: $e');
    }
  }

  void _navigateToProduct(String productId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminProductView(productId: productId),
      ),
    );
  }

  void _viewAllProducts() {
    if (userData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserItemsView(
          userId: widget.userId,
          type: 'products',
          userName: userData!['userName'] ?? 'User',
        ),
      ),
    );
  }

  void _viewAllDonations() {
    if (userData == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserItemsView(
          userId: widget.userId,
          type: 'donations',
          userName: userData!['userName'] ?? 'User',
        ),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatTimeAgo(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return DateFormat('h:mm a').format(date);
      } else if (difference.inDays == 1) {
        return 'Yesterday ${DateFormat('h:mm a').format(date)}';
      } else if (difference.inDays < 7) {
        return '${DateFormat('EEEE').format(date)} ${DateFormat('h:mm a').format(date)}';
      } else {
        return DateFormat('MMM d, y h:mm a').format(date);
      }
    } catch (e) {
      return dateString;
    }
  }

  Widget _buildProductPreview(Map<String, dynamic> product) {
    return GestureDetector(
      onTap: () => _navigateToProduct(product['_id']),
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (product['images']?.isNotEmpty ?? false)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: Stack(
                    children: [
                      Shimmer.fromColors(
                        baseColor: Colors.grey[300]!,
                        highlightColor: Colors.grey[100]!,
                        child: Container(
                          color: Colors.white,
                        ),
                      ),
                      Image.memory(
                        base64Decode(product['images'][0]['data']),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              product['name'] ?? 'Unnamed Product',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserProfile() {
    if (userData == null) {
      return const Center(child: Text('No user data available'));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: userData!['profilePictureData'] != null
                      ? MemoryImage(base64Decode(userData!['profilePictureData']))
                      : null,
                  child: userData!['profilePictureData'] == null
                      ? const Icon(Icons.person, size: 50, color: Colors.grey)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userData!['userName'] ?? 'Unknown User',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userData!['email'] ?? '',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Role', userData!['role']?.toUpperCase() ?? 'USER'),
                _buildDetailRow('User ID', widget.userId),
                _buildDetailRow('Member since', _formatDate(userData!['registrationDate'])),
                _buildDetailRow('Last seen', _formatTimeAgo(userData!['lastSeen'])),
                if (userData!['phone'] != null)
                  _buildDetailRow('Phone', userData!['phone']),
                if (userData!['department'] != null)
                  _buildDetailRow('Department', userData!['department']),
                if (userData!['entryNumber'] != null)
                  _buildDetailRow('Entry Number', userData!['entryNumber']),
              ],
            ),
          ),
          if ((userActivity['products'] ?? []).isNotEmpty) ...[
            _buildSectionHeader('Products', _viewAllProducts),
            SizedBox(
              height: 200,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: math.min(userActivity['products']!.length, 10),
                itemBuilder: (context, index) => _buildProductPreview(userActivity['products']![index]),
              ),
            ),
            const SizedBox(height: 24),
          ],
          if ((userActivity['donations'] ?? []).isNotEmpty) ...[
            _buildSectionHeader('Donations', _viewAllDonations),
            SizedBox(
              height: 200,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: math.min(userActivity['donations']!.length, 10),
                itemBuilder: (context, index) => _buildProductPreview(userActivity['donations']![index]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback onViewAll) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextButton(
            onPressed: onViewAll,
            child: const Text('View All'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(userData != null ? userData!['userName'] ?? 'User Profile' : 'User Profile'),
        elevation: 2,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : isError
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(errorMessage, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _fetchUserProfile,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _buildUserProfile(),
    );
  }
}
