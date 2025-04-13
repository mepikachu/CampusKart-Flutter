import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:http/http.dart' as http;
import 'chat_screen.dart';

class LostItemDetailsScreen extends StatefulWidget {
  final dynamic item;

  const LostItemDetailsScreen({
    Key? key, 
    required this.item,
  }) : super(key: key);

  @override
  State<LostItemDetailsScreen> createState() => _LostItemDetailsScreenState();
}

class _LostItemDetailsScreenState extends State<LostItemDetailsScreen> {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  int _currentImageIndex = 0;
  final CarouselSliderController _carouselController = CarouselSliderController();
  String currentUserName = '';
  String currentUserId = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
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

  void _startChat() async {
    if (widget.item['user']?['_id'] == null) return;
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final conversationResponse = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/conversations'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'participantId': widget.item['user']['_id'],
        }),
      );
      
      if (conversationResponse.statusCode == 200) {
        final conversationData = json.decode(conversationResponse.body);
        final conversationId = conversationData['conversation']['_id'];
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              partnerNames: widget.item['user']['userName'],
              partnerId: widget.item['user']['_id'],
              initialProduct: null,
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error starting chat. Please try again.')),
      );
    }
  }

  List<Widget> _buildImageSlides() {
    final List images = widget.item['images'] ?? [];
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
        title: const Text('Lost Item Details'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
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
                        if (_currentImageIndex > 0)
                          Positioned(
                            left: 10,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                                onPressed: () => _carouselController.previousPage(),
                              ),
                            ),
                          ),
                        if (_currentImageIndex < images.length - 1)
                          Positioned(
                            right: 10,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
                                onPressed: () => _carouselController.nextPage(),
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
                        Text(
                          widget.item['name'] ?? 'Unknown Item',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: widget.item['status'] == 'found' 
                                ? Colors.green[100] 
                                : Colors.orange[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.item['status']?.toUpperCase() ?? 'LOST',
                            style: TextStyle(
                              color: widget.item['status'] == 'found' 
                                  ? Colors.green[700] 
                                  : Colors.orange[700],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Posted by: ${widget.item['user']?['userName'] ?? 'Unknown'}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Description:',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.item['description'] ?? 'No description available',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _startChat,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                ),
                child: const Text(
                  'Chat with Owner',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
