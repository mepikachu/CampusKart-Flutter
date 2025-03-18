import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import your ForgotPasswordScreen
import 'forgot_password.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSavedIdentifier();
    _checkExistingSession();
  }

  Future<void> _checkExistingSession() async {
    final authCookie = await _secureStorage.read(key: 'authCookie');
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool('rememberMe') ?? false;
    final storedRole = prefs.getString('role'); // retrieve stored role
    if (authCookie != null && remember && storedRole != null && mounted) {
      if (storedRole == 'admin') {
        Navigator.pushReplacementNamed(context, '/admin_home');
      } else if (storedRole == 'volunteer') {
        Navigator.pushReplacementNamed(context, '/volunteer_home');
      } else {
        Navigator.pushReplacementNamed(context, '/user_home');
      }
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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

        // Navigate based on role:
        final role = responseBody['user']?['role'] ?? 'user';
        // Store the role locally for session persistence:
        await prefs.setString('role', role);
        if (role == 'admin') {
          Navigator.pushReplacementNamed(context, '/admin_home');
        } else if (role == 'volunteer') {
          Navigator.pushReplacementNamed(context, '/volunteer_home');
        } else {
          Navigator.pushReplacementNamed(context, '/user_home'); // changed from '/home'
        }
      } else {
        setState(() {
          _errorMessage = responseBody['error'] ?? 'Login failed';
        });
      }
    } on TimeoutException {
      setState(() => _errorMessage = 'Connection timeout');
    } on http.ClientException {
      setState(() => _errorMessage = 'Network error');
    } catch (e) {
      setState(() => _errorMessage = 'An error occurred');
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
    return Scaffold(
      backgroundColor: Colors.white, // Plain single-color background
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                const CircleAvatar(
                  radius: 40,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 50, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Welcome Back!",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 20),

                // Email/Username field
                TextFormField(
                  controller: _identifierController,
                  decoration: const InputDecoration(
                    labelText: "Email/Username",
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      (value?.isEmpty ?? true) ? "Required" : null,
                ),
                const SizedBox(height: 16),

                // Password field
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
                      onPressed: () => setState(() {
                        _obscurePassword = !_obscurePassword;
                      }),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      (value?.isEmpty ?? true) ? "Required" : null,
                ),

                // Remember me & Forgot Password row
                const SizedBox(height: 10),
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged: (value) =>
                          setState(() => _rememberMe = value ?? false),
                    ),
                    const Text("Remember me"),
                    const Spacer(),

                    // Directly navigate to ForgotPasswordScreen
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ForgotPasswordScreen(),
                          ),
                        );
                      },
                      child: const Text("Forgot Password?"),
                    ),
                  ],
                ),

                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 16,
                      ),
                    ),
                  ),

                // Login "button" as a text link (same style as "Create Account")
                _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : TextButton(
                        onPressed: _handleLogin,
                        child: const Text(
                          "Login",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                const SizedBox(height: 20),

                // Create account link
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/signup'),
                  child: const Text("Create Account"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
