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
import 'package:pin_code_fields/pin_code_fields.dart';

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
  final TextEditingController _otpController = TextEditingController();

  final _secureStorage = const FlutterSecureStorage();
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  
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
    _otpController.dispose();
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

  Widget _buildProfileImageSelector() {
    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 60,
            backgroundImage: _profilePicture != null
                ? FileImage(_profilePicture!)
                : const AssetImage('assets/default_avatar.png')
                    as ImageProvider,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: InkWell(
              onTap: _showImageOptions,
              child: Container(
                decoration: BoxDecoration(
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
    return {
      'street': _streetController.text,
      'city': _cityController.text,
      'state': _stateController.text,
      'zipCode': _zipCodeController.text,
      'country': 'India'
    };
  }

  // Send OTP to email
  Future<void> _sendOtp() async {
    if (!_emailFormKey.currentState!.validate()) return;

    setState(() {
      _isVerifyingEmail = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/send-otp'),
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
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP sent to your email')),
        );
      } else {
        _showErrorDialog(responseData['error'] ?? 'Failed to send OTP');
      }
    } catch (e) {
      _showErrorDialog("An error occurred. Please try again later.");
    } finally {
      setState(() {
        _isVerifyingEmail = false;
      });
    }
  }

  // Verify OTP
  Future<void> _verifyOtp() async {
    if (_otpController.text.isEmpty) {
      _showErrorDialog("Please enter the OTP");
      return;
    }

    setState(() {
      _isVerifyingEmail = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _emailController.text,
          'otp': _otpController.text,
          'verificationId': _verificationId,
        }),
      ).timeout(const Duration(seconds: 15));

      final responseData = json.decode(response.body);
      
      if (response.statusCode == 200 && responseData['success'] == true) {
        setState(() {
          _emailVerified = true;
          _showOtpField = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email verified successfully')),
        );
      } else {
        _showErrorDialog(responseData['error'] ?? 'Invalid OTP');
      }
    } catch (e) {
      _showErrorDialog("An error occurred. Please try again later.");
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
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email verified with Google')),
        );
      } else {
        _showErrorDialog(responseData['error'] ?? 'Google verification failed');
      }
    } catch (e) {
      _showErrorDialog("An error occurred during Google sign-in");
    } finally {
      setState(() {
        _isVerifyingEmail = false;
      });
    }
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("Sign Up")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _emailVerified ? _buildRegistrationForm() : _buildEmailVerificationForm(),
        ),
      ),
    );
  }

  // Email verification form
  Widget _buildEmailVerificationForm() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Verify Your Email",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: "Email",
              prefixIcon: Icon(Icons.email),
              hintText: "Enter your email address",
            ),
            enabled: !_showOtpField,
            validator: (value) {
              if (value == null || value.isEmpty) return "Email is required";
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return "Invalid email format";
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          
          if (_showOtpField) ...[
            const Text(
              "Enter the OTP sent to your email",
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            PinCodeTextField(
              appContext: context,
              length: 6,
              controller: _otpController,
              obscureText: false,
              animationType: AnimationType.fade,
              pinTheme: PinTheme(
                shape: PinCodeFieldShape.box,
                borderRadius: BorderRadius.circular(5),
                fieldHeight: 50,
                fieldWidth: 40,
                activeFillColor: Colors.white,
                inactiveFillColor: Colors.white,
                selectedFillColor: Colors.white,
                activeColor: Theme.of(context).primaryColor,
                inactiveColor: Colors.grey,
                selectedColor: Theme.of(context).primaryColor,
              ),
              animationDuration: const Duration(milliseconds: 300),
              enableActiveFill: true,
              keyboardType: TextInputType.number,
              onCompleted: (v) {
                // Auto verify when all digits are entered
                _verifyOtp();
              },
              onChanged: (value) {
                // No need to do anything here
              },
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: _resendSeconds > 0 
                      ? null 
                      : _sendOtp,
                  child: Text(
                    _resendSeconds > 0 
                        ? "Resend OTP in $_resendSeconds s" 
                        : "Resend OTP",
                  ),
                ),
                ElevatedButton(
                  onPressed: _isVerifyingEmail ? null : _verifyOtp,
                  child: _isVerifyingEmail
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Verify OTP"),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            const Text(
              "We'll send a verification code to this email",
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isVerifyingEmail ? null : _sendOtp,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _isVerifyingEmail
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text("Send OTP"),
            ),
            const SizedBox(height: 20),
            const Text(
              "OR",
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              icon: Image.asset(
                'assets/google_logo.png',
                height: 24,
              ),
              label: const Text("Continue with Google"),
              onPressed: _isVerifyingEmail ? null : _signInWithGoogle,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
          
          const SizedBox(height: 30),
          Row(
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
          ),
        ],
      ),
    );
  }

  Widget _buildRegistrationForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          const Text(
            "Complete Your Registration",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
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
            ),
          ),
          const SizedBox(height: 20),
          _buildPhoneField(),
          const SizedBox(height: 20),
          _buildPasswordField(),
          const SizedBox(height: 20),
          _buildConfirmPasswordField(),
          const SizedBox(height: 20),
          _buildAddressSection(),
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

  Widget _buildSignUpButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleSignUp,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Text(
                "Sign Up",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
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
