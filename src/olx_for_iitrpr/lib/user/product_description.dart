import 'package:flutter/material.dart' hide CarouselController;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'chat_screen.dart';
import 'view_profile.dart';
import '../services/product_cache_service.dart';
import 'server.dart';

class ProductDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final bool showOfferButton;
  
  const ProductDetailsScreen({
    super.key,
    required this.product,
    this.showOfferButton = true,
  });

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String currentUserName = '';
  String currentUserId = '';
  int _currentImageIndex = 0;
  final CarouselSliderController _carouselController = CarouselSliderController();
  
  bool hasOffer = false;
  double? currentOfferAmount;
  bool isCheckingOffer = true;
  Map<String, dynamic>? productDetails;
  bool isLoading = true;
  bool isLoadingAllImages = false;
  
  // Store images
  List<Uint8List> productImages = [];
  int totalNumImages = 1;

  // Add these variables to track seller details
  Map<String, dynamic>? sellerDetails;
  Map<String, dynamic>? sellerProfile;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadProductDetails();
    
    if (widget.product['_id'] != null) {
      _checkExistingOffer();
    }
  }

  Future<void> _loadCurrentUser() async {
    String? name = await _secureStorage.read(key: 'userName');
    String? id = await _secureStorage.read(key: 'userId');
    if (mounted) {
      setState(() {
        currentUserName = name ?? '';
        currentUserId = id ?? '';
      });
    }
  }

  Future<void> _loadProductDetails() async {
    // First set with the data we already have
    setState(() {
      productDetails = widget.product;
      isLoading = false;
      
      // Use imageData if passed from products tab
      if (widget.product['imageData'] != null) {
        productImages = [widget.product['imageData']];
      }
    });
    
    // Check for cached product
    final cachedProduct = await ProductCacheService.getCachedProduct(widget.product['_id']);
    if (cachedProduct != null) {
      setState(() {
        productDetails = cachedProduct;
      });
    }
    
    // Check for cached images
    await _loadCachedImages();
    
    // Fetch fresh product data
    _fetchProductDetails();
  }
  
  Future<void> _loadCachedImages() async {
    try {
      // Get cached number of images first
      final numImages = await ProductCacheService.getCachedNumImages(widget.product['_id']);
      if (numImages != null) {
        totalNumImages = numImages;
      }
      
      // Try to get cached images
      final cachedImages = await ProductCacheService.getCachedAllImages(widget.product['_id']);
      if (cachedImages != null && cachedImages.isNotEmpty) {
        setState(() {
          productImages = cachedImages;
          isLoadingAllImages = false;
        });
      } else if (productImages.isEmpty && widget.product['imageData'] != null) {
        // We have at least the main image from products tab
        setState(() {
          productImages = [widget.product['imageData']];
        });
      } else {
        // If we don't have all expected images or any images, fetch them
        _fetchAllProductImages();
      }
    } catch (e) {
      print('Error loading cached images: $e');
      _fetchAllProductImages();
    }
  }

  Future<void> _fetchProductDetails() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/products/${widget.product['_id']}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          // Cache the product data
          await ProductCacheService.cacheProduct(widget.product['_id'], data['product']);
          
          if (mounted) {
            setState(() {
              productDetails = data['product'];
            });
          }
          
          // Check if we need to update images
          final lastUpdated = await ProductCacheService.getProductLastUpdated(widget.product['_id']);
          final numImages = await ProductCacheService.getCachedNumImages(widget.product['_id']);
          
          if (numImages == null || productImages.isEmpty || 
              productImages.length < numImages ||
              (lastUpdated != null && productDetails?['lastUpdatedAt'] != null && 
               DateTime.parse(productDetails!['lastUpdatedAt']).isAfter(lastUpdated))) {
            _fetchAllProductImages();
          }
        }
      }
    } catch (e) {
      print('Error fetching product details: $e');
    }
  }

  Future<void> _fetchAllProductImages() async {
    if (isLoadingAllImages) return;
    
    setState(() {
      isLoadingAllImages = true;
    });
    
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
          List<Uint8List> loadedImages = [];
          final images = data['images'] as List;
          
          for (var image in images) {
            if (image != null && image['data'] != null) {
              final String base64Str = image['data'];
              final Uint8List bytes = base64Decode(base64Str);
              loadedImages.add(bytes);
            }
          }
          
          // Cache images and number of images
          if (loadedImages.isNotEmpty) {
            await ProductCacheService.cacheAllImages(widget.product['_id'], loadedImages);
            await ProductCacheService.cacheNumImages(widget.product['_id'], loadedImages.length);
            
            if (mounted) {
              setState(() {
                productImages = loadedImages;
                totalNumImages = loadedImages.length;
                isLoadingAllImages = false;
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching all product images: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoadingAllImages = false;
        });
      }
    }
  }

  Future<void> _checkExistingOffer() async {
    if (widget.product['_id'] == null) {
      setState(() {
        isCheckingOffer = false;
      });
      return;
    }
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/products/${widget.product['_id']}/check-offer'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            // If the offer was rejected (status == 'rejected'), set hasOffer to false
            hasOffer = (data['hasOffer'] ?? false) && (data['offerStatus'] != 'rejected');
            currentOfferAmount = hasOffer ? data['offerAmount']?.toDouble() : null;
            isCheckingOffer = false;
          });
        }
      }
    } catch (e) {
      print('Error checking offer status: $e');
      if (mounted) {
        setState(() {
          isCheckingOffer = false;
        });
      }
    }
  }

  void _startChat() async {
    if (productDetails?['seller']?['_id'] == null) return;
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // First, get or create the conversation
      final conversationResponse = await http.post(
        Uri.parse('$serverUrl/api/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'participantId': productDetails!['seller']['_id'],
        }),
      );
      
      if (conversationResponse.statusCode == 200) {
        final conversationData = json.decode(conversationResponse.body);
        final conversationId = conversationData['conversation']['_id'];
        
        // Get product image for the chat
        String? imageData;
        if (productImages.isNotEmpty) {
          imageData = base64Encode(productImages[0]);
        }
        
        // Create the product data to initialize the reply
        final initialProduct = {
          'productId': widget.product['_id'],
          'name': widget.product['name'],
          'price': widget.product['price'],
          'image': imageData,
        };
        
        // Navigate to the chat screen with the product data
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              partnerNames: productDetails!['seller']['userName'],
              partnerId: productDetails!['seller']['_id'],
              initialProduct: initialProduct,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error starting chat: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error starting chat. Please try again.')),
      );
    }
  }

  Widget _buildImageCarousel() {
    if (productImages.isEmpty) {
      return Container(
        width: double.infinity,
        height: 300,
        color: Colors.grey[200],
        child: Center(
          child: isLoadingAllImages
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_not_supported, color: Colors.grey[400], size: 50),
                    const SizedBox(height: 8),
                    Text(
                      'No images available',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
        ),
      );
    }

    // Build image widgets from Uint8List
    List<Widget> imageWidgets = [];
    for (var imageBytes in productImages) {
      imageWidgets.add(
        Image.memory(
          imageBytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: 300,
          errorBuilder: (context, error, stackTrace) {
            print('Error displaying image: $error');
            return Container(
              width: double.infinity,
              height: 300,
              color: Colors.grey[200],
              child: const Center(
                child: Icon(Icons.error, size: 50, color: Colors.grey),
              ),
            );
          },
        ),
      );
    }

    // Carousel with loading indicator if more images are coming
    return Stack(
      children: [
        // Carousel slider
        CarouselSlider(
          items: imageWidgets,
          carouselController: _carouselController,
          options: CarouselOptions(
            height: 300,
            viewportFraction: 1.0,
            enableInfiniteScroll: imageWidgets.length > 1,
            autoPlay: imageWidgets.length > 1,
            autoPlayInterval: const Duration(seconds: 3),
            onPageChanged: (index, reason) {
              setState(() {
                _currentImageIndex = index;
              });
            },
          ),
        ),
        
        // Loading indicator if we're still loading more images
        if (isLoadingAllImages)
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
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            ),
          ),
          
        // Image indicators
        if (imageWidgets.length > 1)
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: imageWidgets.asMap().entries.map((entry) {
                return Container(
                  width: 8.0,
                  height: 8.0,
                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentImageIndex == entry.key
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  Future<double?> _showOfferDialog({double? initialValue}) async {
    return showDialog<double>(
      context: context,
      builder: (BuildContext context) => _OfferDialog(initialValue: initialValue),
    );
  }

  Future<void> _showReportDialog() async {
    final reasonController = TextEditingController();
    final descriptionController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text(
          'Report Product',
          style: TextStyle(fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What is wrong with this product?',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                items: [
                  'Inappropriate Content',
                  'Fake Product',
                  'Misleading Information',
                  'Other'
                ].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (value) {
                  reasonController.text = value ?? '';
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () async {
              if (reasonController.text.isNotEmpty && descriptionController.text.isNotEmpty) {
                try {
                  final authCookie = await _secureStorage.read(key: 'authCookie');
                  final response = await http.post(
                    Uri.parse('$serverUrl/api/reports/product'),
                    headers: {
                      'Content-Type': 'application/json',
                      'auth-cookie': authCookie ?? '',
                    },
                    body: json.encode({
                      'productId': widget.product['_id'],
                      'reason': reasonController.text,
                      'description': descriptionController.text,
                    }),
                  );
                  
                  if (response.statusCode == 201) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Report submitted successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    throw Exception('Failed to submit report');
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error submitting report'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading && productDetails == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Product Details'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          scrolledUnderElevation: 0, // Add this
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final product = productDetails ?? widget.product;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0, // Add this
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
        title: Text(product['name'] ?? 'Product Details', 
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag),
            onPressed: _showReportDialog,
            tooltip: 'Report Product',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image carousel
                  _buildImageCarousel(),

                  // Main content section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product name and status
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                product['name'] ?? 'Unknown Product',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${product['status']?.toUpperCase() ?? "AVAILABLE"}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Category tags - replace the existing tag section with this
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Text(
                                'Tags: ',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                                ),
                                child: Text(
                                  'Electronics',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.green.withOpacity(0.2)),
                                ),
                                child: Text(
                                  'Campus',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Price section
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Price: ',
                                  style: TextStyle(fontSize: 16),
                                ),
                                Text(
                                  '₹${product['price']?.toString() ?? "0"}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Seller details section with API data
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Seller Details',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ViewProfileScreen(
                                    userId: product['seller']?['_id'] ?? '',
                                  ),
                                ),
                              ),
                              child: Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 20,
                                          backgroundColor: Colors.grey[200],
                                          child: Icon(Icons.person, color: Colors.grey[400]),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              product['seller']?['userName'] ?? 'Unknown',
                                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                            ),
                                            if (sellerProfile != null) ...[
                                              Text(
                                                'Last online: ${_formatDateTime(sellerProfile!['lastSeen'])}',
                                                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                              ),
                                              Text(
                                                'Member since: ${_formatDateTime(sellerProfile!['createdAt'])}',
                                                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                              ),
                                              if (sellerProfile!['address'] != null)
                                                Text(
                                                  'Address: ${sellerProfile!['address']}',
                                                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                                ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        // Add Buyer Details if product is sold
                        if (product['status'] == 'sold' && product['buyer'] != null) ...[
                          const SizedBox(height: 24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Buyer Details',
                                style: TextStyle(fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ViewProfileScreen(
                                      userId: product['buyer']?['_id'] ?? '',
                                    ),
                                  ),
                                ),
                                child: Container(
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[50],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey[200]!),
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: Colors.grey[200],
                                        child: Icon(Icons.person, color: Colors.grey[400]),
                                      ),
                                      const SizedBox(width: 12),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            product['buyer']?['userName'] ?? 'Unknown',
                                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                                          ),
                                          Text(
                                            'Purchased on: ${_formatDateTime(product['soldAt'] ?? product['lastUpdatedAt'])}',
                                            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),

                        // Product timestamps
                        Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.withOpacity(0.1)),
                          ),
                          child: Column(
                            children: [
                              _buildTimeDetail('Posted on', _formatDateTime(product['createdAt'])),
                              const SizedBox(height: 8),
                              _buildTimeDetail('Last updated', _formatDateTime(product['lastUpdatedAt'])),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Description section
                        Text(
                          'About this item',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          product['description'] ?? 'No description available',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: Colors.grey[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: (widget.product['status']?.toLowerCase() != 'available' || 
                          widget.product['seller']?['_id'] == currentUserId ||
                          !widget.showOfferButton)
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _startChat,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'Chat with Seller',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            final offerPrice = await _showOfferDialog(
                              initialValue: currentOfferAmount,
                            );
                            
                            if (offerPrice != null) {
                              final authCookie = await _secureStorage.read(key: 'authCookie');
                              final response = await http.post(
                                Uri.parse('$serverUrl/api/products/${widget.product['_id']}/offers'),
                                headers: {
                                  'Content-Type': 'application/json',
                                  'auth-cookie': authCookie ?? '',
                                },
                                body: json.encode({
                                  'offerPrice': offerPrice,
                                }),
                              );
                              
                              if (response.statusCode == 200) {
                                setState(() {
                                  hasOffer = true;
                                  currentOfferAmount = offerPrice;
                                });
                                
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Offer ${hasOffer ? 'updated' : 'sent'} successfully'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } else {
                                final errorData = json.decode(response.body);
                                throw Exception(errorData['error'] ?? 'Failed to send offer');
                              }
                            }
                          } catch (e) {
                            print('Error making offer: $e');
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Error: Unable to make offer. Please try again.'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasOffer ? Colors.orange : Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          hasOffer ? 'Update Offer' : 'Make Offer',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTag(String text) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey[800],
        ),
      ),
    );
  }

  Widget _buildSellerDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'available':
        return Colors.green;
      case 'sold':
        return Colors.orange;
      case 'closed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final DateTime dateTime = DateTime.parse(date.toString());
      return DateFormat('MMM d, yyyy').format(dateTime);
    } catch (e) {
      return 'N/A';
    }
  }

  // Update helper method to include time
  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final DateTime date = DateTime.parse(dateTime.toString());
      return DateFormat('MMM d, yyyy • h:mm a').format(date);
    } catch (e) {
      return 'N/A';
    }
  }

  Future<void> _loadSellerProfile() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('$serverUrl/api/users/profile/${widget.product['seller']['_id']}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            sellerProfile = data['user'];
          });
        }
      }
    } catch (e) {
      print('Error loading seller profile: $e');
    }
  }
}

// Dialog for making offers
class _OfferDialog extends StatefulWidget {
  final double? initialValue;
  
  const _OfferDialog({Key? key, this.initialValue}) : super(key: key);

  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  final TextEditingController _controller = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!.toStringAsFixed(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Container(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Make an Offer",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              "Enter your offer price",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixText: "₹ ",
                hintText: "Amount",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.blue),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              autofocus: true,
            ),
            SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
                SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    final price = double.tryParse(_controller.text);
                    if (price != null) Navigator.of(context).pop(price);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text("Submit Offer"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
