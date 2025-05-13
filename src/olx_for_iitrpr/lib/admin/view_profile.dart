import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'server.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'view_product.dart';
import 'view_donation.dart';
import 'view_lost_item.dart';
import 'view_report.dart';
import 'view_user_items.dart';
import '../services/profile_service.dart';
import '../services/product_cache_service.dart';
import '../services/donation_cache_service.dart';
import '../services/lost_found_cache_service.dart';

class ViewProfileScreen extends StatefulWidget {
  final String userId;

  const ViewProfileScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen> {
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
    'lost_items': [], // Add lost items array
    'reportsFiled': {
      'user': [],
      'product': []
    },
    'reportsAgainst': []
  };
  
  // Flag to prevent reloading when coming back
  bool allDataFetched = false;
  
  // Cache for loaded images
  // Change the type from Map<String, String> to Map<String, Uint8List>
  final Map<String, Uint8List> _loadedImages = {};

  // Add these new state variables
  final double expandedHeight = 200.0;
  final double collapsedHeight = kToolbarHeight;
  final double profilePicHeightExpanded = 100.0;
  final double profilePicHeightCollapsed = 32.0;

  double _getProfilePicSize(double t) {
    // t is between 0.0 (expanded) and 1.0 (collapsed)
    return Tween<double>(
      begin: profilePicHeightExpanded,
      end: profilePicHeightCollapsed,
    ).transform(t);
  }

  double _getProfilePicLeftPadding(double t) {
    // Move from center to left
    return Tween<double>(
      begin: MediaQuery.of(context).size.width / 2 - profilePicHeightExpanded / 2,
      end: 56.0, // Left padding when collapsed
    ).transform(t);
  }

  late final double safeAreaTop;
  
