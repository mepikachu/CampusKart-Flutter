import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_parser/http_parser.dart';


class SellTab extends StatefulWidget {
  const SellTab({Key? key}) : super(key: key);

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

  // Picks multiple images using image_picker
  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile>? pickedFiles = await picker.pickMultiImage();
    if (pickedFiles != null && pickedFiles.isNotEmpty) {
      setState(() {
        _images = pickedFiles.map((e) => File(e.path)).toList();
      });
    }
  }

  // Submits the product using a multipart POST request
  Future<void> _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one image")),
      );
      return;
    }
    setState(() {
      _isLoading = true;
    });

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Not authenticated")),
        );
        return;
      }
      final uri = Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products');
      var request = http.MultipartRequest('POST', uri);
      
      // Set the auth cookie header; do not manually set Content-Type
      request.headers['auth-cookie'] = authCookie;

      // Add form fields
      request.fields['name'] = _nameController.text.trim();
      request.fields['description'] = _descriptionController.text.trim();
      request.fields['price'] = _priceController.text.trim();
      request.fields['category'] = _selectedCategory;

      // Attach images
      for (File image in _images) {
        var stream = http.ByteStream(image.openRead());
        var length = await image.length();
        var multipartFile = http.MultipartFile(
          'images',
          stream,
          length,
          filename: image.path.split('/').last,
          contentType: MediaType('image', 'jpeg'), // adjust if not JPEG
        );
        request.files.add(multipartFile);
      }

      // Send the request and capture the response
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      // Debug logging
      print("Response status: ${response.statusCode}");
      print("Response body: $responseBody");

      // Attempt to decode the response as JSON.
      // If responseBody starts with '<html>', it indicates an error page.
      if (responseBody.startsWith("<html>")) {
        throw Exception("Server returned an HTML error page");
      }

      final resData = json.decode(responseBody);

      if (response.statusCode == 201 && resData['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Product posted successfully")),
        );
        // Clear the form fields on success
        _nameController.clear();
        _descriptionController.clear();
        _priceController.clear();
        setState(() {
          _images.clear();
          _selectedCategory = _categories.first;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(resData['error'] ?? "Product submission failed")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }


  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Sell Product"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Product Name
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Product Name",
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    (value == null || value.isEmpty) ? "Enter product name" : null,
              ),
              const SizedBox(height: 16),
              // Description
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: "Description",
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (value) =>
                    (value == null || value.isEmpty) ? "Enter product description" : null,
              ),
              const SizedBox(height: 16),
              // Price
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: "Price",
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) =>
                    (value == null || value.isEmpty) ? "Enter product price" : null,
              ),
              const SizedBox(height: 16),
              // Category Dropdown
              DropdownButtonFormField<String>(
                value: _selectedCategory,
                items: _categories.map((cat) {
                  return DropdownMenuItem(
                    value: cat,
                    child: Text(cat[0].toUpperCase() + cat.substring(1)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  }
                },
                decoration: const InputDecoration(
                  labelText: "Category",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              // Image Picker
              ElevatedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.image),
                label: const Text("Select Images"),
              ),
              const SizedBox(height: 8),
              _images.isNotEmpty
                  ? SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _images.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Image.file(
                              _images[index],
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                          );
                        },
                      ),
                    )
                  : const Text("No images selected"),
              const SizedBox(height: 24),
              // Submit Button
              _isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitProduct,
                        child: const Text("Submit Product"),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
