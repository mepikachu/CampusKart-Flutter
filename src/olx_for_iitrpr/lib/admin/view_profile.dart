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
import 'server.dart';
class AdminProfileView extends StatefulWidget {
  final String userId;

  const AdminProfileView({Key? key, required this.userId}) : super(key: key);

  @override
  State<AdminProfileView> createState() => _AdminProfileViewState();
}

class _AdminProfileViewState extends State<AdminProfileView> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();
  
  bool isAppBarCollapsed = false;
  double appBarHeight = 0.0;

  bool isLoading = true;
  bool isError = false;
  String errorMessage = '';
  Map<String, dynamic>? userData;
  Map<String, dynamic> userActivity = {
    'products': [],
    'purchasedProducts': [],
    'donations': [],
    'reportsFiled': {
      'user': [],
      'product': []
    },
    'reportsAgainst': []
  };
  
  // Flag to prevent reloading when coming back
  bool allDataFetched = false;
  
  // Cache for loaded images
  final Map<String, String> _loadedImages = {};

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
    
    // Listen to scroll events to determine when to collapse
    _scrollController.addListener(_onScroll);
  }
  
  void _onScroll() {
    final double offset = _scrollController.offset;
    // Get the height of the app bar to determine collapsed state
    final double threshold = 120.0; // Adjust based on your needs
    
    setState(() {
      isAppBarCollapsed = offset > threshold;
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserProfile() async {
    if (allDataFetched) return; // Don't fetch if already loaded
    
    setState(() {
      isLoading = true;
      isError = false;
    });

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');

      final response = await http.get(
        Uri.parse('$serverUrl/api/admin/users/${widget.userId}'),
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
              // Store all data from API
              userActivity['products'] = data['activity']['products'] ?? [];
              userActivity['purchasedProducts'] = data['activity']['purchasedProducts'] ?? [];
              userActivity['donations'] = data['activity']['donations'] ?? [];
              
              if (data['activity']['reportsFiled'] != null) {
                userActivity['reportsFiled']['user'] = data['activity']['reportsFiled']['user'] ?? [];
                userActivity['reportsFiled']['product'] = data['activity']['reportsFiled']['product'] ?? [];
              }
              
              userActivity['reportsAgainst'] = data['activity']['reportsAgainst'] ?? [];
            }
            
            isLoading = false;
            allDataFetched = true; // Mark as fetched to prevent reloading
          });

          if (userData != null && userData!['profilePicture'] != null) {
            _loadProfilePicture();
          }
          
          // Load all images in parallel
          await Future.wait([
            _loadProductImages(),
            _loadPurchasedProductImages(),
            _loadDonationImages()
          ]);
        } else {
          throw Exception(data['message'] ?? 'Failed to load user profile');
        }
      } else {
        throw Exception('Failed to load user profile. Status: ${response.statusCode}');
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
        Uri.parse('$serverUrl/api/users/profile-picture/${widget.userId}'),
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

  Future<void> _loadProductImages() async {
    final products = userActivity['products'] ?? [];
    if (products.isEmpty) return;

    final authCookie = await _secureStorage.read(key: 'authCookie');
    
    for (var product in products) {
      if (product['_id'] == null) continue;
      
      try {
        final response = await http.get(
          Uri.parse('$serverUrl/api/products/${product['_id']}/main_image'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie ?? '',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] && data['image'] != null && data['image']['data'] != null) {
            if (mounted) {
              setState(() {
                _loadedImages['product_${product['_id']}'] = data['image']['data'];
              });
            }
          }
        }
      } catch (e) {
        print('Error loading product image: $e');
      }
    }
  }

  Future<void> _loadPurchasedProductImages() async {
    final products = userActivity['purchasedProducts'] ?? [];
    if (products.isEmpty) return;

    final authCookie = await _secureStorage.read(key: 'authCookie');
    
    for (var product in products) {
      if (product['_id'] == null) continue;
      
      try {
        final response = await http.get(
          Uri.parse('$serverUrl/api/products/${product['_id']}/main_image'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie ?? '',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] && data['image'] != null && data['image']['data'] != null) {
            if (mounted) {
              setState(() {
                _loadedImages['purchased_${product['_id']}'] = data['image']['data'];
              });
            }
          }
        }
      } catch (e) {
        print('Error loading purchased product image: $e');
      }
    }
  }

  Future<void> _loadDonationImages() async {
    final donations = userActivity['donations'] ?? [];
    if (donations.isEmpty) return;

    final authCookie = await _secureStorage.read(key: 'authCookie');
    
    for (var donation in donations) {
      if (donation['_id'] == null) continue;
      
      try {
        final response = await http.get(
          Uri.parse('$serverUrl/api/donations/${donation['_id']}/main_image'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie ?? '',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] && data['image'] != null && data['image']['data'] != null) {
            if (mounted) {
              setState(() {
                _loadedImages['donation_${donation['_id']}'] = data['image']['data'];
              });
            }
          }
        }
      } catch (e) {
        print('Error loading donation image: $e');
      }
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

  Widget _buildItemPreview(Map<String, dynamic> item, String type, String idPrefix, Function onTap) {
    final String itemId = item['_id'];
    final String? imageData = _loadedImages['${idPrefix}_$itemId'];
    final String title = item['name'] ?? 'Unnamed ${type.capitalize()}';
    
    return GestureDetector(
      onTap: () => onTap(itemId),
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    // Always show shimmer background
                    Shimmer.fromColors(
                      baseColor: Colors.grey[300]!,
                      highlightColor: Colors.grey[100]!,
                      child: Container(
                        color: Colors.white,
                      ),
                    ),
                    // Show image if loaded
                    if (imageData != null)
                      Image.memory(
                        base64Decode(imageData),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        // Keep in memory to prevent disappearing on scroll
                        cacheWidth: 320, // Specify cache size
                        // In case of image error, show fallback
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Icon(
                              Icons.image_not_supported,
                              size: 40,
                              color: Colors.grey[400],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            // Show seller for purchased products
            if (type == 'purchased' && item['seller'] != null)
              Text(
                'Seller: ${item['seller']['userName'] ?? 'Unknown'}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBox(String title, List<Widget> children) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          SizedBox(height: 16),
          ...children,
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
  
  Widget _buildReportStatusBadge(String? status) {
    Color statusColor;
    switch (status?.toLowerCase()) {
      case 'pending':
        statusColor = Colors.orange;
        break;
      case 'resolved':
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.grey;
        break;
    }
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status?.toUpperCase() ?? 'UNKNOWN',
        style: TextStyle(
          color: statusColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
              : _buildUserProfileWithCollapsibleHeader(),
    );
  }
  
  Widget _buildUserProfileWithCollapsibleHeader() {
    if (userData == null) {
      return const Center(child: Text('No user data available'));
    }
    
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    final double appBarHeight = kToolbarHeight;
    
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Update collapsed status based on scroll
        final bool wasCollapsed = isAppBarCollapsed;
        if (notification.metrics.pixels > 140 && !isAppBarCollapsed) {
          setState(() {
            isAppBarCollapsed = true;
          });
        } else if (notification.metrics.pixels <= 140 && isAppBarCollapsed) {
          setState(() {
            isAppBarCollapsed = false;
          });
        }
        
        return false;
      },
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            backgroundColor: Colors.white,
            elevation: isAppBarCollapsed ? 4 : 0,
            // This ensures the back button stays visible
            leading: BackButton(color: Colors.black87),
            // Add the profile pic at right of the back button when collapsed
            title: AnimatedOpacity(
              duration: Duration(milliseconds: 200),
              opacity: isAppBarCollapsed ? 1.0 : 0.0,
              child: Row(
                children: [
                  // Only show small avatar when collapsed
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey[200],
                    backgroundImage: userData!['profilePictureData'] != null
                        ? MemoryImage(base64Decode(userData!['profilePictureData']))
                        : null,
                    child: userData!['profilePictureData'] == null
                        ? const Icon(Icons.person, size: 16, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      userData!['userName'] ?? 'Unknown User',
                      style: TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Center(
                child: AnimatedOpacity(
                  duration: Duration(milliseconds: 200),
                  opacity: isAppBarCollapsed ? 0.0 : 1.0,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: statusBarHeight + 20),
                      Hero(
                        tag: 'profile-${widget.userId}',
                        child: CircleAvatar(
                          radius: 50,
                          backgroundColor: Colors.grey[200],
                          backgroundImage: userData!['profilePictureData'] != null
                              ? MemoryImage(base64Decode(userData!['profilePictureData']))
                              : null,
                          child: userData!['profilePictureData'] == null
                              ? const Icon(Icons.person, size: 50, color: Colors.grey)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: AnimatedOpacity(
              duration: Duration(milliseconds: 200),
              opacity: isAppBarCollapsed ? 0.0 : 1.0,
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Text(
                    userData!['userName'] ?? 'Unknown User',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Center(
                    child: Container(
                      margin: EdgeInsets.only(top: 4),
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        userData!['role']?.toUpperCase() ?? 'USER',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Last seen: ${_formatTimeAgo(userData!['lastSeen'])}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                
                // User Info Box
                _buildInfoBox(
                  'User Information',
                  [
                    _buildDetailRow('Email', userData!['email'] ?? 'N/A'),
                    _buildDetailRow('User ID', widget.userId),
                    _buildDetailRow('Member since', _formatDate(userData!['registrationDate'])),
                    if (userData!['phone'] != null)
                      _buildDetailRow('Phone', userData!['phone']),
                  ],
                ),
                
                // Academic Info Box
                if (userData!['department'] != null || userData!['entryNumber'] != null)
                  _buildInfoBox(
                    'Academic Information',
                    [
                      if (userData!['department'] != null)
                        _buildDetailRow('Department', userData!['department']),
                      if (userData!['entryNumber'] != null)
                        _buildDetailRow('Entry Number', userData!['entryNumber']),
                    ],
                  ),
                
                // Products Section
                if ((userActivity['products'] as List).isNotEmpty) ...[
                  _buildSectionHeader('Products', _viewAllProducts),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: math.min((userActivity['products'] as List).length, 10),
                      itemBuilder: (context, index) => _buildItemPreview(
                        (userActivity['products'] as List)[index],
                        'product',
                        'product',
                        _navigateToProduct,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                
                // Purchased Products Section
                if ((userActivity['purchasedProducts'] as List).isNotEmpty) ...[
                  _buildSectionHeader('Purchased Products', () {}),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: math.min((userActivity['purchasedProducts'] as List).length, 10),
                      itemBuilder: (context, index) => _buildItemPreview(
                        (userActivity['purchasedProducts'] as List)[index],
                        'purchased',
                        'purchased',
                        _navigateToProduct,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                
                // Donations Section
                if ((userActivity['donations'] as List).isNotEmpty) ...[
                  _buildSectionHeader('Donations', _viewAllDonations),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: math.min((userActivity['donations'] as List).length, 10),
                      itemBuilder: (context, index) => _buildItemPreview(
                        (userActivity['donations'] as List)[index],
                        'donation',
                        'donation',
                        (id) => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AdminDonationView(donationId: id),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                
                // Reports Filed Section
                if ((userActivity['reportsFiled']['user'] as List).isNotEmpty || 
                    (userActivity['reportsFiled']['product'] as List).isNotEmpty) ...[
                  _buildInfoBox(
                    'Reports Filed',
                    [
                      ...(userActivity['reportsFiled']['user'] as List).map((report) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Against user: ${report['reportedUser']?['userName'] ?? 'Unknown'}'),
                          subtitle: Text(report['reason'] ?? 'No reason provided'),
                          trailing: _buildReportStatusBadge(report['status']),
                        ),
                      )).toList(),
                      
                      ...(userActivity['reportsFiled']['product'] as List).map((report) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('Against product: ${report['product']?['name'] ?? 'Unknown'}'),
                          subtitle: Text(report['reason'] ?? 'No reason provided'),
                          trailing: _buildReportStatusBadge(report['status']),
                        ),
                      )).toList(),
                    ],
                  ),
                ],
                
                // Reports Against User Section
                if ((userActivity['reportsAgainst'] as List).isNotEmpty) ...[
                  _buildInfoBox(
                    'Reports Against User',
                    [
                      ...(userActivity['reportsAgainst'] as List).map((report) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('From: ${report['reporter']?['userName'] ?? 'Unknown'}'),
                          subtitle: Text(report['reason'] ?? 'No reason provided'),
                          trailing: _buildReportStatusBadge(report['status']),
                        ),
                      )).toList(),
                    ],
                  ),
                ],
                
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}