  double _getNameTopPadding(double t) {
    safeAreaTop = MediaQuery.of(context).padding.top;
    // Reduce the gap between profile picture and name
    return Tween<double>(
      begin: profilePicHeightExpanded + 8, // Reduced from 16 to 8
      end: safeAreaTop,
    ).transform(t);
  }

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
    _scrollController.addListener(_onScroll);
  }

  // Add this new method to load all images
  Future<void> _loadAllImages() async {
    await _loadProductImages();
    await _loadPurchasedProductImages();
    await _loadDonationImages();
    await _loadLostItemImages();
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
    if (allDataFetched) return;
    
    setState(() {
      isLoading = true;
      isError = false;
    });

    try {
      // Try to load from cache first
      final cachedData = await ProfileService.getCachedUserProfile(widget.userId);
      if (cachedData != null) {
        setState(() {
          userData = cachedData;
          // profilePictureData is already included in cachedData
          isLoading = false;
        });
      }

      // Fetch fresh data
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
          // Cache the complete response
          await ProfileService.cacheUserProfile(widget.userId, data);

          setState(() {
            userData = data['user'];
            // profilePictureData comes directly from data['user']['profilePicture']
            if (userData!['profilePicture']?.containsKey('data') ?? false) {
              userData!['profilePictureData'] = userData!['profilePicture']['data'];
            }
            userActivity = data['activity'] ?? userActivity;
            isLoading = false;
            allDataFetched = true;
          });
          // Load images only after userActivity is updated
          await _loadAllImages();
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

  Future<void> _loadProductImages() async {
    final products = userActivity['products'] ?? [];
    if (products.isEmpty) return;

    final authCookie = await _secureStorage.read(key: 'authCookie');
    
    for (var product in products) {
      if (product['_id'] == null) continue;
      
      try {
        // Try to get from cache first
        final cachedImage = await ProductCacheService.getCachedImage(product['_id']);
        if (cachedImage != null) {
          if (mounted) {
            setState(() {
              _loadedImages['product_${product['_id']}'] = cachedImage;
            });
          }
          continue; // Skip API call if we have cached image
        }

        final response = await http.get(
          Uri.parse('$serverUrl/api/products/${product['_id']}/main_image'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie ?? '',
          },
        );

        print("Image received for the product");

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] && data['image'] != null) {
            final image = data['image'];
            final numImages = data['numImages'] ?? 1;
            
            if (image != null && image['data'] != null) {
              final bytes = base64Decode(image['data']);
              
              // Cache the image
              await ProductCacheService.cacheImage(product['_id'], bytes, numImages);
              
              if (mounted) {
                setState(() {
                  _loadedImages['product_${product['_id']}'] = bytes;
                });
              }
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
            // Fix: decode the base64 string to Uint8List
            final bytes = base64Decode(data['image']['data']);
            if (mounted) {
              setState(() {
                _loadedImages['purchased_${product['_id']}'] = bytes;
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
        // Try to get from cache first
        final cachedImage = await DonationCacheService.getCachedImage(donation['_id']);
        if (cachedImage != null) {
          if (mounted) {
            setState(() {
              _loadedImages['donation_${donation['_id']}'] = cachedImage;
            });
          }
          continue; // Skip API call if we have cached image
        }

        final response = await http.get(
          Uri.parse('$serverUrl/api/donations/${donation['_id']}/main_image'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie ?? '',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] && data['image'] != null) {
            final image = data['image'];
            final numImages = data['numImages'] ?? 1;
            
            if (image != null && image['data'] != null) {
              final bytes = base64Decode(image['data']);
              
              // Cache the image
              await DonationCacheService.cacheImage(donation['_id'], bytes, numImages);
              
              if (mounted) {
                setState(() {
                  _loadedImages['donation_${donation['_id']}'] = bytes;
                });
              }
            }
          }
        }
      } catch (e) {
        print('Error loading donation image: $e');
      }
    }
  }

  // Add this new function
  Future<void> _loadLostItemImages() async {
    final lostItems = userActivity['lost_items'] ?? [];
    if (lostItems.isEmpty) return;

    final authCookie = await _secureStorage.read(key: 'authCookie');
    
    for (var item in lostItems) {
      if (item['_id'] == null) continue;
      
      try {
        // Try to get from cache first
        final cachedImage = await LostFoundCacheService.getCachedImage(item['_id']);
        if (cachedImage != null) {
          if (mounted) {
            setState(() {
              _loadedImages['lostitem_${item['_id']}'] = cachedImage;
            });
          }
          continue; // Skip API call if we have cached image
        }

        final response = await http.get(
          Uri.parse('$serverUrl/api/lost-items/${item['_id']}/main_image'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie ?? '',
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] && data['image'] != null) {
            final image = data['image'];
            final numImages = data['numImages'] ?? 1;
            
            if (image != null && image['data'] != null) {
              final bytes = base64Decode(image['data']);
              
              // Cache the image
              await LostFoundCacheService.cacheImage(item['_id'], bytes, numImages);
              
              if (mounted) {
                setState(() {
                  _loadedImages['lostitem_${item['_id']}'] = bytes;
                });
              }
            }
          }
        }
      } catch (e) {
        print('Error loading lost item image: $e');
      }
    }
  }

  void _navigateToProduct(String productId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProductDetailsScreen(product: {'_id': productId}),
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

  // Update _buildItemPreview to center align text
  Widget _buildItemPreview(Map<String, dynamic> item, String type, String idPrefix, Function onTap) {
    final String itemId = item['_id'];
    final Uint8List? imageData = _loadedImages['${idPrefix}_$itemId'];
    final String title = item['name'] ?? 'Unnamed ${ViewReportStringExtension(type).capitalize()}';
    
    return GestureDetector(
      onTap: () => onTap(itemId),
      child: Container(
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
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageData != null)
                      Image.memory(
                        imageData,  // No need for base64Decode here
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
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  if (type == 'purchased' && item['seller'] != null)
                    Text(
                      'Seller: ${item['seller']['userName'] ?? 'Unknown'}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
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
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: label == 'Status' && value == 'BLOCKED' 
                    ? Colors.red 
                    : Colors.black87,
                fontWeight: label == 'Status' ? FontWeight.w600 : FontWeight.normal,
              ),
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
  
  Widget _buildEmptyStateCard(String message) {
    return Center(
      child: Container(
        padding: EdgeInsets.all(16),
        child: Text(
          message,
          style: TextStyle(fontSize: 16, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
  
  Widget _buildProductsSection() {
    final products = userActivity['products'] ?? [];
    return products.isEmpty
        ? _buildEmptyStateCard('User has not listed any products yet')
        : _buildItemsHorizontalList(products, 'product');
  }

  Widget _buildPurchasedProductsSection() {  // New method specifically for purchased products
    final purchasedProducts = userActivity['purchasedProducts'] ?? [];
    return purchasedProducts.isEmpty
        ? _buildEmptyStateCard('User has not purchased any products yet')
        : _buildItemsHorizontalList(purchasedProducts, 'purchased');
  }

  Widget _buildDonationsSection() {
    final donations = userActivity['donations'] ?? [];
    return donations.isEmpty
        ? _buildEmptyStateCard('User has not made any donations yet')
        : _buildItemsHorizontalList(donations, 'donation');
  }
  
  Widget _buildLostItemsSection() {
    final lostitems = userActivity['lost_items'] ?? [];
    return lostitems.isEmpty
        ? _buildEmptyStateCard('User has not reported any lost items')
        : _buildItemsHorizontalList(lostitems, 'lostitem');
  }

  // Update _buildItemsHorizontalList method
  Widget _buildItemsHorizontalList(List items, String type) {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) {
          switch(type) {
            case 'donation':
              return _buildItemPreview(
                items[index], 
                type, 
                type,
                (id) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DonationDetailsScreen(donation: items[index]),
                  ),
                ),
              );
            case 'lostitem':
              return _buildItemPreview(
                items[index], 
                type, 
                type,
                (id) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => LostItemDetailsScreen(item: items[index]),
                  ),
                ),
              );
            default:
              return _buildItemPreview(items[index], type, type, _navigateToProduct);
          }
        },
      ),
    );
  }
  
  Widget _buildReportsFiledSection() {
    final userReports = userActivity['reportsFiled']['user'] as List;
    final productReports = userActivity['reportsFiled']['product'] as List;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Reports Filed',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...userReports.map((report) => GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReportDetailScreen(
                reportId: report['_id'],
                reportType: 'user',
              ),
            ),
          ),
          child: Card(
            margin: EdgeInsets.only(bottom: 8),
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey[200]!),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text('Against User: ${report['reportedUser']?['userName'] ?? 'Unknown'}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report['reason'] ?? 'No reason provided',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Filed on: ${_formatDate(report['createdAt'])}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              trailing: _buildReportStatusBadge(report['status']),
            ),
          ),
        )).toList(),
        ...productReports.map((report) => GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReportDetailScreen(
                reportId: report['_id'],
                reportType: 'product',
              ),
            ),
          ),
          child: Card(
            margin: EdgeInsets.only(bottom: 8),
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey[200]!),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text('Against Product: ${report['product']?['name'] ?? 'Unknown'}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report['reason'] ?? 'No reason provided',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Filed on: ${_formatDate(report['createdAt'])}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              trailing: _buildReportStatusBadge(report['status']),
            ),
          ),
        )).toList(),
      ],
    );
  }

  Widget _buildReportsAgainstSection() {
    final reports = userActivity['reportsAgainst'] as List;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reports.isNotEmpty) const Divider(height: 32),
        Text(
          'Reports Against User',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...reports.map((report) => GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReportDetailScreen(
                reportId: report['_id'],
                reportType: 'user',
              ),
            ),
          ),
          child: Card(
            margin: EdgeInsets.only(bottom: 8),
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey[200]!),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              title: Text('From: ${report['reporter']?['userName'] ?? 'Unknown'}'),
              subtitle: Text(
                report['reason'] ?? 'No reason provided',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _buildReportStatusBadge(report['status']),
            ),
          ),
        )).toList(),
      ],
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

    final safeAreaTop = MediaQuery.of(context).padding.top;
    
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverAppBar(
          expandedHeight: expandedHeight,
          pinned: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: Container(
            margin: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isAppBarCollapsed ? Colors.transparent : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          flexibleSpace: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final minHeight = safeAreaTop + kToolbarHeight;
              final maxHeight = expandedHeight + safeAreaTop;
              
              final progress = ((maxHeight - constraints.maxHeight) / (maxHeight - minHeight))
                  .clamp(0.0, 1.0);

              return Stack(
                fit: StackFit.expand,
                children: [
                  // Profile Picture with animation
                  Positioned(
                    top: safeAreaTop + (kToolbarHeight - profilePicHeightCollapsed) / 2,
                    left: _getProfilePicLeftPadding(progress),
                    child: Column(
                      children: [
                        Container(
                          height: _getProfilePicSize(progress),
                          width: _getProfilePicSize(progress),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[200],
                            image: userData!['profilePictureData'] != null
                                ? DecorationImage(
                                    image: MemoryImage(
                                      base64Decode(userData!['profilePictureData']),
                                    ),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: userData!['profilePictureData'] == null
                              ? Icon(
                                  Icons.person,
                                  size: _getProfilePicSize(progress) * 0.5,
                                  color: Colors.grey,
                                )
                              : null,
                        ),
                        if (!isAppBarCollapsed) ...[
                          const SizedBox(height: 8),
                          Text(
                            userData!['userName'] ?? 'Unknown User',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
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
                        ],
                      ],
                    ),
                  ),
                  
                  // Collapsed state username
                  if (isAppBarCollapsed)
                    Positioned(
                      top: safeAreaTop,
                      left: _getProfilePicLeftPadding(progress) + _getProfilePicSize(progress) + 12,
                      child: Container(
                        height: kToolbarHeight,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          userData!['userName'] ?? 'Unknown User',
                          style: TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        
        // Rest of the content
        SliverToBoxAdapter(
          child: Column(
            children: [
              // User Info Section (add this before Products section)
              _buildInfoBox(
                'User Information',
                [
                  _buildDetailRow('Email', userData!['email'] ?? 'N/A'),
                  _buildDetailRow('Phone', userData!['phone'] ?? 'N/A'),
                  _buildDetailRow('Role', userData!['role']?.toUpperCase() ?? 'N/A'),
                  _buildDetailRow('Joined', _formatDate(userData!['createdAt'])),
                  _buildDetailRow('Last Active', _formatTimeAgo(userData!['lastSeen'])),
                  _buildDetailRow('Status', userData!['isBlocked'] == true ? 'BLOCKED' : 'ACTIVE'),
                  if (userData!['isBlocked'] == true) ...[
                    _buildDetailRow('Blocked At', _formatDate(userData!['blockedAt'])),
                    _buildDetailRow('Block Reason', userData!['blockReason'] ?? 'N/A'),
                  ],
                ],
              ),

              // Products Section
              _buildInfoBox(
                'Products',
                [_buildProductsSection()],
              ),
              
              // Purchased Products Section
              _buildInfoBox(
                'Purchased Products',
                [_buildPurchasedProductsSection()], // Changed from _buildProductsSection()
              ),
              
              // Donations Section
              _buildInfoBox(
                'Donations',
                [_buildDonationsSection()],
              ),
              
              // Lost Items Section
              _buildInfoBox(
                'Lost Items',
                [_buildLostItemsSection()],
              ),

              // Reports Section
              _buildInfoBox(
                'Reports',
                [
                  if (userActivity['reportsFiled']['user'].isEmpty && 
                      userActivity['reportsFiled']['product'].isEmpty &&
                      userActivity['reportsAgainst'].isEmpty)
                    _buildEmptyStateCard('No reports associated with this user')
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((userActivity['reportsFiled']['user'] as List).isNotEmpty ||
                            (userActivity['reportsFiled']['product'] as List).isNotEmpty)
                          _buildReportsFiledSection(),
                        if ((userActivity['reportsAgainst'] as List).isNotEmpty)
                          _buildReportsAgainstSection(),
                      ],
                    ),
                ],
              ),
              
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }
}