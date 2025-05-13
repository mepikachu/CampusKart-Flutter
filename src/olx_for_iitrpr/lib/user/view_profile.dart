import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

import 'product_description.dart';
import 'lost_item_description.dart';

import 'chat_screen.dart';
import 'home.dart';
import 'server.dart';
import 'report_user.dart';

class ViewProfileScreen extends StatefulWidget {
  final String userId;
  
  const ViewProfileScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  bool isLoading = true;
  bool isError = false;
  String errorMessage = '';
  Map<String, dynamic>? userData;
  Map<String, dynamic> userActivity = {
    'products': [],
    'donations': [],
    'lost_items': [],
  };
  String currentUserId = '';
  bool allDataFetched = false;

  // Add cache map for images
  final Map<String, String> _loadedImages = {};
  final ScrollController _scrollController = ScrollController();
  bool isAppBarCollapsed = false;
  bool isBlocked = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadCurrentUserInfo().then((_) {
      // Check if viewing own profile, redirect to tab_profile if so
      if (currentUserId == widget.userId) {
        // Navigate to tab_profile and remove this screen from stack
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pop(context);
          UserHomeScreen.homeKey.currentState?.switchToTab(1);
        });
      } else {
        _fetchUserProfile();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final double offset = _scrollController.offset;
    final bool collapsed = offset > 120;
    if (collapsed != isAppBarCollapsed) {
      setState(() {
        isAppBarCollapsed = collapsed;
      });
    }
  }

  Future<void> _loadCurrentUserInfo() async {
    try {
      final userId = await _secureStorage.read(key: 'userId');
      if (userId != null) {
        setState(() {
          currentUserId = userId;
        });
      }
    } catch (e) {
      print('Error loading user info: $e');
    }
  }

