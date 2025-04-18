import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'view_chat.dart';
import 'view_profile.dart';
import 'view_product.dart';

class ReportDetailScreen extends StatefulWidget {
  final String reportId;
  final String reportType;
  
  const ReportDetailScreen({
    Key? key, 
    required this.reportId, 
    required this.reportType
  }) : super(key: key);

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  final _secureStorage = const FlutterSecureStorage();
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _blockReasonController = TextEditingController();
  final TextEditingController _warningMessageController = TextEditingController();
  final TextEditingController _deleteReasonController = TextEditingController();
  
  bool _isLoading = true;
  bool _isError = false;
  bool _isPerformingAction = false;
  String _errorMessage = '';
  Map<String, dynamic>? _reportData;
  bool _hasConversation = false;
  List<String> _participantNames = [];
  
  // Track which action dialog is open
  String? _currentActionDialog;

  // Store profile pictures URLs
  Map<String, String> _profilePicUrls = {};

  @override
  void initState() {
    super.initState();
    _fetchReportDetails();
  }
  
  @override
  void dispose() {
    _remarksController.dispose();
    _blockReasonController.dispose();
    _warningMessageController.dispose();
    _deleteReasonController.dispose();
    super.dispose();
  }

  // Show notification as a floating SnackBar
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

  Future<void> _fetchReportDetails() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/${widget.reportId}?type=${widget.reportType}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _reportData = data['report'];
          if (_reportData != null && _reportData!['adminNotes'] != null) {
            _remarksController.text = _reportData!['adminNotes'];
          }
          
          // Check if conversation is included
          _hasConversation = _reportData != null && 
                           _reportData!['includeChat'] == true && 
                           _reportData!['conversationId'] != null;
          
