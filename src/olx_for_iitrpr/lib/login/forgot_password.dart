import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/api_config.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final GlobalKey<FormState> _emailFormKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _passwordFormKey = GlobalKey<FormState>();
  
  // Controllers
  final TextEditingController _identifierController = TextEditingController(); // Email or username
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  
  // Focus nodes for OTP fields
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  
  // Google Sign In
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  
  // State variables
  int _currentStep = 0; // 0: Email entry, 1: OTP verification, 2: New password, 3: Success
  bool _showOtpField = false;
  bool _isProcessing = false;
  String? _verificationId;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _email; // Store email for later API calls
  Timer? _resendTimer;
  int _resendSeconds = 0;
  
  @override
  void initState() {
    super.initState();
    
    // Add listeners to OTP controllers for auto-advancing
    for (int i = 0; i < 5; i++) {
      _otpControllers[i].addListener(() {
        if (_otpControllers[i].text.length == 1) {
          _otpFocusNodes[i + 1].requestFocus();
        }
      });
    }
    
    // Add listener to last OTP controller for auto verification
    _otpControllers[5].addListener(() {
      if (_otpControllers[5].text.length == 1) {
        String otp = _otpControllers.map((controller) => controller.text).join();
        if (otp.length == 6) {
          // Auto verify when all digits are entered
          _verifyOtp();
        }
      }
    });
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    
    for (var focusNode in _otpFocusNodes) {
      focusNode.dispose();
    }
    
    _resendTimer?.cancel();
    super.dispose();
  }

  // Show notification bar
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

  // Clear all OTP fields
  void _clearOtpFields() {
    for (var controller in _otpControllers) {
      controller.clear();
    }
    _otpFocusNodes[0].requestFocus();
  }

  // Get full OTP from individual fields
  String _getFullOtp() {
    return _otpControllers.map((controller) => controller.text).join();
  }

  // Google Password Reset
  Future<void> _googlePasswordReset() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        setState(() {
          _isProcessing = false;
        });
        return; // User canceled the sign-in flow
      }
      
      // Get email from Google account
      final email = googleUser.email;
      
      // Pre-fill email field and send OTP
      setState(() {
        _identifierController.text = email;
        _email = email;
      });
      
      // Send OTP to the Google email
      await _sendOtp();
      
    } catch (e) {
      _showTopSnackBar("An error occurred during Google sign-in");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Send OTP to email
  Future<void> _sendOtp() async {
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() {
      _isProcessing = true;
      _email = _identifierController.text; // Store email for later use
    });

    try {
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/send-reset-otp'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'identifier': _identifierController.text}),
      ).timeout(const Duration(seconds: 15));

      final responseData = json.decode(response.body);
      
      if (response.statusCode == 200 && responseData['success'] == true) {
        setState(() {
          _showOtpField = true;
          _currentStep = 1; // Move to OTP verification step
          _verificationId = responseData['verificationId'];
          _resendSeconds = 60;
        });
        
        // Start countdown timer for resend button
        _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            if (_resendSeconds > 0) {
              _resendSeconds--;
            } else {
              _resendTimer?.cancel();
            }
          });
        });
        
        _showTopSnackBar('OTP sent to your email', isError: false);
      } else {
        _showTopSnackBar(responseData['error'] ?? 'Failed to send OTP');
      }
    } catch (e) {
      _showTopSnackBar("An error occurred. Please try again later.");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Verify OTP
  Future<void> _verifyOtp() async {
    final otp = _getFullOtp();
    
    if (otp.length != 6) {
      _showTopSnackBar("Please enter the 6-digit OTP");
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'otp': otp,
          'verificationId': _verificationId,
        }),
      ).timeout(const Duration(seconds: 15));

      final responseData = json.decode(response.body);
      
      if (response.statusCode == 200 && responseData['success'] == true) {
        setState(() {
          _currentStep = 2; // Move to password reset step
          _showOtpField = false;
        });
        
        _showTopSnackBar('OTP verified successfully', isError: false);
      } else {
        _showTopSnackBar(responseData['error'] ?? 'Invalid OTP');
      }
    } catch (e) {
      _showTopSnackBar("An error occurred. Please try again later.");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // Reset password
  Future<void> _resetPassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    
    if (_passwordController.text != _confirmPasswordController.text) {
      _showTopSnackBar("Passwords do not match");
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'identifier': _email,
          'verificationId': _verificationId,
          'newPassword': _passwordController.text,
        }),
      ).timeout(const Duration(seconds: 15));

      final responseData = json.decode(response.body);
      
      if (response.statusCode == 200 && responseData['success'] == true) {
        setState(() {
          _currentStep = 3; // Move to success state
        });
        
        _showTopSnackBar('Password reset successfully', isError: false);
        
        // Navigate to login after a delay
        Timer(const Duration(seconds: 2), () {
          Navigator.pushReplacementNamed(context, '/login');
        });
      } else {
        _showTopSnackBar(responseData['error'] ?? 'Failed to reset password');
      }
    } catch (e) {
      _showTopSnackBar("An error occurred. Please try again later.");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
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
          // Main content
          Positioned.fill(
            bottom: 60, // Make space for the footer
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  width: screenWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: screenHeight - 60 - bottomPadding,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (_currentStep == 0)
                          _buildEmailEntryForm(),
                        if (_currentStep == 1)
                          _buildOtpVerificationForm(),
                        if (_currentStep == 2)
                          _buildPasswordResetForm(),
                        if (_currentStep == 3)
                          _buildSuccessState(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Fixed footer at the bottom
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
                          "Go back to ",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[600], 
                            fontSize: 12
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.pushReplacementNamed(context, '/login');
                          },
                          child: Text(
                            "Login",
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.blue[900],
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Text(
                          " Page",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.grey[600], 
                            fontSize: 12
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

  // Build step indicator
  Widget _buildStepIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 40, top: 40),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // First circle
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _currentStep > 0 ? Colors.green[400] : Colors.green[400],
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.3),
                      spreadRadius: 1,
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Center(
                  child: _currentStep > 0
                      ? const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 22,
                        )
                      : const Text(
                          "1",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                ),
              ),
              // Connector
              Container(
                width: 80,
                height: 3,
                color: _currentStep > 0 ? Colors.green[400] : Colors.grey[300],
              ),
              // Second circle
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _currentStep > 1 
                      ? Colors.green[400] 
                      : _currentStep == 1 
                          ? Colors.green[400] 
                          : Colors.grey[300],
                  shape: BoxShape.circle,
                  boxShadow: _currentStep >= 1
                      ? [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.3),
                            spreadRadius: 1,
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: _currentStep > 1
                      ? const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 22,
                        )
                      : Text(
                          "2",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                ),
              ),
              // Connector
              Container(
                width: 80,
                height: 3,
                color: _currentStep > 1 ? Colors.green[400] : Colors.grey[300],
              ),
              // Third circle
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _currentStep > 2
                      ? Colors.green[400]
                      : _currentStep == 2
                          ? Colors.green[400]
                          : Colors.grey[300],
                  shape: BoxShape.circle,
                  boxShadow: _currentStep >= 2
                      ? [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.3),
                            spreadRadius: 1,
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: _currentStep > 2
                      ? const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 22,
                        )
                      : Text(
                          "3",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 50,
                child: Text(
                  "Enter Email",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: _currentStep == 0 ? Colors.blue[700] : Colors.grey[700],
                    fontWeight: _currentStep == 0 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 80),
              SizedBox(
                width: 50,
                child: Text(
                  "Verify OTP",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: _currentStep == 1 ? Colors.blue[700] : Colors.grey[700],
                    fontWeight: _currentStep == 1 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(width: 80),
              SizedBox(
                width: 50,
                child: Text(
                  "Reset Password",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    color: _currentStep == 2 ? Colors.blue[700] : Colors.grey[700],
                    fontWeight: _currentStep == 2 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Email entry form
  Widget _buildEmailEntryForm() {
    return Form(
      key: _emailFormKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildStepIndicator(),
          
          TextFormField(
            controller: _identifierController,
            decoration: InputDecoration(
              hintText: "Email or username",
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
            validator: (value) {
              if (value == null || value.isEmpty) {
                return "Please enter your email or username";
              }
              return null;
            },
          ),
          const SizedBox(height: 10),
          Text(
            "Enter your email or username to receive a password reset code",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _sendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[400],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                disabledBackgroundColor: Colors.blue[200],
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      "Send OTP",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
          
          const SizedBox(height: 30),
          
          // OR divider with lines on both sides
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  "OR",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Colors.grey[300], thickness: 1)),
            ],
          ),
          
          const SizedBox(height: 30),
          // Google login button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: Image.asset(
                'assets/google_logo.webp',
                height: 24,
                width: 24,
                errorBuilder: (context, error, stackTrace) {
                  // Fallback if image fails to load
                  return Icon(Icons.g_mobiledata, size: 24, color: Colors.red);
                },
              ),
              label: Text(
                "Continue with Google",
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.black87,
                  fontSize: 14,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: BorderSide(color: Colors.grey[300]!),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              onPressed: _isProcessing ? null : _googlePasswordReset,
            ),
          ),
        ],
      ),
    );
  }

  // OTP verification form
  Widget _buildOtpVerificationForm() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildStepIndicator(),
        
        // OTP Input Fields
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(
            6,
            (index) => SizedBox(
              width: 40,
              height: 50,
              child: TextField(
                controller: _otpControllers[index],
                focusNode: _otpFocusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                decoration: InputDecoration(
                  counterText: "",
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.blue[400]!),
                  ),
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(1),
                ],
                onChanged: (value) {
                  // Handle backspace - move to previous field
                  if (value.isEmpty && index > 0) {
                    _otpFocusNodes[index - 1].requestFocus();
                  }
                },
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 10),
        Text(
          "Enter the verification code sent to your email",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
          ),
        ),
        
        // Resend OTP row
        Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _resendSeconds > 0 ? null : _sendOtp,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue[900],
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(10, 10),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _resendSeconds > 0 
                      ? "Resend in $_resendSeconds s" 
                      : "Resend OTP",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Verify button
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isProcessing ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[400],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              disabledBackgroundColor: Colors.blue[200],
            ),
            child: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    "Verify OTP",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // Password reset form
  Widget _buildPasswordResetForm() {
    return Form(
      key: _passwordFormKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildStepIndicator(),
          
          // New password field
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: "New Password",
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
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey[500]),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return "Password is required";
              if (value.length < 6) return "Minimum 6 characters required";
              return null;
            },
          ),
          const SizedBox(height: 20),
          
          // Confirm password field
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            decoration: InputDecoration(
              labelText: "Confirm Password",
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
                icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey[500]),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return "Please confirm password";
              if (value != _passwordController.text) return "Passwords don't match";
              return null;
            },
          ),
          
          const SizedBox(height: 10),
          Text(
            "Create a new password for your account",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
          
          const SizedBox(height: 30),
          
          // Reset password button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _resetPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[400],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                disabledBackgroundColor: Colors.blue[200],
              ),
              child: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      "Reset Password",
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
    );
  }

  // Success state
  Widget _buildSuccessState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 80,
          color: Colors.green,
        ),
        const SizedBox(height: 20),
        Text(
          "Password Reset Successful",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "Your password has been reset successfully. You will be redirected to the login page.",
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 40),
        ElevatedButton(
          onPressed: () {
            Navigator.pushReplacementNamed(context, '/login');
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[400],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          child: Text(
            "Go to Login",
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
