import 'package:flutter/material.dart';

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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Simulated login function. Replace with actual authentication logic.
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    // Simulate network delay.
    await Future.delayed(const Duration(seconds: 2));

    // Check credentials (for demonstration only).
    if (_emailController.text.trim() == "user@example.com" && _passwordController.text.trim() == "password") {
      if (!mounted) return; // Check if the widget is still mounted.
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      if (!mounted) return; // Check if the widget is still mounted.
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Login Failed"),
          content: const Text("Invalid email or password."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            )
          ],
        ),
      );
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Gradient background for a modern look.
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
                        // Logo and welcome header.
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
                        // Email Field.
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
                        // Password Field.
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
                        // Remember Me and Forgot Password row.
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
                        // Login Button.
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
                        // Divider with text.
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
                        // Social Login Buttons.
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
                        // Sign Up link.
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
