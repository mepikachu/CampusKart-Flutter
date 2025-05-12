import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'edit_product_screen.dart';
import '../services/product_cache_service.dart';
import 'server.dart';

class SellerOfferManagementScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  const SellerOfferManagementScreen({super.key, required this.product});

  @override
  State<SellerOfferManagementScreen> createState() => _SellerOfferManagementScreenState();
}

class _SellerOfferManagementScreenState extends State<SellerOfferManagementScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  List<dynamic> offers = [];
  bool isLoading = true;
  String errorMessage = '';
  
  // Image caching fields
  final Map<String, List<Uint8List>> _imageCache = {};
  final Set<String> _loadingImages = {};
  bool _isLoadingImages = true;
  int _totalExpectedImages = 1;

  @override
  void initState() {
    super.initState();
    fetchOffers();
    _loadCachedImages();
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
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offer accepted. Product marked as sold.')),
          );
          
          // Navigate back after a short delay
          Future.delayed(const Duration(seconds: 2), () {
            Navigator.of(context).pop();
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offer rejected successfully')),
          );
          fetchOffers(); // Refresh the offers list
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to $action offer');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
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
            scrolledUnderElevation: 0, // Prevents color change on scroll
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
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.black,
              tabs: [
                Tab(text: 'Details'),
                Tab(text: 'Offers'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImageCarousel(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.product['name'] ?? 'Unknown Product',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: widget.product['status'] == 'sold' 
                                    ? Colors.orange.shade50 
                                    : Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  (widget.product['status'] ?? 'AVAILABLE').toUpperCase(),
                                  style: TextStyle(
                                    color: widget.product['status'] == 'sold' 
                                      ? Colors.orange.shade700 
                                      : Colors.green.shade700,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),

                          Text(
                            '₹${widget.product['price']?.toString() ?? '0'}',
                            style: TextStyle(
                              fontSize: 24,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 24),

                          // Tags section with category
                          Text(
                            'Tags:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                          SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              _buildTag('For Sale'),
                              _buildTag('Campus'),
                              if (widget.product['category'] != null) 
                                _buildTag(widget.product['category']),
                            ],
                          ),
                          SizedBox(height: 24),

                          // Posted date in blue box
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue.shade100),
                            ),
                            child: Text(
                              'Posted on ${_formatDateWithTime(widget.product['createdAt'])}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(height: 24),

                          Text(
                            'About This Product',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            widget.product['description'] ?? 'No description available',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey[800],
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _buildOffersList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTag(String text) {
    return Container(
      margin: EdgeInsets.only(right: 8, bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        text[0].toUpperCase() + text.substring(1),
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }

  String _formatDateWithTime(String? dateString) {
    if (dateString == null) return 'Unknown date';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
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
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          title: Text(
                            '₹${offer['offerPrice']}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            'From: ${offer['buyer']?['userName'] ?? 'Unknown'}\n'
                            'Date: ${DateTime.parse(offer['createdAt']).toString().split('.')[0]}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.check, color: Colors.white),
                                label: const Text('Accept'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                                onPressed: () => _showConfirmationDialog(
                                  'Accept Offer',
                                  'Are you sure you want to accept this offer? This will mark the product as sold.',
                                  () => _handleOfferAction(offer['_id'], 'accept'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.clear, color: Colors.white),
                                label: const Text('Reject'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                onPressed: () => _showConfirmationDialog(
                                  'Reject Offer',
                                  'Are you sure you want to reject this offer?',
                                  () => _handleOfferAction(offer['_id'], 'decline'),
                                ),
                              ),
                            ],
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  );
  }

  Future<void> _showConfirmationDialog(String title, String message, Function onConfirm) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Confirm'),
              onPressed: () {
                Navigator.of(context).pop();
                onConfirm();
              },
            ),
          ],
        );
      },
    );
  }
}
