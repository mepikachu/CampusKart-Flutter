import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product['name']);
    _descriptionController = TextEditingController(text: widget.product['description']);
  }

  Future<void> _deleteProduct() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('This action cannot be undone. Delete product?'),
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

    setState(() => _isProcessing = true);
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) throw Exception('Authentication required');

      final response = await http.delete(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/${widget.product['_id']}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
          'X-Requested-With': 'XMLHttpRequest',
        },
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.pop(context, {'deleted': true});
      } else {
        _handleErrorResponse(response);
      }
    } catch (e) {
      _showSnackbar('Delete failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isProcessing = true);

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      if (authCookie == null) throw Exception('Authentication required');

      final response = await http.put(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/products/${widget.product['_id']}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: json.encode({
          'name': _nameController.text,
          'description': _descriptionController.text,
        }),
      );

      if (response.statusCode == 200) {
        if (!mounted) return;
        Navigator.pop(context, {
          'updated': true,
          'name': _nameController.text,
          'description': _descriptionController.text
        });
      } else {
        _handleErrorResponse(response);
      }
    } catch (e) {
      _showSnackbar('Update failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _handleErrorResponse(http.Response response) {
    try {
      final errorData = jsonDecode(response.body);
      _showSnackbar(errorData['error'] ?? 'Unknown error occurred');
    } catch (_) {
      _showSnackbar('Server responded with status ${response.statusCode}');
    }
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
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
            icon: Icon(Icons.delete, color: _isProcessing ? Colors.grey : Colors.red),
            onPressed: _isProcessing ? null : _deleteProduct,
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Product Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value?.isEmpty ?? true 
                        ? 'Name cannot be empty'
                        : null,
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 5,
                    validator: (value) => value?.isEmpty ?? true 
                        ? 'Description cannot be empty'
                        : null,
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    icon: _isProcessing 
                        ? const SizedBox.shrink()
                        : const Icon(Icons.save),
                    label: _isProcessing
                        ? const CircularProgressIndicator()
                        : const Text('Save Changes'),
                    onPressed: _isProcessing ? null : _saveChanges,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
