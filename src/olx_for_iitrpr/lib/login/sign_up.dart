import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Constructs address map to send as JSON.
  Map<String, dynamic> _getAddress() {
    return {
      'street': _streetController.text,
      'city': _cityController.text,
      'state': _stateController.text,
      'zipCode': _zipCodeController.text,
      'country': 'India'
    };
  }

  // Handles registration; on success stores the authCookie and navigates to home.
  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      _showErrorDialog("Passwords do not match");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await http
          .post(
            Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/register'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'userName': _userNameController.text,
              'email': _emailController.text,
              'phone': _phoneController.text,
              'password': _passwordController.text,
              'address': json.encode(_getAddress()),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final responseBody = json.decode(response.body);
      
      if (response.statusCode == 201 && responseBody['success'] == true) {
        // Registration successful, store the authCookie for auto login.
        final authCookie = responseBody['authCookie'];
        await _secureStorage.write(key: 'authCookie', value: authCookie);

        // Optionally, if you want to remember the identifier:
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('identifier', _emailController.text);

        if (mounted) {
          Navigator.pushReplacementNamed(context, '/home');
        }
      } else {
        _showErrorDialog(responseBody['error'] ?? 'Signup failed');
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

  // Shows an error dialog with the given message.
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sign Up")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(16),
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
                  const SizedBox(height: 30),
                  _buildSignUpButton(),
                  const SizedBox(height: 16),
                  _buildLoginLink(),
                ],
              ),
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
        if (value.length < 3 || value.length > 30) return "Must be 3-30 characters";
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
        if (!RegExp(r'^[0-9]{10}$').hasMatch(value)) return "Invalid phone number";
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
        const Text("Address Details", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        TextFormField(
          controller: _streetController,
          decoration: const InputDecoration(labelText: "Street", prefixIcon: Icon(Icons.home)),
          validator: (value) => (value?.isEmpty ?? true) ? "Street is required" : null,
        ),
        TextFormField(
          controller: _cityController,
          decoration: const InputDecoration(labelText: "City", prefixIcon: Icon(Icons.location_city)),
          validator: (value) => (value?.isEmpty ?? true) ? "City is required" : null,
        ),
        TextFormField(
          controller: _stateController,
          decoration: const InputDecoration(labelText: "State", prefixIcon: Icon(Icons.map)),
          validator: (value) => (value?.isEmpty ?? true) ? "State is required" : null,
        ),
        TextFormField(
          controller: _zipCodeController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "ZIP Code", prefixIcon: Icon(Icons.numbers)),
          validator: (value) => (value?.isEmpty ?? true) ? "ZIP Code is required" : null,
        ),
      ],
    );
  }

  Widget _buildSignUpButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSignUp,
        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        child: _isLoading 
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
            : const Text("Sign Up", style: TextStyle(fontSize: 16)),
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
          child: const Text("Login", style: TextStyle(fontWeight: FontWeight.bold)),
        )
      ],
    );
  }
}
