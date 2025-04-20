import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:isolate';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:carousel_slider/carousel_controller.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'chat_screen.dart';
import '../services/product_cache_service.dart';

class ProductDetailsScreen extends StatefulWidget {
  final dynamic product;
  final bool showOfferButton;

  const ProductDetailsScreen({
    super.key,
    required this.product,
    this.showOfferButton = true, // Set default value to true
  });

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String currentUserName = '';
  String currentUserId = '';
  int _currentImageIndex = 0;

  // Use the correct carousel controller
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

  // For threading
  ReceivePort? _receivePort;
  Isolate? _isolate;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _setupImageLoading();
    _loadProductDetails();

    if (widget.product != null && widget.product['_id'] != null) {
      _checkExistingOffer();
    }
  }

  @override
  void dispose() {
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    super.dispose();
  }

  void _setupImageLoading() {
    _receivePort = ReceivePort();
    _receivePort!.listen((message) {
      if (message is Map && message.containsKey('type')) {
        if (message['type'] == 'imageLoaded' && message.containsKey('images')) {
          final List<Uint8List> loadedImages = List<Uint8List>.from(message['images']);

          if (mounted) {
            setState(() {
              productImages = loadedImages;
              isLoadingAllImages = false;
            });
          }
        }
      }
    });
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
    final cachedImages = await ProductCacheService.getCachedAllImages(widget.product['_id']);
    if (cachedImages != null && cachedImages.isNotEmpty) {
      setState(() {
        productImages = cachedImages;
      });
    } else if (productImages.isEmpty && widget.product['imageData'] != null) {
      // We have at least the main image from products tab
      setState(() {
        productImages = [widget.product['imageData']];
      });
    }

    // Get cached number of images
    final numImages = await ProductCacheService.getCachedNumImages(widget.product['_id']);
    if (numImages != null) {
      totalNumImages = numImages;
    }

    // Fetch fresh product data
    _fetchProductDetails();

    // Fetch all images if needed
    if (productImages.isEmpty || productImages.length < totalNumImages) {
      _fetchAllProductImages();
    }
  }

  Future<void> _fetchProductDetails() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/${widget.product['_id']}'),
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
          final lastCached = await ProductCacheService.getImageCacheTimestamp(widget.product['_id']);

          if (lastCached == null || (lastUpdated != null && lastUpdated.isAfter(lastCached))) {
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
      // Kill previous isolate if exists
      _isolate?.kill(priority: Isolate.immediate);

      // Spawn a new isolate
      _isolate = await Isolate.spawn(
        _isolateImagesFetcher,
        {
          'productId': widget.product['_id'],
          'sendPort': _receivePort!.sendPort,
          'authCookie': await _secureStorage.read(key: 'authCookie'),
        },
      );
    } catch (e) {
      print('Error setting up isolate: $e');
      _fetchAllProductImagesDirect();
    }
  }

  // Direct image fetching without isolate (fallback)
  Future<void> _fetchAllProductImagesDirect() async {
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/${widget.product['_id']}/images'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          List<Uint8List> loadedImages = [];
          final images = data['images'];

          for (var image in images) {
            if (image != null && image['data'] != null) {
              final String base64Str = image['data'];
              final Uint8List bytes = base64Decode(base64Str);
              loadedImages.add(bytes);
            }
          }

          // Cache images and number of images
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
    } catch (e) {
      print('Error fetching all images directly: $e');
      if (mounted) {
        setState(() {
          isLoadingAllImages = false;
        });
      }
    }
  }

  // Static method for isolate
  static void _isolateImagesFetcher(Map<String, dynamic> data) async {
    final String productId = data['productId'];
    final SendPort sendPort = data['sendPort'];
    final String? authCookie = data['authCookie'];

    try {
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/$productId/images'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          List<Uint8List> loadedImages = [];
          final images = data['images'];

          for (var image in images) {
            if (image != null && image['data'] != null) {
              final String base64Str = image['data'];
              final Uint8List bytes = base64Decode(base64Str);
              loadedImages.add(bytes);
            }
          }

          // Tell the main isolate about our loaded images
          sendPort.send({
            'type': 'imageLoaded',
            'images': loadedImages,
          });
        }
      }
    } catch (e) {
      print('Error in isolate: $e');
      sendPort.send({'type': 'error'});
    }
  }

  Future<void> _checkExistingOffer() async {
    if (widget.product == null || widget.product['_id'] == null) {
      setState(() {
        isCheckingOffer = false;
      });
      return;
    }

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/${widget.product['_id']}/check-offer'),
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
    if (widget.product['seller']?['_id'] == null) return;

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');

      // First, get or create the conversation
      final conversationResponse = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'participantId': widget.product['seller']['_id'],
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
              partnerNames: widget.product['seller']['userName'],
              partnerId: widget.product['seller']['_id'],
              initialProduct: initialProduct,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error starting chat: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting chat. Please try again.')),
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
              ? CircularProgressIndicator()
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
              child: Center(
                child: CircularProgressIndicator(),
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
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
      builder: (BuildContext context) => OfferDialog(initialValue: initialValue),
    );
  }

  Future<void> _showReportDialog() async {
    final reasonController = TextEditingController();
    final descriptionController = TextEditingController();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Report Product'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Please provide more details',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (reasonController.text.isNotEmpty && descriptionController.text.isNotEmpty) {
                try {
                  final authCookie = await _secureStorage.read(key: 'authCookie');
                  final response = await http.post(
                    Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/reports/product'),
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
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Submit'),
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
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final product = productDetails ?? widget.product;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(product['name'] ?? 'Product Details'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
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

                  // Product details section
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name and Price section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                product['name'] ?? 'Unknown Product',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              '₹${product['price']?.toString() ?? '0'}',
                              style: const TextStyle(
                                fontSize: 22,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Category and Status
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                product['category']?.toString().toUpperCase() ?? 'UNKNOWN',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _getStatusColor(product['status']).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                product['status']?.toUpperCase() ?? 'UNKNOWN',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _getStatusColor(product['status']),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Seller info
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
                                  'Seller',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  product['seller']?['userName'] ?? 'Unknown',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Description section
                        const Text(
                          'Description',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          product['description'] ?? 'No description available',
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.5,
                          ),
                        ),

                        // Sold Information section if product is sold
                        if (product['status'] == 'sold') ...[
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange.withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.sell, color: Colors.orange[700], size: 20),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Sold Information',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Sold Price: ₹${product['transactionPrice']?.toString() ?? product['price']?.toString() ?? '0'}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Sold Date: ${_formatDate(product['transactionDate'])}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Last updated info
                        Row(
                          children: [
                            Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text(
                              'Last Updated: ${_formatDate(product['lastUpdatedAt'])}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
        ],
      ),
      bottomNavigationBar: widget.product['status'] == 'sold' || widget.product['user']?['_id'] == currentUserId
          ? null
          : widget.showOfferButton // Only show if showOfferButton is true
              ? Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        spreadRadius: 1,
                        blurRadius: 5,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: isLoading ? null : () async {
                      try {
                        final offerPrice = await _showOfferDialog(
                          initialValue: currentOfferAmount,
                        );

                        if (offerPrice != null) {
                          final authCookie = await _secureStorage.read(key: 'authCookie');

                          final response = await http.post(
                            Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/${widget.product['_id']}/offers'),
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
                          SnackBar(
                            content: Text('Error: Unable to make offer. Please try again.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: hasOffer ? Colors.orange : Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      hasOffer ? 'Edit Offer (₹${currentOfferAmount?.toStringAsFixed(0)})' : 'Make Offer',
                      style: const TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                )
              : null,
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
}

// Dialog for making offers
class OfferDialog extends StatefulWidget {
  final double? initialValue;
  const OfferDialog({Key? key, this.initialValue}) : super(key: key);

  @override
  State<OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<OfferDialog> {
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
    return AlertDialog(
      title: const Text("Your Offer Price"),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          hintText: "Enter Offer Price",
          prefixText: "₹ ",
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          onPressed: () {
            final price = double.tryParse(_controller.text);
            if (price != null) Navigator.of(context).pop(price);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text("Submit"),
        ),
      ],
    );
  }
}
