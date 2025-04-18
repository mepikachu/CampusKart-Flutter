import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';
import '../config/api_config.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _emailFormKey = GlobalKey<FormState>();
  
  final TextEditingController _userNameController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _stateController = TextEditingController();
  final TextEditingController _zipCodeController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(
    6, (_) => TextEditingController());
  
  final _secureStorage = const FlutterSecureStorage();
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  bool _acceptedTerms = false;
  
  // New fields for profile picture and volunteer registration
  File? _profilePicture;
  bool _registerAsVolunteer = false;
  
  // Email verification state
  bool _emailVerified = false;
  bool _showOtpField = false;
  String? _verificationId;
  bool _isVerifyingEmail = false;
  Timer? _resendTimer;
  int _resendSeconds = 0;
  
  // Define fixed address values
  final Map<String, String> _fixedAddress = {
    'street': 'IIT-Ropar',
    'city': 'Ropar',
    'state': 'Punjab',
    'zipCode': '140001',
    'country': 'India'
  };

  // Focus nodes for OTP input fields
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    // Initialize address controllers with fixed values
    _streetController.text = _fixedAddress['street']!;
    _cityController.text = _fixedAddress['city']!;
    _stateController.text = _fixedAddress['state']!;
    _zipCodeController.text = _fixedAddress['zipCode']!;
    
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
    
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    
    for (var focusNode in _otpFocusNodes) {
      focusNode.dispose();
    }
    
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _pickProfilePicture() async {
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _profilePicture = File(pickedFile.path);
      });
    }
  }

  void _clearProfilePicture() {
    setState(() {
      _profilePicture = null;
    });
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload New Image'),
              onTap: () {
                Navigator.pop(context);
                _pickProfilePicture();
              },
            ),
            ListTile(
              leading: const Icon(Icons.clear),
              title: const Text('Clear Image'),
              onTap: () {
                Navigator.pop(context);
                _clearProfilePicture();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTermsAndConditions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Terms and Conditions",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("1. Platform Overview", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text("IIT Ropar Marketplace is an exclusive platform for IIT Ropar community members to buy, sell, and exchange items within the campus community."),
              const SizedBox(height: 12),
              
              const Text("2. User Eligibility", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text("Only current students, faculty, and staff of IIT Ropar can register and use this platform. Users must register with their official IIT Ropar email addresses."),
              const SizedBox(height: 12),
              
              const Text("3. User Responsibilities", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text("Users are responsible for maintaining accurate product listings, responding to inquiries promptly, and engaging in respectful communication with other users."),
              const SizedBox(height: 12),
              
              const Text("4. Prohibited Items", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text("The following items are strictly prohibited:"),
              const SizedBox(height: 4),
              const Text("• Illegal goods and substances\n• Weapons and dangerous materials\n• Academic materials violating copyright\n• Counterfeit products\n• Any items violating institute policies"),
              const SizedBox(height: 12),
              
              const Text("5. Transaction Safety", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text("Users are advised to meet in public campus locations for exchanges and verify items before completing transactions. The platform is not responsible for any physical exchanges or payments."),
              const SizedBox(height: 12),
              
              const Text("6. Account Security", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text("Users must maintain the security of their accounts and immediately report any unauthorized access or suspicious activity."),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileImageSelector() {
    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.grey[200],
            // If no profile picture is selected, show a default person icon
            child: _profilePicture != null
                ? null // Don't show icon if we have a profile picture
                : Icon(
                    Icons.person,
                    size: 80,
                    color: Colors.grey[400],
                  ),
            backgroundImage: _profilePicture != null
                ? FileImage(_profilePicture!)
                : null,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: InkWell(
              onTap: _showImageOptions,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(6),
                child: const Icon(
                  Icons.edit,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getAddress() {
    return _fixedAddress;
  }

  // Show notification bar at the top with red for errors and green for success
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

  // Send OTP to email
  Future<void> _sendOtp() async {
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() {
      _isVerifyingEmail = true;
    });

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.sendOtpUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': _emailController.text}),
      ).timeout(const Duration(seconds: 15));

      final responseData = json.decode(response.body);
      
      if (response.statusCode == 200 && responseData['success'] == true) {
        setState(() {
          _showOtpField = true;
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
        _isVerifyingEmail = false;
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
      _isVerifyingEmail = true;
    });

    try {
      final response = await http.post(
        Uri.parse(ApiConfig.verifyOtpUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'otp': otp,
          'verificationId': _verificationId,
        }),
      ).timeout(const Duration(seconds: 15));

      final responseData = json.decode(response.body);
      
      if (response.statusCode == 200 && responseData['success'] == true) {
        setState(() {
          _emailVerified = true;
          _showOtpField = false;
        });
        
        _showTopSnackBar('Email verified successfully', isError: false);
      } else {
        _showTopSnackBar(responseData['error'] ?? 'Invalid OTP');
      }
    } catch (e) {
      _showTopSnackBar("An error occurred. Please try again later.");
    } finally {
      setState(() {
        _isVerifyingEmail = false;
      });
    }
  }

  // Google Sign In
  Future<void> _signInWithGoogle() async {
    setState(() {
      _isVerifyingEmail = true;
    });

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        setState(() {
          _isVerifyingEmail = false;
        });
        return; // User canceled the sign-in flow
      }
      
      // Get email from Google account
      final email = googleUser.email;
      
      // Verify with backend
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/verify-google'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'googleId': googleUser.id,
        }),
      ).timeout(const Duration(seconds: 15));

      final responseData = json.decode(response.body);
      
      if (response.statusCode == 200 && responseData['success'] == true) {
        setState(() {
          _emailController.text = email;
          _emailVerified = true;
          // Store verification ID received from Google sign-in
          _verificationId = responseData['verificationId'];
        });
        
        _showTopSnackBar('Email verified with Google', isError: false);
      } else {
        _showTopSnackBar(responseData['error'] ?? 'Google verification failed');
      }
    } catch (e) {
      _showTopSnackBar("An error occurred during Google sign-in");
    } finally {
      setState(() {
        _isVerifyingEmail = false;
      });
    }
  }

  Future<void> _handleSignUp() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_passwordController.text != _confirmPasswordController.text) {
      _showTopSnackBar("Passwords do not match");
      return;
    }
    
    if (!_acceptedTerms) {
      _showTopSnackBar("You must accept the Terms and Conditions");
      return;
    }
    
    if (_verificationId == null) {
      _showTopSnackBar("Verification ID is missing. Please try again.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Use a multipart request to send both fields and an image if provided.
      final uri = Uri.parse(ApiConfig.signupUrl);
      final request = http.MultipartRequest('POST', uri);

      request.fields['verificationId'] = _verificationId!;
      request.fields['userName'] = _userNameController.text;
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

        // Navigate based on role:
        final role = responseData['user']?['role'] ?? 'user';
        await prefs.setString('role', role);
        if (role == 'admin') {
          Navigator.pushReplacementNamed(context, '/admin_home');
        } else if (role == 'volunteer') {
          Navigator.pushReplacementNamed(context, '/volunteer_home');
        } else {
          Navigator.pushReplacementNamed(context, '/user_home');
        }
      } else {
        _showTopSnackBar(responseData['error'] ?? 'Signup failed');
      }
    } on TimeoutException {
      _showTopSnackBar("Connection timeout");
    } on http.ClientException {
      _showTopSnackBar("Network error");
    } catch (e) {
      _showTopSnackBar("An error occurred. Please try again later.");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    
    return Scaffold(
      backgroundColor: Colors.white,
      // Don't resize when keyboard appears
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Main scrollable content
          Positioned.fill(
            bottom: _emailVerified ? 0 : 60, // Make space for the footer on email screen
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  width: screenWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  // Precisely center the content
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: _emailVerified ? screenHeight - bottomPadding : screenHeight - 60 - bottomPadding,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _emailVerified
                            ? _buildRegistrationForm()
                            : _buildEmailVerificationForm(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Fixed footer at the bottom for "Already have an account"
          if (!_emailVerified)
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
                            "Already have an account? ",
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
                              "Log in",
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

  // Email verification form
  Widget _buildEmailVerificationForm() {
    return Form(
      key: _emailFormKey,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Progress indicators with bigger gaps
          Container(
            margin: const EdgeInsets.only(bottom: 40, top: 40),  // Added top margin
            child: Column(
              children: [
                // Progress indicator row with smaller circles and more space between them
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Smaller circle (reduced from 60 to 50)
                    Container(
                      width: 50,  // Reduced from 60
                      height: 50,  // Reduced from 60
                      decoration: BoxDecoration(
                        color: Colors.green[400],
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
                      child: const Center(
                        child: Text(
                          "1",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ),
                    // Wider connector (increased from 50 to 80)
                    Container(
                      width: 80,  // Increased from 50 to 80
                      height: 3,  // Reduced from 4 to 3
                      color: Colors.grey[300],
                    ),
                    Container(
                      width: 50,  // Reduced from 60
                      height: 50,  // Reduced from 60
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          "2",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,  // Reduced from 24
                          ),
                        ),
                      ),
                    ),
                    // Wider connector (increased from 50 to 80)
                    Container(
                      width: 80,  // Increased from 50 to 80
                      height: 3,  // Reduced from 4 to 3
                      color: Colors.grey[300],
                    ),
                    Container(
                      width: 50,  // Reduced from 60
                      height: 50,  // Reduced from 60
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          "3",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,  // Reduced from 24
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Text row - adjusted widths to match circles and connectors
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 50,  // Match circle width
                      child: Text(
                        "Email Verification",  // More descriptive
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,  // Smaller to fit text
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 80),  // Match connector width
                    SizedBox(
                      width: 50,  // Match circle width
                      child: Text(
                        "Account Details",  // More descriptive
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,  // Smaller to fit text
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                    const SizedBox(width: 80),  // Match connector width
                    SizedBox(
                      width: 50,  // Match circle width
                      child: Text(
                        "Registration Successful",  // More descriptive
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,  // Smaller to fit longer text
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (!_showOtpField) ...[
            // Email field when not showing OTP
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                hintText: "Email",
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
                if (value == null || value.isEmpty) return "Email is required";
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                  return "Invalid email format";
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            Text(
              "We'll send a verification code to this email",
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12, 
                color: Colors.grey[500]
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isVerifyingEmail ? null : _sendOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[400],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                  disabledBackgroundColor: Colors.blue[200],
                ),
                child: _isVerifyingEmail
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
            // Google login button with Icon instead of image
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
                onPressed: _isVerifyingEmail ? null : _signInWithGoogle,
              ),
            ),
          ] else ...[
            // OTP Input Fields - 6 separate boxes
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
            
            // Verify OTP button
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isVerifyingEmail ? null : _verifyOtp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[400],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                  disabledBackgroundColor: Colors.blue[200],
                ),
                child: _isVerifyingEmail
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
        ],
      ),
    );
  }

  Widget _buildRegistrationForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Step indicator similar to the provided image
          Container(
            margin: const EdgeInsets.only(bottom: 15, top: 20), // Added top margin, reduced bottom
            child: Column(
              children: [
                // Progress indicator row with smaller circles and more space between them
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Smaller circle (reduced from 60 to 50)
                    Container(
                      width: 50,  // Reduced from 60
                      height: 50,  // Reduced from 60
                      decoration: BoxDecoration(
                        color: Colors.green[400],
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
                      child: const Center(
                        child: Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 22,  // Reduced from 28
                        ),
                      ),
                    ),
                    // Wider connector (increased from 50 to 80)
                    Container(
                      width: 80,  // Increased from 50 to 80
                      height: 3,  // Reduced from 4 to 3
                      color: Colors.green[400],
                    ),
                    Container(
                      width: 50,  // Reduced from 60
                      height: 50,  // Reduced from 60
                      decoration: BoxDecoration(
                        color: Colors.green[400],
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          "2",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,  // Reduced from 24
                          ),
                        ),
                      ),
                    ),
                    // Wider connector (increased from 50 to 80)
                    Container(
                      width: 80,  // Increased from 50 to 80
                      height: 3,  // Reduced from 4 to 3
                      color: Colors.grey[300],
                    ),
                    Container(
                      width: 50,  // Reduced from 60
                      height: 50,  // Reduced from 60
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          "3",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,  // Reduced from 24
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Text row - adjusted widths to match circles and connectors
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 50,  // Match circle width
                      child: Text(
                        "Email Verification",  // More descriptive
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,  // Smaller to fit text
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                    const SizedBox(width: 80),  // Match connector width
                    SizedBox(
                      width: 50,  // Match circle width
                      child: Text(
                        "Account Details",  // More descriptive
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,  // Smaller to fit text
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 80),  // Match connector width
                    SizedBox(
                      width: 50,  // Match circle width
                      child: Text(
                        "Registration Successful",  // More descriptive
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9,  // Smaller to fit longer text
                          color: Colors.grey[500],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 10), // Reduced from 20 to create less space
          _buildProfileImageSelector(),
          const SizedBox(height: 20),
          _buildUserNameField(),
          const SizedBox(height: 20),
          _buildNameField(),
          const SizedBox(height: 20),
          // Email field (disabled, showing verified email)
          TextFormField(
            controller: _emailController,
            enabled: false, // Disabled since already verified
            decoration: InputDecoration(
              labelText: "Email (Verified)",
              prefixIcon: const Icon(Icons.email),
              suffixIcon: Icon(Icons.verified, color: Colors.green),
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
          ),
          const SizedBox(height: 20),
          _buildPhoneField(),
          const SizedBox(height: 20),
          _buildPasswordField(),
          const SizedBox(height: 20),
          _buildConfirmPasswordField(),
          const SizedBox(height: 20),
          _buildFixedAddressSection(),
          const SizedBox(height: 20),
          
          // Improved Register as Volunteer toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber[200]!)
            ),
            child: Row(
              children: [
                Icon(
                  Icons.volunteer_activism,
                  color: Colors.amber[800],
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Register as Volunteer",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.amber[900],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Help others by volunteering to deliver and manage donations",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber[800],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: _registerAsVolunteer,
                  onChanged: (value) {
                    setState(() {
                      _registerAsVolunteer = value;
                    });
                  },
                  activeColor: Colors.amber[800],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Terms and Conditions acceptance checkbox
          Row(
            children: [
              Checkbox(
                value: _acceptedTerms,
                onChanged: (bool? value) {
                  setState(() {
                    _acceptedTerms = value ?? false;
                  });
                },
                activeColor: Colors.blue[700],
              ),
              Expanded(
                child: Wrap(
                  children: [
                    Text(
                      "I agree to the ",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                      ),
                    ),
                    GestureDetector(
                      onTap: _showTermsAndConditions,
                      child: Text(
                        "Terms and Conditions",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading || !_acceptedTerms ? null : _handleSignUp,
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
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white, 
                        strokeWidth: 2.5
                      ),
                    )
                  : Text(
                      "Sign Up",
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
          
          // Already have an account section for registration form 
          const SizedBox(height: 30),
          Divider(color: Colors.grey[300], thickness: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Already have an account? ",
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
                    "Log in",
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
    );
  }

  Widget _buildUserNameField() {
    return TextFormField(
      controller: _userNameController,
      decoration: InputDecoration(
        labelText: "Username",
        hintText: "Unique username (3-30 characters)",
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
      decoration: InputDecoration(
        labelText: "Full Name",
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
        if (value == null || value.isEmpty) return "Full name is required";
        return null;
      },
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      decoration: InputDecoration(
        labelText: "Phone Number",
        hintText: "10-digit mobile number",
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
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
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
    );
  }

  Widget _buildFixedAddressSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Address Details",
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 16, 
            fontWeight: FontWeight.bold
          ),
        ),
        const SizedBox(height: 10),
        // Using the same text fields but pre-filled and disabled
        TextFormField(
          controller: _streetController,
          enabled: false,
          decoration: InputDecoration(
            labelText: "Street",
            filled: true,
            fillColor: Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _cityController,
          enabled: false,
          decoration: InputDecoration(
            labelText: "City",
            filled: true,
            fillColor: Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _stateController,
          enabled: false,
          decoration: InputDecoration(
            labelText: "State",
            filled: true,
            fillColor: Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _zipCodeController,
          enabled: false,
          decoration: InputDecoration(
            labelText: "ZIP Code",
            filled: true,
            fillColor: Colors.grey[100],
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(5),
              borderSide: BorderSide(color: Colors.grey[300]!),
            ),
          ),
        ),
      ],
    );
  }
}
