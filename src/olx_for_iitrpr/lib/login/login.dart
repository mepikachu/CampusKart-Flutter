import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  final String? errorMessage;
  
  const LoginScreen({Key? key, this.errorMessage}) : super(key: key);
  
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _secureStorage = const FlutterSecureStorage();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedIdentifier();
    _checkExistingSession();
    
    if (widget.errorMessage != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTopSnackBar(widget.errorMessage!);
      });
    }
  }

  Future<void> _checkExistingSession() async {
    final authCookie = await _secureStorage.read(key: 'authCookie');
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('rememberMe') ?? false;
    final storedRole = prefs.getString('role');
    if (authCookie != null && remember && storedRole != null && mounted) {
      if (storedRole == 'admin') {
        Navigator.pushReplacementNamed(context, '/admin_home');
      } else if (storedRole == 'volunteer' || storedRole == 'volunteer_pending') {
        Navigator.pushReplacementNamed(context, '/volunteer_home');
      } else {
        Navigator.pushReplacementNamed(context, '/user_home');
      }
    }
  }

  void _showTopSnackBar(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Poppins',
          ),
        ),
        backgroundColor: isError 
            ? Colors.red.withOpacity(0.8)
            : Colors.green.withOpacity(0.8),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 100,
          right: 20,
          left: 20,
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http
          .post(
            Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'identifier': _identifierController.text.trim(),
              'password': _passwordController.text.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));

      final responseBody = json.decode(response.body);
      print("-------------------------------------------");
      print(responseBody['user']);
      if (response.statusCode == 200 && responseBody['success'] == true) {
        await _secureStorage.write(
          key: 'authCookie',
          value: responseBody['authCookie'],
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('rememberMe', _rememberMe);
        if (_rememberMe) {
          await prefs.setString('identifier', _identifierController.text);
        } else {
          await prefs.remove('identifier');
        }

        if (responseBody['user'] != null) {
          await _secureStorage.write(
            key: 'userId',
            value: responseBody['user']['_id'],
          );
          await _secureStorage.write(
            key: 'userName',
            value: responseBody['user']['userName'],
          );
        } else {
          await _secureStorage.delete(key: 'userId');
          await _secureStorage.delete(key: 'userName');
        }

        final role = responseBody['user']?['role'] ?? 'user';
        await prefs.setString('role', role);
        if (role == 'admin') {
          Navigator.pushReplacementNamed(context, '/admin_home');
        } else if (role == 'volunteer' || role == 'volunteer_pending') {
          Navigator.pushReplacementNamed(context, '/volunteer_home');
        } else {
          Navigator.pushReplacementNamed(context, '/user_home');
        }
      } else {
        _showTopSnackBar(responseBody['error'] ?? 'Login failed');
      }
    } on TimeoutException {
      _showTopSnackBar('Connection timeout');
    } on http.ClientException {
      _showTopSnackBar('Network error');
    } catch (e) {
      _showTopSnackBar('An error occurred');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSavedIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    final identifier = prefs.getString('identifier');
    if (identifier != null && mounted) {
      setState(() {
        _identifierController.text = identifier;
        _rememberMe = true;
      });
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Main scrollable content
          Positioned.fill(
            bottom: 60, // Make space for the footer
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  width: screenWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  // Precisely center the content
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: screenHeight - 60 - bottomPadding,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            "IITRPR MarketPlace",
                            style: TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -1.0,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 40),

                          // Username/Email field
                          TextFormField(
                            controller: _identifierController,
                            decoration: InputDecoration(
                              hintText: "Username or email",
                              hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                              filled: true,
                              fillColor: Colors.grey[100],
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: BorderSide(color: Colors.grey[400]!),
                              ),
                            ),
                            validator: (value) => (value?.isEmpty ?? true) ? "Required" : null,
                          ),
                          const SizedBox(height: 12),

                          // Password field
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              hintText: "Password",
                              hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                              filled: true,
                              fillColor: Colors.grey[100],
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: BorderSide(color: Colors.grey[400]!),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                  color: Colors.grey[500],
                                ),
                                onPressed: () => setState(() {
                                  _obscurePassword = !_obscurePassword;
                                }),
                              ),
                            ),
                            validator: (value) => (value?.isEmpty ?? true) ? "Required" : null,
                          ),

                          const SizedBox(height: 8),
                          
                          // Remember me and Forgot password row
                          Row(
                            children: [
                              // Remember me checkbox
                              Checkbox(
                                value: _rememberMe,
                                onChanged: (bool? value) {
                                  setState(() {
                                    _rememberMe = value ?? false;
                                  });
                                },
                                activeColor: Colors.blue[700],
                              ),
                              Text(
                                "Remember me",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[700],
                                ),
                              ),
                              
                              const Spacer(),
                              
                              // Forgot password button
                              TextButton(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/forgot_password');
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(10, 30),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  "Forgot password?",
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 12,
                                    color: Colors.blue[900],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Login button
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[400],
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                disabledBackgroundColor: Colors.blue[200],
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      "Log in",
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
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
            ),
          ),
          
          // Fixed footer at the bottom for "Don't have an account"
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Divider(color: Colors.grey[300], thickness: 1),
                  Padding(
                    padding: EdgeInsets.only(
                      top: 16,
                      bottom: 16 + bottomPadding,
                      left: 16,
                      right: 16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[600], 
                            fontSize: 12
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushNamed(context, '/signup');
                          },
                          child: Text(
                            "Sign up",
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.blue[900],
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
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
    );
  }
}
