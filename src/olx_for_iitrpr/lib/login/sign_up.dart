import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _nameController = TextEditingController(); // optional, not sent to backend here
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _zipCodeController = TextEditingController();

  final _secureStorage = const FlutterSecureStorage();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  // New fields for profile picture and volunteer registration
  File? _profilePicture;
  bool _registerAsVolunteer = false;

  Future<void> _pickProfilePicture() async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _profilePicture = File(pickedFile.path);
      });
    }
  }

  Map<String, dynamic> _getAddress() {
    return {
      'street': _streetController.text,
      'city': _cityController.text,
      'state': _stateController.text,
      'zipCode': _zipCodeController.text,
      'country': 'India'
    };
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      _showErrorDialog("Passwords do not match");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Use a multipart request to send both fields and an image if provided.
      final uri = Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/register');
      final request = http.MultipartRequest('POST', uri);

      request.fields['userName'] = _userNameController.text;
      request.fields['email'] = _emailController.text;
      request.fields['phone'] = _phoneController.text;
      request.fields['password'] = _passwordController.text;
      request.fields['address'] = json.encode(_getAddress());
      // Set role: if volunteer was selected then role will be 'volunteer'
      request.fields['role'] = _registerAsVolunteer ? 'volunteer' : 'user';

      if (_profilePicture != null) {
        final stream = http.ByteStream(_profilePicture!.openRead());
        final length = await _profilePicture!.length();
        final multipartFile = http.MultipartFile(
          'profilePicture',
          stream,
          length,
          filename: _profilePicture!.path.split('/').last,
          contentType: MediaType('image', 'jpeg'), // adjust if needed
        );
        request.files.add(multipartFile);
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 15));
      final responseBody = await streamedResponse.stream.bytesToString();
      final responseData = json.decode(responseBody);
      
      if (streamedResponse.statusCode == 201 && responseData['success'] == true) {
        final authCookie = responseData['authCookie'];
        await _secureStorage.write(key: 'authCookie', value: authCookie);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('identifier', _emailController.text);

        // For simplicity, always navigate to user home.
        // Volunteer registrations will require admin approval.
        Navigator.pushReplacementNamed(context, '/user_home');
      } else {
        _showErrorDialog(responseData['error'] ?? 'Signup failed');
      }
    } on TimeoutException {
      _showErrorDialog("Connection timeout");
    } on http.ClientException {
      _showErrorDialog("Network error");
    } catch (e) {
      _showErrorDialog("An error occurred. Please try again later.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _userNameController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Plain white background
      appBar: AppBar(title: const Text("Sign Up")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildUserNameField(),
                const SizedBox(height: 20),
                _buildNameField(),
                const SizedBox(height: 20),
                _buildEmailField(),
                const SizedBox(height: 20),
                _buildPhoneField(),
                const SizedBox(height: 20),
                _buildPasswordField(),
                const SizedBox(height: 20),
                _buildConfirmPasswordField(),
                const SizedBox(height: 20),
                _buildAddressSection(),
                const SizedBox(height: 20),
                // Add an option to pick a profile picture
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickProfilePicture,
                      icon: const Icon(Icons.image),
                      label: const Text("Pick Profile Picture"),
                    ),
                    const SizedBox(width: 16),
                    _profilePicture != null
                        ? const Text("Image Selected")
                        : const Text("No image"),
                  ],
                ),
                const SizedBox(height: 20),
                // Option to register as volunteer
                Row(
                  children: [
                    Checkbox(
                      value: _registerAsVolunteer,
                      onChanged: (v) {
                        setState(() {
                          _registerAsVolunteer = v ?? false;
                        });
                      },
                    ),
                    const Text("Register as Volunteer"),
                  ],
                ),
                const SizedBox(height: 30),
                _buildSignUpButton(),
                const SizedBox(height: 16),
                _buildLoginLink(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserNameField() {
    return TextFormField(
      controller: _userNameController,
      decoration: const InputDecoration(
        labelText: "Username",
        prefixIcon: Icon(Icons.person),
        hintText: "Unique username (3-30 characters)",
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return "Username is required";
        if (value.length < 3 || value.length > 30) {
          return "Must be 3-30 characters";
        }
        return null;
      },
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: "Full Name",
        prefixIcon: Icon(Icons.badge),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return "Full name is required";
        return null;
      },
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: "Email",
        prefixIcon: Icon(Icons.email),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return "Email is required";
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
          return "Invalid email format";
        }
        return null;
      },
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(
        labelText: "Phone Number",
        prefixIcon: Icon(Icons.phone),
        hintText: "10-digit mobile number",
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return "Phone number is required";
        if (!RegExp(r'^[0-9]{10}$').hasMatch(value)) {
          return "Invalid phone number";
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: "Password",
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return "Password is required";
        if (value.length < 6) return "Minimum 6 characters required";
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      decoration: InputDecoration(
        labelText: "Confirm Password",
        prefixIcon: const Icon(Icons.lock),
        suffixIcon: IconButton(
          icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return "Please confirm password";
        if (value != _passwordController.text) return "Passwords don't match";
        return null;
      },
    );
  }

  Widget _buildAddressSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Address Details",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _streetController,
          decoration: const InputDecoration(
            labelText: "Street",
            prefixIcon: Icon(Icons.home),
          ),
          validator: (value) => (value?.isEmpty ?? true) ? "Street is required" : null,
        ),
        TextFormField(
          controller: _cityController,
          decoration: const InputDecoration(
            labelText: "City",
            prefixIcon: Icon(Icons.location_city),
          ),
          validator: (value) => (value?.isEmpty ?? true) ? "City is required" : null,
        ),
        TextFormField(
          controller: _stateController,
          decoration: const InputDecoration(
            labelText: "State",
            prefixIcon: Icon(Icons.map),
          ),
          validator: (value) => (value?.isEmpty ?? true) ? "State is required" : null,
        ),
        TextFormField(
          controller: _zipCodeController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: "ZIP Code",
            prefixIcon: Icon(Icons.numbers),
          ),
          validator: (value) => (value?.isEmpty ?? true) ? "ZIP Code is required" : null,
        ),
      ],
    );
  }

  /// **Sign Up "button"** as a text link, showing a loading spinner if busy
  Widget _buildSignUpButton() {
    return _isLoading
        ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        : TextButton(
            onPressed: _handleSignUp,
            child: const Text(
              "Sign Up",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
  }

  Widget _buildLoginLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("Already have an account? "),
        TextButton(
          onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
          child: const Text(
            "Login",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