  Future<void> _fetchUserProfile() async {
    if (allDataFetched) return;
    
    setState(() {
      isLoading = true;
      isError = false;
    });

    try {
      // Check cache first
      final prefs = await SharedPreferences.getInstance();
      final cachedProductsStr = prefs.getString('cached_products_${widget.userId}');
      final cachedDonationsStr = prefs.getString('cached_donations_${widget.userId}');
      final cachedLostItemsStr = prefs.getString('cached_lost_items_${widget.userId}');
      
      if (cachedProductsStr != null || cachedDonationsStr != null || cachedLostItemsStr != null) {
        setState(() {
          if (cachedProductsStr != null) {
            userActivity['products'] = json.decode(cachedProductsStr);
            userActivity['purchasedProducts'] = json.decode(cachedProductsStr).where((p) => p['buyer'] != null).toList();
          }
          if (cachedDonationsStr != null) {
            userActivity['donations'] = json.decode(cachedDonationsStr);
          }
          if (cachedLostItemsStr != null) {
            userActivity['lost_items'] = json.decode(cachedLostItemsStr);
          }
        });
      }

      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/users/profile/${widget.userId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Cache the data
          final prefs = await SharedPreferences.getInstance();
          if (data['activity'] != null) {
            if (data['activity']['products'] != null) {
              await prefs.setString('cached_products_${widget.userId}', 
                json.encode(data['activity']['products']));
            }
            if (data['activity']['donations'] != null) {
              await prefs.setString('cached_donations_${widget.userId}', 
                json.encode(data['activity']['donations']));
            }
            if (data['activity']['lost_items'] != null) {
              await prefs.setString('cached_lost_items_${widget.userId}', 
                json.encode(data['activity']['lost_items']));
            }
          }

          setState(() {
            userData = data['user'];
            if (data['activity'] != null) {
              userActivity['products'] = data['activity']['products'] ?? [];
              userActivity['donations'] = data['activity']['donations'] ?? [];
              userActivity['lost_items'] = data['activity']['lost_items'] ?? [];
            }
            isLoading = false;
            allDataFetched = true;
          });

          if (userData != null && userData!['profilePicture'] != null) {
            _loadProfilePicture();
          }
          
          await Future.wait([
            _loadProductImages(),
            _loadDonationImages(),
            _loadLostItemImages()
          ]);
        }
      } else {
        setState(() {
          isLoading = false;
          isError = true;
          errorMessage = 'Failed to load user profile. Status: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        isError = true;
        errorMessage = 'Error: $e';
      });
      print('Error fetching profile: $e');
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
          // This is binary data (image)
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

  // Method to open chat with this user
  Future<void> _messageUser() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('$serverUrl/api/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'participantId': widget.userId,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Navigate to chat screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                conversationId: data['conversation']['_id'],
                partnerNames: userData?['userName'] ?? 'User',
                partnerId: widget.userId,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['error'] ?? 'Failed to start conversation')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start conversation')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
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

  // Add image loading functions
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

  Future<void> _loadLostItemImages() async {
    final lostItems = userActivity['lost_items'] ?? [];
    if (lostItems.isEmpty) return;

    final authCookie = await _secureStorage.read(key: 'authCookie');
    
    for (var item in lostItems) {
      if (item['_id'] == null) continue;
      
      try {
        final response = await http.get(
          Uri.parse('$serverUrl/api/lost-items/${item['_id']}/main_image'),
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
                _loadedImages['lostitem_${item['_id']}'] = data['image']['data'];
              });
            }
          }
        }
      } catch (e) {
        print('Error loading lost item image: $e');
      }
    }
  }

  // Add navigation methods
  void _navigateToProduct(String productId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailsScreen(
          product: {'_id': productId}
        ),
      ),
    );
  }

  void _navigateToLostItem(Map<String, dynamic> item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LostItemDetailsScreen(
          item: {'_id': item['_id']},
        ),
      ),
    );
  }

  // Add this method to show modern snackbar
  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    
    final snackBar = SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : Colors.green,
      duration: Duration(seconds: isError ? 4 : 2),
      behavior: SnackBarBehavior.floating,
      margin: EdgeInsets.only(
        bottom: MediaQuery.of(context).size.height - 100,
        right: 20,
        left: 20,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10.0),
      ),
    );
    
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  // Add block user functionality
  Future<void> _blockUser() async {
    bool confirmed = await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Text(
            'Block User',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to block ${userData?['userName'] ?? 'this user'}?',
            style: TextStyle(color: Colors.black87),
          ),
          actions: [
            TextButton(
              child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: Text('Block', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    ) ?? false;
    
    if (!confirmed) return;
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('$serverUrl/api/users/block/${widget.userId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        setState(() {
          isBlocked = true;
        });
        _showMessage('User blocked successfully');
      } else {
        _showMessage('Failed to block user', isError: true);
      }
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    }
  }

  // Add unblock user functionality
  Future<void> _unblockUser() async {
    bool confirmed = await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Text(
            'Unblock User',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Are you sure you want to unblock ${userData?['userName'] ?? 'this user'}?',
            style: TextStyle(color: Colors.black87),
          ),
          actions: [
            TextButton(
              child: Text('Cancel', style: TextStyle(color: Colors.grey[700])),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: Text('Unblock', style: TextStyle(color: Colors.blue)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    ) ?? false;
    
    if (!confirmed) return;
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.delete(
        Uri.parse('$serverUrl/api/users/unblock/${widget.userId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        setState(() {
          isBlocked = false;
        });
        _showMessage('User unblocked successfully');
      } else {
        _showMessage('Failed to unblock user', isError: true);
      }
    } catch (e) {
      _showMessage('Error: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0, // Prevents color change on scroll
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: isAppBarCollapsed ? Colors.white : Colors.transparent,
          elevation: 0,
          leading: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isAppBarCollapsed ? Colors.transparent : Colors.grey.shade100,
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
            ),
          ),
          title: Text(
            userData != null ? userData!['userName'] ?? 'User Profile' : 'User Profile',
            style: const TextStyle(color: Colors.black),
          ),
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
                : _buildUserProfileContent(),
      ),
    );
  }

  Widget _buildUserProfileContent() {
    if (userData == null) {
      return const Center(child: Text('No user data available'));
    }

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        children: [
          // Profile Header with Picture
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: userData!['profilePictureData'] != null
                      ? MemoryImage(base64Decode(userData!['profilePictureData']))
                      : null,
                  child: userData!['profilePictureData'] == null
                      ? const Icon(Icons.person, size: 60, color: Colors.grey)
                      : null,
                ),
                const SizedBox(height: 16),
                Text(
                  userData!['userName'] ?? 'Unknown User',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getRoleColor(userData!['role']),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    userData!['role']?.toUpperCase() ?? 'USER',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Member since ${_formatDate(userData!['registrationDate'])}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Action Buttons Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _messageUser,
                          icon: const Icon(Icons.message, size: 20),
                          label: const Text('Message'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size(0, 45), // Fixed height
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isBlocked ? _unblockUser : _blockUser,
                          icon: Icon(isBlocked ? Icons.lock_open : Icons.block, size: 20),
                          label: Text(isBlocked ? 'Unblock' : 'Block'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isBlocked ? Colors.orange : Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size(0, 45), // Fixed height
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => Theme(
                                data: Theme.of(context).copyWith(
                                  dialogBackgroundColor: Colors.white,
                                  dialogTheme: DialogTheme(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                ),
                                child: ReportDialog(
                                  userId: widget.userId,
                                  conversationId: '',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.report_problem, size: 20),
                          label: const Text('Report'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size(0, 45), // Fixed height
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          const Divider(),

          // Contact Information Section
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Contact Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                if (userData!['email'] != null)
                  _buildInfoItem(Icons.email_outlined, 'Email', userData!['email']),
                if (userData!['phone'] != null)
                  _buildInfoItem(Icons.phone_outlined, 'Phone', userData!['phone']),
              ],
            ),
          ),

          // Address Section
          if (userData!['address'] != null) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Address',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildAddressSection(userData!['address']),
                ],
              ),
            ),
          ],

          const SizedBox(height: 24),
          const Divider(),

          // Products Section
          const SizedBox(height: 24),
          _buildSectionHeader('Products', userActivity['products']?.length ?? 0),
          const SizedBox(height: 12),
          _buildItemsHorizontalList(userActivity['products'] ?? [], 'product'),

          // Donations Section
          const SizedBox(height: 24),
          _buildSectionHeader('Donations', userActivity['donations']?.length ?? 0),
          const SizedBox(height: 12),
          _buildItemsHorizontalList(userActivity['donations'] ?? [], 'donation', isClickable: false),

          // Lost Items Section
          const SizedBox(height: 24),
          _buildSectionHeader('Lost Items', userActivity['lost_items']?.length ?? 0),
          const SizedBox(height: 12),
          _buildItemsHorizontalList(userActivity['lost_items'] ?? [], 'lostitem'),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            '$count items',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsHorizontalList(List items, String type, {bool isClickable = true}) {
    return items.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Icon(
                    type == 'product' ? Icons.shopping_bag_outlined :
                    type == 'donation' ? Icons.volunteer_activism_outlined :
                    Icons.search_outlined,
                    size: 48,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No ${type}s yet',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          )
        : SizedBox(
            height: 220,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                Widget itemPreview = _buildItemPreview(item, type);
                
                // Only wrap with GestureDetector if the item is clickable
                if (isClickable) {
                  return GestureDetector(
                    onTap: () {
                      if (type == 'product' || type == 'purchased') {
                        _navigateToProduct(item['_id']);
                      } else if (type == 'lostitem') {
                        _navigateToLostItem(item);
                      }
                    },
                    child: itemPreview,
                  );
                }
                
                return itemPreview;
              },
            ),
          );
  }

  Widget _buildItemPreview(Map<String, dynamic> item, String type) {
    final String itemId = item['_id'];
    final String? imageData = _loadedImages['${type}_$itemId'];
    final String title = item['name'] ?? 'Unnamed Item';
    
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageData != null)
                    Image.memory(
                      base64Decode(imageData),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      isAntiAlias: true,
                      filterQuality: FilterQuality.medium,
                      cacheWidth: 320,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Icon(
                            Icons.image_not_supported,
                            size: 40,
                            color: Colors.grey[400],
                          ),
                        );
                      },
                    )
                  else
                    Shimmer.fromColors(
                      baseColor: Colors.grey[300]!,
                      highlightColor: Colors.grey[100]!,
                      child: Container(color: Colors.white),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddressSection(Map<String, dynamic> address) {
    final street = address['street'];
    final city = address['city'];
    final state = address['state'];
    final zipCode = address['zipCode'];
    final country = address['country'];
    
    final formattedAddress = [
      if (street != null && street.isNotEmpty) street,
      if (city != null && city.isNotEmpty) city,
      if (state != null && state.isNotEmpty) state,
      if (zipCode != null && zipCode.isNotEmpty) zipCode,
      if (country != null && country.isNotEmpty) country,
    ].join(', ');
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.location_on_outlined, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Address',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formattedAddress.isNotEmpty ? formattedAddress : 'No address provided',
                  style: const TextStyle(
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'admin':
        return Colors.red.shade700;
      case 'volunteer':
        return Colors.green.shade700;
      case 'volunteer_pending':
        return Colors.orange.shade700;
      default:
        return Colors.blue.shade700;
    }
  }
}
