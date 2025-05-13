import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';
import 'server.dart';
import '../utils/image_processor.dart';

class SellTab extends StatefulWidget {
  const SellTab({super.key});

  @override
  State<SellTab> createState() => _SellTabState();
}

class _SellTabState extends State<SellTab> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  String _selectedCategory = 'electronics';
  List<File> _images = [];
  bool _isLoading = false;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  final List<String> _categories = ['electronics', 'furniture', 'books', 'clothing', 'others'];

  // Colors from tab_sell
  static const primaryColor = Color(0xFF1A73E8);
  static const surfaceColor = Color(0xFFFFFFFF); // Pure white
  static const backgroundColor = Color(0xFFFFFFFF); // Pure white
  static const outlineColor = Color(0xFFE1E3E6);
  static const textPrimaryColor = Color(0xFF202124);
  static const textSecondaryColor = Color(0xFF5F6368);

  // Picks multiple images using image_picker
  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile>? pickedFiles = await picker.pickMultiImage();
    
    if (pickedFiles != null && pickedFiles.isNotEmpty) {
      setState(() {
        _images.addAll(pickedFiles.map((xfile) => File(xfile.path)));
        if (_images.length > 5) {
          _images = _images.sublist(0, 5); // Limit to 5 images
          _showMessage(error: 'Maximum 5 images allowed');
        }
      });
    }
  }

  // Submits the product using a multipart POST request
  Future<void> _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (_images.isEmpty) {
      _showMessage(error: "Please select at least one image");
      return;
    }
    setState(() {
      _isLoading = true;
    });

    try {
      // Compress images before upload
      final compressedImages = await ImageProcessor.compressImages(_images);
      
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) {
        _showMessage(error: "Not authenticated");
        return;
      }
      final uri = Uri.parse('$serverUrl/api/products');
      var request = http.MultipartRequest('POST', uri);
      request.headers['auth-cookie'] = authCookie;

      request.fields['name'] = _nameController.text.trim();
      request.fields['description'] = _descriptionController.text.trim();
      request.fields['price'] = _priceController.text.trim();
      request.fields['category'] = _selectedCategory;

      for (File image in compressedImages) {
        var stream = http.ByteStream(image.openRead());
        var length = await image.length();
        var multipartFile = http.MultipartFile(
          'images',
          stream,
          length,
          filename: image.path.split('/').last,
          contentType: MediaType('image', 'jpeg'),
        );
        request.files.add(multipartFile);
      }

      // Send the request and capture the response
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 201) {
        final resData = json.decode(responseBody);
        if (resData['success'] == true) {
          _showMessage(success: "Product posted successfully");
          
          // Clear form fields on success
          _nameController.clear();
          _descriptionController.clear();
          _priceController.clear();
          setState(() {
            _images.clear();
            _selectedCategory = _categories.first;
          });
        } else {
          _showMessage(error: resData['error'] ?? "Product submission failed");
        }
      } else {
        _showMessage(error: "Server error: ${response.statusCode}");
      }
    } catch (e) {
      _showMessage(error: "Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Add these state variables
  String? errorMessage;
  String? successMessage;
  Timer? _messageTimer;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  // Add helper method
  void _showMessage({String? error, String? success}) {
    _messageTimer?.cancel();
    setState(() {
      errorMessage = error;
      successMessage = success;
    });
    _messageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          errorMessage = null;
          successMessage = null;
        });
      }
    });
  }

  Widget _buildImagePreviews() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: outlineColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Product Images',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textPrimaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add up to 5 images',
            style: TextStyle(
              fontSize: 14,
              color: textSecondaryColor,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            height: 120,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length + (_images.length < 5 ? 1 : 0),
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (oldIndex < _images.length && newIndex <= _images.length) {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final File item = _images.removeAt(oldIndex);
                    _images.insert(newIndex, item);
                  }
                });
              },
              itemBuilder: (context, index) {
                if (index == _images.length) {
                  return Container(
                    key: const ValueKey('add_image'),
                    width: 120,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: outlineColor),
                    ),
                    child: InkWell(
                      onTap: _pickImages,
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: surfaceColor,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.add_photo_alternate_rounded,
                              color: primaryColor,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add Image',
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return Container(
                  key: ValueKey(_images[index]),
                  width: 120,
                  margin: const EdgeInsets.only(right: 12),
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _images[index],
                            height: 120,
                            width: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => setState(() => _images.removeAt(index)),
                              customBorder: const CircleBorder(),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (index == 0)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'MAIN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Pure white background
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Sell Product', style: TextStyle(color: Colors.black)),
        leading: Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.shade100,
          ),
          child: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.black),
            padding: EdgeInsets.zero,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: Column(
        children: [
          // Add message boxes at the top
          if (errorMessage != null)
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
                      errorMessage!,
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
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Center(child: _buildImagePreviews()),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: "Product Name",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.white, // Changed to pure white
                        ),
                        validator: (value) => 
                            (value?.isEmpty ?? true) ? "Enter product name" : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: InputDecoration(
                          labelText: "Description",
                          alignLabelWithHint: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.white, // Changed to pure white
                        ),
                        maxLines: null,
                        minLines: 3,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        validator: (value) => 
                            (value?.isEmpty ?? true) ? "Enter description" : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _priceController,
                              decoration: InputDecoration(
                                labelText: "Price",
                                prefixText: '₹ ',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.white, // Changed to pure white
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) => 
                                  (value?.isEmpty ?? true) ? "Enter price" : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              value: _selectedCategory,
                              decoration: InputDecoration(
                                labelText: "Category",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Colors.white, // Changed to pure white
                              ),
                              items: _categories.map((cat) {
                                return DropdownMenuItem(
                                  value: cat,
                                  child: Text(
                                    cat[0].toUpperCase() + cat.substring(1),
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _selectedCategory = value);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      // List for Sale button at the bottom of content
                      Container(
                        width: double.infinity,
                        height: 54,
                        margin: const EdgeInsets.only(bottom: 16),
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submitProduct,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E7D32),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'List for Sale',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