          _isLoading = false;
        });
        
        // Fetch profile pictures for reporter and reported user
        _fetchUserProfilePictures();
        
      } else {
        setState(() {
          _isError = true;
          _errorMessage = data['message'] ?? 'Failed to load report details';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isError = true;
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }
  
  // Fetch profile pictures for users
  Future<void> _fetchUserProfilePictures() async {
    if (_reportData == null) return;
    
    final authCookie = await _secureStorage.read(key: 'authCookie');
    
    // Fetch reporter's profile picture
    if (_reportData!['reporter'] != null && _reportData!['reporter']['_id'] != null) {
      try {
        final reporterId = _reportData!['reporter']['_id'];
        final response = await http.get(
          Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/users/profile-picture/$reporterId'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie ?? '',
          },
        );
        
        if (response.statusCode == 200) {
          setState(() {
            _profilePicUrls[reporterId] = response.body;
          });
        }
      } catch (e) {
        // Silently fail, will use fallback avatar
      }
    }
    
    // Fetch reported user's profile picture for user reports
    if (widget.reportType == 'user' && 
        _reportData!['reportedUser'] != null && 
        _reportData!['reportedUser']['_id'] != null) {
      try {
        final reportedUserId = _reportData!['reportedUser']['_id'];
        final response = await http.get(
          Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/users/profile-picture/$reportedUserId'),
          headers: {
            'Content-Type': 'application/json',
            'auth-cookie': authCookie ?? '',
          },
        );
        
        if (response.statusCode == 200) {
          setState(() {
            _profilePicUrls[reportedUserId] = response.body;
          });
        }
      } catch (e) {
        // Silently fail, will use fallback avatar
      }
    }
  }
  
  // Updated to use /reports/:reportId/resolve/dismiss endpoint
  Future<void> _dismissReport() async {
    setState(() {
      _isPerformingAction = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/${widget.reportId}/resolve/dismiss'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'adminNotes': _remarksController.text,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _showTopSnackBar('Report dismissed successfully', isError: false);
        
        setState(() {
          if (_reportData != null) {
            _reportData!['status'] = 'dismissed';
          }
        });
      } else {
        _showTopSnackBar(data['message'] ?? 'Failed to dismiss report');
      }
    } catch (e) {
      _showTopSnackBar('Error: $e');
    } finally {
      setState(() {
        _isPerformingAction = false;
      });
    }
  }
  
  // Updated to use /reports/:reportId/resolve/block-user endpoint
  Future<void> _blockUser(String reason) async {
    setState(() {
      _isPerformingAction = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/${widget.reportId}/resolve/block-user'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'adminNotes': _remarksController.text,
          'blockReason': reason,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _showTopSnackBar('User blocked successfully', isError: false);
        
        setState(() {
          if (_reportData != null) {
            _reportData!['status'] = 'resolved';
            _reportData!['adminAction'] = 'blocked';
            _reportData!['blockReason'] = reason;
          }
        });
      } else {
        _showTopSnackBar(data['message'] ?? 'Failed to block user');
      }
    } catch (e) {
      _showTopSnackBar('Error: $e');
    } finally {
      setState(() {
        _isPerformingAction = false;
        _currentActionDialog = null;
      });
    }
  }
  
  // Updated to use /reports/:reportId/resolve/issue-warning endpoint
  Future<void> _warnUser(String warningMessage) async {
    setState(() {
      _isPerformingAction = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/${widget.reportId}/resolve/issue-warning'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'adminNotes': _remarksController.text,
          'warningMessage': warningMessage,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _showTopSnackBar('Warning sent to user successfully', isError: false);
        
        setState(() {
          if (_reportData != null) {
            _reportData!['status'] = 'resolved';
            _reportData!['adminAction'] = 'warned';
            _reportData!['warningMessage'] = warningMessage;
          }
        });
      } else {
        _showTopSnackBar(data['message'] ?? 'Failed to send warning');
      }
    } catch (e) {
      _showTopSnackBar('Error: $e');
    } finally {
      setState(() {
        _isPerformingAction = false;
        _currentActionDialog = null;
      });
    }
  }
  
  // Updated to use /reports/:reportId/resolve/delete-product endpoint
  Future<void> _deleteProduct(String deleteReason) async {
    setState(() {
      _isPerformingAction = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/${widget.reportId}/resolve/delete-product'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'adminNotes': _remarksController.text,
          'deleteReason': deleteReason,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _showTopSnackBar('Product deleted successfully', isError: false);
        
        setState(() {
          if (_reportData != null) {
            _reportData!['status'] = 'resolved';
            _reportData!['adminAction'] = 'deleted_product';
          }
        });
      } else {
        _showTopSnackBar(data['message'] ?? 'Failed to delete product');
      }
    } catch (e) {
      _showTopSnackBar('Error: $e');
    } finally {
      setState(() {
        _isPerformingAction = false;
        _currentActionDialog = null;
      });
    }
  }
  
  Future<void> _viewUserProfile(String userId) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminProfileView(userId: userId),
      ),
    );
  }
  
  Future<void> _viewProductDetails(String productId) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminProductView(productId: productId),
      ),
    );
  }
  
  // View full conversation history - now just navigates to view_chat.dart
  Future<void> _viewConversation() async {
    if (!_hasConversation) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminChatHistoryView(
          reportId: widget.reportId,
          participants: _participantNames,
        ),
      ),
    );
  }
  
  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return 'N/A';
    
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return DateFormat('MMM d, yyyy h:mm a').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }
  
  String _getReasonText(String reason) {
    if (widget.reportType == 'user') {
      switch (reason) {
        case 'spam':
          return 'Spam';
        case 'harassment':
          return 'Harassment';
        case 'inappropriate_content':
          return 'Inappropriate Content';
        case 'fake_account':
          return 'Fake Account';
        case 'other':
          return 'Other';
        default:
          return reason;
      }
    } else {
      return reason;
    }
  }
  
  // Show block user dialog
  void _showBlockUserDialog() {
    setState(() {
      _currentActionDialog = 'block';
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please provide a reason for blocking this user:'),
            const SizedBox(height: 16),
            TextField(
              controller: _blockReasonController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter block reason',
                labelText: 'Reason',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _currentActionDialog = null;
              });
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_blockReasonController.text.trim().isEmpty) {
                _showTopSnackBar('Please enter a reason for blocking');
                return;
              }
              Navigator.of(context).pop();
              _blockUser(_blockReasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Block User'),
          ),
        ],
      ),
    );
  }
  
  // Show warning dialog
  void _showWarningDialog() {
    setState(() {
      _currentActionDialog = 'warn';
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Send Warning'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter a warning message to send to the user:'),
            const SizedBox(height: 16),
            TextField(
              controller: _warningMessageController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter warning message',
                labelText: 'Warning',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _currentActionDialog = null;
              });
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_warningMessageController.text.trim().isEmpty) {
                _showTopSnackBar('Please enter a warning message');
                return;
              }
              Navigator.of(context).pop();
              _warnUser(_warningMessageController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Warning'),
          ),
        ],
      ),
    );
  }
  
  // Show delete product dialog
  void _showDeleteProductDialog() {
    setState(() {
      _currentActionDialog = 'delete';
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please provide a reason for deleting this product:'),
            const SizedBox(height: 16),
            TextField(
              controller: _deleteReasonController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Enter delete reason',
                labelText: 'Reason',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _currentActionDialog = null;
              });
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_deleteReasonController.text.trim().isEmpty) {
                _showTopSnackBar('Please enter a reason for deleting');
                return;
              }
              Navigator.of(context).pop();
              _deleteProduct(_deleteReasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Product'),
          ),
        ],
      ),
    );
  }
  
  // Show confirmation for resolving report
  void _showResolveActionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Prevents overflow
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Resolve Report',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  subtitle: Text('Choose an action to take:'),
                ),
                const Divider(),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red.shade50,
                    child: Icon(Icons.block, color: Colors.red),
                  ),
                  title: const Text('Block User'),
                  subtitle: const Text('Permanently block this user from the platform'),
                  onTap: () {
                    Navigator.pop(context);
                    _showBlockUserDialog();
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade50,
                    child: Icon(Icons.warning_amber, color: Colors.orange),
                  ),
                  title: const Text('Send Warning'),
                  subtitle: const Text('Send a warning message to the user'),
                  onTap: () {
                    Navigator.pop(context);
                    _showWarningDialog();
                  },
                ),
                if (widget.reportType == 'product')
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.purple.shade50,
                      child: Icon(Icons.delete, color: Colors.purple),
                    ),
                    title: const Text('Delete Product'),
                    subtitle: const Text('Remove this product from the platform'),
                    onTap: () {
                      Navigator.pop(context);
                      _showDeleteProductDialog();
                    },
                  ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(Icons.check_circle, color: Colors.green),
                  ),
                  title: const Text('Resolve Report'),
                  subtitle: const Text('Mark as resolved without taking action'),
                  onTap: () {
                    Navigator.pop(context);
                    _updateReportStatus('resolved');
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey.shade50,
                    child: Icon(Icons.cancel, color: Colors.grey),
                  ),
                  title: const Text('Cancel'),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to resolve report normally
  Future<void> _updateReportStatus(String newStatus) async {
    setState(() {
      _isPerformingAction = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // Use the appropriate endpoint based on status
      final String endpoint = newStatus == 'dismissed' 
          ? 'https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/${widget.reportId}/resolve/dismiss'
          : 'https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/${widget.reportId}/resolve/no-action';
      
      final response = await http.post(
        Uri.parse(endpoint),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'adminNotes': _remarksController.text,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        _showTopSnackBar('Report ${newStatus == 'resolved' ? 'resolved' : 'dismissed'} successfully', isError: false);
        
        setState(() {
          if (_reportData != null) {
            _reportData!['status'] = newStatus;
          }
        });
      } else {
        _showTopSnackBar(data['message'] ?? 'Failed to update report status');
      }
    } catch (e) {
      _showTopSnackBar('Error: $e');
    } finally {
      setState(() {
        _isPerformingAction = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get entity name to show in title
    String entityName = '';
    if (_reportData != null) {
      if (widget.reportType == 'user' && _reportData!['reportedUser'] != null) {
        entityName = _reportData!['reportedUser']['userName'] ?? '';
      } else if (widget.reportType == 'product' && _reportData!['product'] != null) {
        entityName = _reportData!['product']['name'] ?? '';
      }
    }
    
    return Scaffold(
      backgroundColor: Colors.white, // Set entire background to white
      extendBodyBehindAppBar: false, // Prevents content from going behind app bar
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Text(
          '${widget.reportType.capitalize()} Report${entityName.isNotEmpty ? ': $entityName' : ''}',
          style: const TextStyle(color: Colors.black),
        ),
        leading: IconButton(
          icon: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(4),
            child: const Icon(Icons.arrow_back, color: Colors.black),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Container(
        color: Colors.white, // Ensure entire body is white
        child: Stack(
          children: [
            _isLoading
                ? _buildShimmerLoading() // Modern shimmer loading
                : _isError
                    ? _buildErrorView()
                    : _reportData == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.warning_amber_rounded, 
                                     size: 64, 
                                     color: Colors.amber),
                                const SizedBox(height: 16),
                                const Text(
                                  'Report not found',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : _buildReportDetailsView(),
            
            // Loading overlay
            if (_isPerformingAction)
              Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  // Modern shimmer loading animation
  Widget _buildShimmerLoading() {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status indicator
              Container(
                width: double.infinity,
                height: 40,
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 24),
              ),
              
              // Report details section
              Container(
                width: 150,
                height: 24,
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 12),
              ),
              
              Container(
                width: double.infinity,
                height: 1,
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 16),
              ),
              
              // Report fields
              for (int i = 0; i < 3; i++) ...[
                Container(
                  width: 100,
                  height: 16,
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 8),
                ),
                Container(
                  width: double.infinity,
                  height: 20,
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 16),
                ),
              ],
              
              // Reporter section
              Container(
                width: 180,
                height: 24,
                color: Colors.white,
                margin: const EdgeInsets.only(top: 8, bottom: 12),
              ),
              
              Container(
                width: double.infinity,
                height: 1,
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 16),
              ),
              
              // Reporter info
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 150,
                          height: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 200,
                          height: 14,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 24),
              
              // Reported entity section
              Container(
                width: 180,
                height: 24,
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 12),
              ),
              
              Container(
                width: double.infinity,
                height: 1,
                color: Colors.white,
                margin: const EdgeInsets.only(bottom: 16),
              ),
              
              // Reported entity info
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 150,
                          height: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 200,
                          height: 14,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '☹️',
              style: TextStyle(fontSize: 64),
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade800),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchReportDetails,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildReportDetailsView() {
    final status = _reportData!['status'] ?? 'pending';
    
    return RefreshIndicator(
      onRefresh: _fetchReportDetails,
      child: ListView(
        padding: EdgeInsets.zero, // Fix for potential overflow
        children: [
          // Status banner - FULL WIDTH RECTANGLE as requested
          Container(
            width: double.infinity,
            color: _getStatusColor(status).withOpacity(0.1),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _getStatusIcon(status),
                  const SizedBox(width: 8),
                  Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(status),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Report details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Report reason
                const Text(
                  'Report Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                
                // Reported on - each field on a new line with bold labels
                const Text(
                  'Reported on:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(_formatDateTime(_reportData!['createdAt']?.toString())),
                
                const SizedBox(height: 16),
                
                // Reason
                const Text(
                  'Reason:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(_getReasonText(_reportData!['reason']?.toString() ?? 'Not specified')),
                
                // Details if available
                if (_reportData!['details'] != null || _reportData!['description'] != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Details:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_reportData!['details']?.toString() ?? _reportData!['description']?.toString() ?? 'None provided'),
                ],
                
                const SizedBox(height: 24),
                
                // Reporter information
                const Text(
                  'Reporter User',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                
                _buildReporterInfo(),
                
                const SizedBox(height: 24),
                
                // Reported user/product information
                Text(
                  widget.reportType == 'user' ? 'Reported User' : 'Reported Product',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                
                _buildReportedEntityInfo(),
                
                const SizedBox(height: 24),
                
                // Conversation Section - Only show that conversation is shared with a button
                if (_hasConversation) ...[
                  const Text(
                    'Conversation',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              color: Colors.blue.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Conversation is shared with this report',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _viewConversation,
                          icon: const Icon(Icons.remove_red_eye),
                          label: const Text('View Conversation'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 40),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                ],
                
                // Remarks section (renamed from Admin Notes)
                const Text(
                  'Remarks',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                
                _buildRemarksSection(),
                
                const SizedBox(height: 24),
                
                // Actions for pending reports
                if (status == 'pending')
                  _buildActionButtons(),
                
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildReporterInfo() {
    final reporter = _reportData!['reporter'];
    final userName = reporter != null ? reporter['userName'] ?? 'Unknown User' : 'Unknown User';
    final email = reporter != null ? reporter['email'] : null;
    final reporterId = reporter != null ? reporter['_id'] : null;
    final String? profilePicUrl = _profilePicUrls[reporterId];
    
    return InkWell(
      onTap: reporterId != null ? () => _viewUserProfile(reporterId) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            // User avatar - profile pic if available, otherwise first letter
            profilePicUrl != null && profilePicUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(
                      profilePicUrl,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        radius: 20,
                        child: Text(
                          userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                          style: TextStyle(color: Colors.blue.shade800),
                        ),
                      ),
                    ),
                  )
                : CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    radius: 20,
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                      style: TextStyle(color: Colors.blue.shade800),
                    ),
                  ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (email != null)
                    Text(
                      email.toString(),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildReportedEntityInfo() {
    final bool isUserReport = widget.reportType == 'user';
    
    // Get reported entity data based on report type
    final reportedEntity = isUserReport ? _reportData!['reportedUser'] : _reportData!['product'];
    
    if (reportedEntity == null) {
      return const Text('Entity information not available');
    }
    
    final entityName = isUserReport 
        ? (reportedEntity['userName'] ?? 'Unknown User')
        : (reportedEntity['name'] ?? 'Unknown Product');
    final entityId = reportedEntity['_id'];
    
    // For user report, get profile pic URL
    final String? profilePicUrl = isUserReport ? _profilePicUrls[entityId] : null;
    
    return InkWell(
      onTap: entityId != null 
          ? () => isUserReport 
              ? _viewUserProfile(entityId) 
              : _viewProductDetails(entityId)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          children: [
            // Entity avatar/image
            if (isUserReport && profilePicUrl != null && profilePicUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  profilePicUrl,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => CircleAvatar(
                    backgroundColor: Colors.red.shade100,
                    radius: 20,
                    child: Icon(
                      Icons.person,
                      color: Colors.red.shade800,
                    ),
                  ),
                ),
              )
            else
              CircleAvatar(
                backgroundColor: isUserReport ? Colors.red.shade100 : Colors.orange.shade100,
                radius: 20,
                child: Icon(
                  isUserReport ? Icons.person : Icons.shopping_bag,
                  color: isUserReport ? Colors.red.shade800 : Colors.orange.shade800,
                ),
              ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entityName.toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (isUserReport && reportedEntity['email'] != null)
                    Text(
                      reportedEntity['email'].toString(),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    )
                  else if (!isUserReport && reportedEntity['price'] != null)
                    Text(
                      '₹${reportedEntity['price']}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Renamed from _buildAdminNotesSection to _buildRemarksSection
  Widget _buildRemarksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Block reason if available
        if (_reportData!['blockReason'] != null) ...[
          Text(
            'Block Reason:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red.shade700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(_reportData!['blockReason'].toString()),
          const Divider(height: 24),
        ],
        
        // Warning message if available
        if (_reportData!['warningMessage'] != null) ...[
          Text(
            'Warning Message:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(_reportData!['warningMessage'].toString()),
          const Divider(height: 24),
        ],
        
        // Action taken if available
        if (_reportData!['adminAction'] != null) ...[
          Text(
            'Action Taken:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(_getAdminActionText(_reportData!['adminAction'].toString())),
          const Divider(height: 24),
        ],
        
        // Remarks editor for pending reports, text for others
        if (_reportData!['status'] == 'pending') ...[
          TextField(
            controller: _remarksController,
            decoration: const InputDecoration(
              hintText: 'Add remarks that will be visible to the user...',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
            ),
            maxLines: 4,
          ),
        ] else if (_remarksController.text.isNotEmpty) ...[
          Text(
            'Remarks:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(_remarksController.text),
        ] else
          Text(
            'No remarks',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }
  
  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 16),
        
        ElevatedButton.icon(
          onPressed: _showResolveActionSheet,
          icon: const Icon(Icons.check_circle),
          label: const Text('Resolve Report'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _dismissReport,
          icon: const Icon(Icons.cancel),
          label: const Text('Dismiss Report'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey.shade700,
            side: BorderSide(color: Colors.grey.shade400),
            minimumSize: const Size(double.infinity, 48),
          ),
        ),
      ],
    );
  }
  
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'dismissed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
  
  Widget _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icon(Icons.pending, color: Colors.orange, size: 20); // Clock icon for pending
      case 'resolved':
        return Icon(Icons.check_circle, color: Colors.green, size: 20); // Tick mark for resolved
      case 'dismissed':
        return Icon(Icons.cancel, color: Colors.red, size: 20); // Cross mark for dismissed
      default:
        return Icon(Icons.help, color: Colors.grey, size: 20);
    }
  }
  
  String _getAdminActionText(String? action) {
    if (action == null) return 'None';
    
    switch (action) {
      case 'blocked':
        return 'User Blocked';
      case 'warned':
        return 'Warning Sent';
      case 'deleted_product':
        return 'Product Deleted';
      default:
        return action.replaceAll('_', ' ').capitalize();
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}