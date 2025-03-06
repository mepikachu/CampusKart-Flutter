import 'dart:async'; // Add this import for TimeoutException
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLoginInfo();
    });
  }

  Future<void> _loadLoginInfo() async {
    print('Loading saved credentials...');
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _emailController.text = prefs.getString('email') ?? '';
        _passwordController.text = prefs.getString('password') ?? '';
        _rememberMe = prefs.getBool('rememberMe') ?? false;
      });

      if (_rememberMe && _emailController.text.isNotEmpty && _passwordController.text.isNotEmpty) {
        print('Attempting auto-login...');
        await _handleLogin();
      }
    } catch (e) {
      print('Error loading credentials: $e');
    }
  }

  Future<void> _saveLoginInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('email', _emailController.text);
        await prefs.setString('password', _passwordController.text);
        await prefs.setBool('rememberMe', true);
      } else {
        await prefs.remove('email');
        await prefs.remove('password');
        await prefs.setBool('rememberMe', false);
      }
    } catch (e) {
      print('Error saving credentials: $e');
    }
  }

  Future<void> _handleLogin() async {
    print('=== Login Process Started ===');
    if (!_formKey.currentState!.validate()) {
      print('Validation failed');
      return;
    }

    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _saveLoginInfo();

      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
        }),
      ).timeout(const Duration(seconds: 15));

      print('Response Status: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (!mounted) return;

      final responseBody = json.decode(response.body);
      
      if (response.statusCode == 200 && responseBody['message'] == 'Login successful') {
        print('Login successful! Navigating to home...');
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        setState(() {
          _errorMessage = responseBody['message'] ?? 'Login failed. Please try again.';
        });
      }
    } on http.ClientException catch (e) {
      print('Network error: $e');
      setState(() {
        _errorMessage = 'Network error. Check your connection.';
      });
    } on TimeoutException {
      print('Request timed out');
      setState(() {
        _errorMessage = 'Server response timed out. Try again.';
      });
    } catch (e) {
      print('Unexpected error: $e');
      setState(() {
        _errorMessage = 'An unexpected error occurred.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      print('=== Login Process Ended ===');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.blue.shade50,
                          child: const Icon(Icons.person, size: 50, color: Colors.blue),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Welcome Back!",
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Login to your account",
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: "Email",
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return "Please enter your email";
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: "Password",
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return "Please enter your password";
                            return null;
                          },
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Checkbox(
                              value: _rememberMe,
                              onChanged: (value) {
                                setState(() {
                                  _rememberMe = value!;
                                });
                              },
                            ),
                            const Text("Remember me"),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                Navigator.pushNamed(context, '/forgot');
                              },
                              child: const Text("Forgot Password?"),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text("Login"),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: const [
                            Expanded(child: Divider(thickness: 1)),
                            SizedBox(width: 8),
                            Text("or"),
                            SizedBox(width: 8),
                            Expanded(child: Divider(thickness: 1)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            IconButton(
                              onPressed: () => ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text("Google Sign In clicked!"))),
                              icon: const Icon(Icons.g_mobiledata, size: 32, color: Colors.red),
                            ),
                            IconButton(
                              onPressed: () => ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text("Facebook Sign In clicked!"))),
                              icon: const Icon(Icons.facebook, size: 32, color: Colors.blue),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("Don't have an account? "),
                            TextButton(
                              onPressed: () {
                                Navigator.pushNamed(context, '/signup');
                              },
                              child: const Text(
                                "Sign Up",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
