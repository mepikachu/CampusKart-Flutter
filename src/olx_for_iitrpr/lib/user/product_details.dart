import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:http/http.dart' as http;
import 'chats.dart';

class ProductDetailsScreen extends StatefulWidget {
  final dynamic product;
  
  const ProductDetailsScreen({super.key, required this.product});

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  String currentUserName = '';
  int _currentImageIndex = 0;
  final CarouselSliderController _carouselController = CarouselSliderController();
  bool hasOffer = false;
  double? currentOfferAmount;
  bool isCheckingOffer = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserName();
    _checkExistingOffer();
  }

  Future<void> _loadCurrentUserName() async {
    String? name = await _secureStorage.read(key: 'userName');
    if (mounted) {
      setState(() {
        currentUserName = name ?? '';
      });
    }
  }

  Future<void> _checkExistingOffer() async {
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
            hasOffer = data['hasOffer'] ?? false;
            currentOfferAmount = data['offerAmount']?.toDouble();
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

    final productPreview = {
      'type': 'product_reply', // marker to render this as a product reply message
      'productId': widget.product['_id'],
      'productName': widget.product['name'],
      'price': widget.product['price'],
      'image': (widget.product['images'] != null &&
              widget.product['images'].isNotEmpty)
          ? widget.product['images'][0]['data']
          : null,
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          conversationId: '', // empty means new conversation
          partnerNames: widget.product['seller']['userName'],
          sellerId: widget.product['seller']['_id'],
          productPreview: productPreview, // pass product preview data
        ),
      ),
    );
  }

  List<Widget> _buildImageSlides() {
    final List<dynamic> images = widget.product['images'] ?? [];
    return images.map<Widget>((image) {
      if (image != null && image['data'] != null) {
        try {
          final imageBytes = base64Decode(image['data']);
          return Container(
            width: double.infinity,
            child: Image.memory(
              imageBytes,
              fit: BoxFit.cover,
            ),
          );
        } catch (e) {
          return const Center(child: Icon(Icons.error));
        }
      }
      return const Center(child: Icon(Icons.image_not_supported));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final images = _buildImageSlides();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      // Add bottom padding to account for the fixed buttons
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (images.isNotEmpty)
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CarouselSlider(
                          carouselController: _carouselController,
                          items: images,
                          options: CarouselOptions(
                            height: 300,
                            viewportFraction: 1.0,
                            enableInfiniteScroll: false,
                            onPageChanged: (index, reason) {
                              setState(() {
                                _currentImageIndex = index;
                              });
                            },
                          ),
                        ),
                        // Left Arrow (show only if not first image)
                        if (_currentImageIndex > 0)
                          Positioned(
                            left: 10,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.5),
                                  width: 1,
                                ),
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_back_ios,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: () => _carouselController.previousPage(),
                              ),
                            ),
                          ),
                        // Right Arrow (show only if not last image)
                        if (_currentImageIndex < images.length - 1)
                          Positioned(
                            right: 10,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.5),
                                  width: 1,
                                ),
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.arrow_forward_ios,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                onPressed: () => _carouselController.nextPage(),
                              ),
                            ),
                          ),
                        // Pagination dots with background
                        Positioned(
                          bottom: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.5),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: images.asMap().entries.map((entry) {
                                return Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.5),
                                      width: 1,
                                    ),
                                    color: Colors.white.withOpacity(
                                      _currentImageIndex == entry.key ? 0.9 : 0.4
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Product Name
                        Text(
                          widget.product['name'] ?? 'Unknown Product',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        
                        // Price
                        Text(
                          '₹${widget.product['price']?.toString() ?? '0'}',
                          style: const TextStyle(
                            fontSize: 20,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Seller Info
                        Text(
                          'Seller: ${widget.product['seller']?['userName'] ?? 'Unknown'}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Description
                        const Text(
                          'Description:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.product['description'] ?? 'No description available',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Fixed buttons at bottom
          if (widget.product['seller']['userName'] == currentUserName)
            _buildSellerActions()
          else
            _buildBottomActions(),
        ],
      ),
    );
  }

  Widget _buildSellerActions() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                // Add seller-specific actions here
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('Manage Listing'),
            ),
          ),
        ],
      ),
    );
  }

  Future<double?> _showOfferDialog({double? initialValue}) async {
    return showDialog<double>(
      context: context,
      builder: (BuildContext context) => OfferDialog(initialValue: initialValue),
    );
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: isCheckingOffer ? null : () async {
                final offerPrice = await _showOfferDialog(
                  initialValue: currentOfferAmount,
                );
                if (offerPrice != null) {
                  final authCookie = await _secureStorage.read(key: 'authCookie');
                  final response = await http.post(
                    Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/offers'),
                    headers: {
                      'Content-Type': 'application/json',
                      'auth-cookie': authCookie ?? '',
                    },
                    body: json.encode({
                      'productId': widget.product['_id'],
                      'offerPrice': offerPrice,
                    }),
                  );

                  if (response.statusCode == 200) {
                    final data = json.decode(response.body);
                    setState(() {
                      hasOffer = data['hasOffer'] ?? false;
                      currentOfferAmount = offerPrice;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(hasOffer ? 'Offer updated successfully' : 'Offer sent successfully'),
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: hasOffer ? Colors.orange : Colors.green,
              ),
              child: Text(
                hasOffer ? 'Edit Offer' : 'Make Offer',
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _startChat,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
              ),
              child: const Text(
                'Chat with Seller',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OfferDialog extends StatefulWidget {
  final double? initialValue;
  const OfferDialog({Key? key, this.initialValue}) : super(key: key);

  @override
  _OfferDialogState createState() => _OfferDialogState();
}

class _OfferDialogState extends State<OfferDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Your Offer Price"),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(hintText: "Enter Offer Price"),
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
          child: const Text("Submit"),
        ),
      ],
    );
  }
}