import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';

class EditProductScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  const EditProductScreen({Key? key, required this.product}) : super(key: key);

  @override
  State<EditProductScreen> createState() => _EditProductScreenState();
}

class _EditProductScreenState extends State<EditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _priceController;
  late String _selectedCategory;
  List<File> _images = [];
  List<dynamic> _existingImages = [];
  bool _isLoading = false;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  final List<String> _categories = ['electronics', 'furniture', 'books', 'clothing', 'others'];

  // Colors from tab_sell
  static const primaryColor = Color(0xFF1A73E8);
  static const surfaceColor = Color(0xFFFFFFFF);
  static const backgroundColor = Color(0xFFFFFFFF);
  static const outlineColor = Color(0xFFE1E3E6);
  static const textPrimaryColor = Color(0xFF202124);
  static const textSecondaryColor = Color(0xFF5F6368);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product['name']);
    _descriptionController = TextEditingController(text: widget.product['description']);
    _priceController = TextEditingController(text: widget.product['price'].toString());
    _selectedCategory = widget.product['category'];
    if (widget.product['images'] != null) {
      _existingImages = List.from(widget.product['images']);
    }
  }

  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile>? pickedFiles = await picker.pickMultiImage();
    
    if (pickedFiles != null && pickedFiles.isNotEmpty) {
      setState(() {
        _images.addAll(pickedFiles.map((xfile) => File(xfile.path)));
        if (_images.length + _existingImages.length > 5) {
          _images = _images.sublist(0, 5 - _existingImages.length);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum 5 images allowed')),
          );
        }
      });
    }
  }

  Future<void> _deleteProduct() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this product? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) throw Exception('Authentication required');

      final response = await http.delete(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/${widget.product['_id']}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.of(context).pop({'refresh': true});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product deleted successfully')),
        );
      } else {
        throw Exception('Failed to delete product');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProduct() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) throw Exception('Authentication required');

      final request = http.MultipartRequest(
        'PUT',
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/${widget.product['_id']}'),
      );

      request.headers['auth-cookie'] = authCookie;
      
      // Add form fields
      request.fields['name'] = _nameController.text.trim();
      request.fields['description'] = _descriptionController.text.trim();
      request.fields['price'] = _priceController.text.trim();
      request.fields['category'] = _selectedCategory;
      request.fields['clearOffers'] = 'true'; // Add this line to clear offers
      
      // Add existing images that weren't deleted
      if (_existingImages.isNotEmpty) {
        request.fields['existingImages'] = json.encode(_existingImages);
      }

      // Add new images
      for (var image in _images) {
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

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final responseData = json.decode(responseBody);

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.of(context).pop({'refresh': true});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product updated successfully. All existing offers have been cleared.')),
        );
      } else {
        throw Exception(responseData['error'] ?? 'Failed to update product');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
          const Text(
            'Product Images',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: textPrimaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add up to ${5 - _existingImages.length} more images',
            style: const TextStyle(
              fontSize: 14,
              color: textSecondaryColor,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // Display existing images
                ..._existingImages.map((imageData) {
                  return Container(
                    width: 120,
                    margin: const EdgeInsets.only(right: 12),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: imageData['data'] != null 
                            ? Image.memory(
                                base64Decode(imageData['data']),
                                height: 120,
                                width: 120,
                                fit: BoxFit.cover,
                              )
                            : Container(color: Colors.grey),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white, size: 16),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() => _existingImages.remove(imageData));
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),

                // Display newly picked images
                ..._images.map((file) {
                  return Container(
                    width: 120,
                    margin: const EdgeInsets.only(right: 12),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            file,
                            height: 120,
                            width: 120,
                            fit: BoxFit.cover,
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
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white, size: 16),
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() => _images.remove(file));
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),

                // Add image button
                if (_existingImages.length + _images.length < 5)
                  Container(
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
                        children: const [
                          Icon(
                            Icons.add_photo_alternate_rounded,
                            color: primaryColor,
                            size: 28,
                          ),
                          SizedBox(height: 8),
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
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Product'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            color: Colors.red,
            onPressed: _isLoading ? null : _deleteProduct,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildImagePreviews(),
                const SizedBox(height: 24),
                // Read-only product name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: "Product Name",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  enabled: false, // Make it read-only
                ),
                const SizedBox(height: 16),
                // Editable description
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: "Description",
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  maxLines: 3,
                  validator: (value) => 
                      (value?.isEmpty ?? true) ? "Enter description" : null,
                ),
                const SizedBox(height: 16),
                // Editable price and read-only category
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
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) => 
                            (value?.isEmpty ?? true) ? "Enter price" : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        initialValue: _selectedCategory[0].toUpperCase() + _selectedCategory.substring(1),
                        decoration: InputDecoration(
                          labelText: "Category",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        enabled: false, // Make it read-only
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  height: 54,
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ElevatedButton(
                    onPressed: _isLoading || _existingImages.isEmpty ? null : _updateProduct,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _existingImages.isEmpty 
                                ? 'At least one image required'
                                : 'Save Changes',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }
}
