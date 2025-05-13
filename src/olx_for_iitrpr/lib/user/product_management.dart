import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'edit_product_screen.dart';
import '../services/product_cache_service.dart';
import 'server.dart';
import 'view_profile.dart'; // Add this import

class SellerOfferManagementScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final int initialTab; // Add this parameter

  const SellerOfferManagementScreen({
    Key? key,
    required this.product,
    this.initialTab = 0, // Default to first tab
  }) : super(key: key);

  @override
  State<SellerOfferManagementScreen> createState() => _SellerOfferManagementScreenState();
}

class _SellerOfferManagementScreenState extends State<SellerOfferManagementScreen> with SingleTickerProviderStateMixin {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> offers = [];
  bool isLoading = true;
  String errorMessage = '';
  
  // Image caching fields
  final Map<String, List<Uint8List>> _imageCache = {};
  final Set<String> _loadingImages = {};
  bool _isLoadingImages = true;
  int _totalExpectedImages = 1;

  // Add these state variables at the top of the class
  String? errorMessageDisplay;
  String? successMessage;
  Timer? _messageTimer;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab, // Use the initialTab parameter
    );
    fetchOffers();
    _loadCachedImages();
  }

  @override
  void dispose() {
    _messageTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // Add helper method for showing messages
  void _showMessage({String? error, String? success}) {
    _messageTimer?.cancel();
    setState(() {
      errorMessageDisplay = error;
      successMessage = success;
    });
    _messageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          errorMessageDisplay = null;
          successMessage = null;
        });
      }
    });
  }

  Future<void> fetchOffers() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/products/${widget.product['_id']}/offers'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          offers = data['offerRequests'] ?? [];
          isLoading = false;
        });
      } else {
        throw Exception(data['error'] ?? 'Failed to fetch offers');
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> _handleOfferAction(String offerId, String action) async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('$serverUrl/api/products/offers/$offerId/$action'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({'productId': widget.product['_id']}),
      );
      
      if (response.statusCode == 200) {
        if (action == 'accept') {
          setState(() {
            widget.product['status'] = 'sold';
            offers = []; // Clear all offers
          });
          
          // Update the cache with the updated product status
          final cachedProduct = await ProductCacheService.getCachedProduct(widget.product['_id']);
          if (cachedProduct != null) {
            cachedProduct['status'] = 'sold';
            await ProductCacheService.cacheProduct(widget.product['_id'], cachedProduct);
          }
          
          _showMessage(success: 'Offer accepted. Product marked as sold.');
          
          // Navigate back after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            Navigator.of(context).pop();
          });
        } else {
          _showMessage(success: 'Offer rejected successfully');
          fetchOffers(); // Refresh the offers list
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to $action offer');
      }
    } catch (e) {
      _showMessage(error: 'Error: ${e.toString()}');
    }
  }

  Future<void> _loadCachedImages() async {
    setState(() {
      _isLoadingImages = true;
    });
    
    try {
      // Check if we have cached number of images first
      final numImages = await ProductCacheService.getCachedNumImages(widget.product['_id']);
      if (numImages != null) {
        _totalExpectedImages = numImages;
      }
      
      // Try to get cached images
      final cachedImages = await ProductCacheService.getCachedAllImages(widget.product['_id']);
      if (cachedImages != null && cachedImages.isNotEmpty) {
        setState(() {
          _imageCache[widget.product['_id']] = cachedImages;
          _isLoadingImages = false;
        });
      } else {
        // If no cached images or we don't have all expected images, fetch them
        await _fetchAllProductImages();
      }
    } catch (e) {
      print('Error loading cached images: $e');
      // Try to fetch fresh images if caching failed
      await _fetchAllProductImages();
    }
  }
  
  Future<void> _fetchAllProductImages() async {
    if (_loadingImages.contains(widget.product['_id'])) return;
    
    _loadingImages.add(widget.product['_id']);
    setState(() => _isLoadingImages = true);
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/products/${widget.product['_id']}/images'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] && data['images'] != null) {
          final images = data['images'] as List;
          final List<Uint8List> imagesList = [];
          
          for (var image in images) {
            if (image != null && image['data'] != null) {
              final imageBytes = base64Decode(image['data']);
              imagesList.add(imageBytes);
            }
          }
          
          // Cache the images
          if (imagesList.isNotEmpty) {
            await ProductCacheService.cacheAllImages(widget.product['_id'], imagesList);
            await ProductCacheService.cacheNumImages(widget.product['_id'], imagesList.length);
            
            if (mounted) {
              setState(() {
                _imageCache[widget.product['_id']] = imagesList;
                _totalExpectedImages = imagesList.length;
                _isLoadingImages = false;
              });
            }
          } else {
            // If no images were found, set loading to false
            setState(() => _isLoadingImages = false);
          }
        }
      } else {
        throw Exception('Failed to load images');
      }
    } catch (e) {
      print('Error fetching all product images: $e');
      setState(() => _isLoadingImages = false);
    } finally {
      _loadingImages.remove(widget.product['_id']);
    }
  }

  Future<void> _closeProduct() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.post(
        Uri.parse('$serverUrl/api/products/${widget.product['_id']}/close'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      // Check if response is JSON by looking at content-type header
      final isJson = response.headers['content-type']?.contains('application/json') ?? false;

      if (response.statusCode == 200 && isJson) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            widget.product['status'] = 'closed';
          });
          
          // Update cache
          final cachedProduct = await ProductCacheService.getCachedProduct(widget.product['_id']);
          if (cachedProduct != null) {
            cachedProduct['status'] = 'closed';
            await ProductCacheService.cacheProduct(widget.product['_id'], cachedProduct);
          }

          _showMessage(success: 'Product closed successfully');

          // Navigate back after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            Navigator.of(context).pop();
          });
        } else {
          throw Exception(data['error'] ?? 'Failed to close product');
        }
      } else {
        throw Exception('Server error: Please try again later');
      }
    } catch (e) {
      _showMessage(error: e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _showCloseConfirmationDialog() async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Close Product',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Are you sure you want to close this product listing? This will remove it from active listings and cannot be undone.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 16,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _closeProduct();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Theme(
        data: Theme.of(context).copyWith(
          appBarTheme: AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
        ),
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            systemOverlayStyle: SystemUiOverlayStyle.dark,
            leading: Container(
              margin: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.black),
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            actions: [
              if (widget.product['status'] == 'available') // Only show edit button if product is available
                Container(
                  margin: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.edit, color: Colors.black),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditProductScreen(product: widget.product),
                        ),
                      );
                    },
                  ),
                ),
            ],
            title: Text(
              'Product Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black,
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.black,
              tabs: [
                Tab(text: 'Details'),
                Tab(text: 'Offers'),
              ],
            ),
          ),
          body: Column(
            children: [
              // Add message boxes at the top
              if (errorMessageDisplay != null)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade50,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errorMessageDisplay!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              if (successMessage != null)
                Container(
                  width: double.infinity,
                  color: Colors.green.shade50,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.green.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          successMessage!,
                          style: TextStyle(color: Colors.green.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDetailsTab(),
                    _buildOffersList(),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: widget.product['status'] == 'available' 
            ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 5,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _showCloseConfirmationDialog,
                  child: const Text(
                    'Close Product',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              )
            : null,
        ),
      ),
    );
  }

  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image carousel
          if (_imageCache[widget.product['_id']]?.isNotEmpty == true || _isLoadingImages)
            _buildImageCarousel(),
          const SizedBox(height: 16),

          // Name and Status row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.product['name'] ?? 'Unknown Product',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(widget.product['status']).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  (widget.product['status'] ?? 'AVAILABLE').toUpperCase(),
                  style: TextStyle(
                    color: _getStatusColor(widget.product['status']),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Price with label
          Row(
            children: [
              Text(
                'Price: ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              Text(
                '₹${widget.product['price']?.toString() ?? '0'}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Tags section on same line
          Row(
            children: [
              Text(
                'Tags: ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildTag('Campus'),
                      _buildTag('Electronics'),
                      if (widget.product['category'] != null)
                        _buildTag(widget.product['category']),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Description
          Text(
            'Description',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.product['description'] ?? 'No description available',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[800],
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Timestamps in blue box
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTimeDetail(
                  'Posted on',
                  _formatDateTime(widget.product['createdAt']),
                ),
                const SizedBox(height: 4),
                if (widget.product['lastUpdatedAt'] != null)
                  _buildTimeDetail(
                    'Last updated',
                    _formatDateTime(widget.product['lastUpdatedAt']),
                  ),
              ],
            ),
          ),

          // Add Buyer Details section for sold products
          if (widget.product['status'] == 'sold' && widget.product['buyer'] != null) ...[
            const SizedBox(height: 24),
            Text(
              'Buyer Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ViewProfileScreen(userId: widget.product['buyer']['_id']),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                          Icons.person,
                          color: Colors.grey.shade400,
                          size: 30,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.product['buyer']['userName'] ?? 'Unknown Buyer',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTag(String text) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.blue[700],
        ),
      ),
    );
  }

  Widget _buildTimeDetail(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.black, // Changed from blue to black
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            color: Colors.black, // Changed from blue to black
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatDateTime(String? dateString) {
    if (dateString == null) return 'Unknown date';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  Widget _buildImageCarousel() {
    List<Widget> imageSlides = [];
    
    if (_imageCache.containsKey(widget.product['_id'])) {
      final images = _imageCache[widget.product['_id']]!;
      imageSlides = List.generate(images.length, (index) {
        return Image.memory(
          images[index],
          fit: BoxFit.cover,
          width: double.infinity,
        );
      });
    } else {
      // Show placeholder with loading indicator
      imageSlides = [
        Container(
          color: Colors.grey[200],
          child: Center(
            child: _isLoadingImages
                ? const CircularProgressIndicator()
                : const Icon(Icons.image_not_supported),
          ),
        ),
      ];
    }

    return Stack(
      children: [
        CarouselSlider(
          items: imageSlides,
          options: CarouselOptions(
            height: 300,
            viewportFraction: 1.0,
            enableInfiniteScroll: imageSlides.length > 1,
            autoPlay: imageSlides.length > 1,
            autoPlayInterval: const Duration(seconds: 3),
          ),
        ),
        if (_isLoadingImages)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildOffersList() {
    return isLoading
        ? const Center(child: CircularProgressIndicator())
        : errorMessage.isNotEmpty
            ? Center(child: Text('Error: $errorMessage'))
            : offers.isEmpty
                ? const Center(child: Text('No offers yet'))
                : ListView.builder(
                    itemCount: offers.length,
                    itemBuilder: (context, index) {
                      final offer = offers[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '₹${offer['offerPrice']}',
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      // Wrap buyer details with InkWell:
                                      InkWell(
                                        onTap: () {
                                          if (offer['buyer'] != null && offer['buyer']['_id'] != null) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ViewProfileScreen(userId: offer['buyer']['_id']),
                                              ),
                                            );
                                          }
                                        },
                                        child: Text(
                                          'From: ${offer['buyer']?['userName'] ?? 'Unknown'}',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.blue, // indicate it's clickable
                                            decoration: TextDecoration.underline,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Date: ${DateTime.parse(offer['createdAt']).toString().split('.')[0]}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (widget.product['status'] == 'available') // Only show action buttons if product is available
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border(
                                      left: BorderSide(color: Colors.grey.shade200),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _buildActionButton(
                                        icon: Icons.check_circle,
                                        color: Colors.green,
                                        onPressed: () => _showConfirmationDialog(
                                          'Accept Offer',
                                          'Are you sure you want to accept this offer? This will mark the product as sold.',
                                          () => _handleOfferAction(offer['_id'], 'accept'),
                                        ),
                                      ),
                                      Container(
                                        height: 1,
                                        width: 56,
                                        color: Colors.grey.shade200,
                                      ),
                                      _buildActionButton(
                                        icon: Icons.cancel,
                                        color: Colors.red,
                                        onPressed: () => _showConfirmationDialog(
                                          'Reject Offer',
                                          'Are you sure you want to reject this offer?',
                                          () => _handleOfferAction(offer['_id'], 'decline'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 56,
      height: 56,
      child: IconButton(
        icon: Icon(icon, size: 32),
        color: color,
        onPressed: onPressed,
      ),
    );
  }

  Future<void> _showConfirmationDialog(String title, String message, Function onConfirm) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 16,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: title.contains('Accept') ? Colors.green : Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: Text(
                        title.split(' ')[0],
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onConfirm();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'sold':
        return Colors.orange.shade700;
      case 'available':
      default:
        return Colors.green.shade700;
    }
  }
}
