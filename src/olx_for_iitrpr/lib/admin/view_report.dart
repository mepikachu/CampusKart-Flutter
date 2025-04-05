import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'view_profile.dart';
import 'view_product.dart';
import 'view_chat.dart';

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
  bool _isLoading = true;
  bool _isError = false;
  bool _isPerformingAction = false;
  String _errorMessage = '';
  Map<String, dynamic>? _reportData;
  final TextEditingController _adminNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchReportDetails();
  }
  
  @override
  void dispose() {
    _adminNotesController.dispose();
    super.dispose();
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
            _adminNotesController.text = _reportData!['adminNotes'];
          }
          _isLoading = false;
        });
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
  
  Future<void> _updateReportStatus(String newStatus) async {
    setState(() {
      _isPerformingAction = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.patch(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/${widget.reportId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'status': newStatus,
          'type': widget.reportType,
          'adminNotes': _adminNotesController.text,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report status updated to $newStatus')),
        );
        
        setState(() {
          if (_reportData != null) {
            _reportData!['status'] = newStatus;
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Failed to update report status')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isPerformingAction = false;
      });
    }
  }
  
  Future<void> _saveAdminNotes() async {
    setState(() {
      _isPerformingAction = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.patch(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/${widget.reportId}'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'type': widget.reportType,
          'adminNotes': _adminNotesController.text,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin notes saved successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Failed to save admin notes')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isPerformingAction = false;
      });
    }
  }
  
  Future<void> _blockUser() async {
    // Ask for confirmation
    bool confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content: const Text('Are you sure you want to block this user? They will not be able to use the application.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    ) ?? false;
    
    if (!confirmed) return;
    
    setState(() {
      _isPerformingAction = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/${widget.reportId}/block-user'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'type': widget.reportType,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked successfully')),
        );
        
        setState(() {
          if (_reportData != null) {
            _reportData!['status'] = 'resolved';
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Failed to block user')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isPerformingAction = false;
      });
    }
  }
  
  Future<void> _deleteProduct() async {
    // Ask for confirmation
    bool confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: const Text('Are you sure you want to delete this product? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ?? false;
    
    if (!confirmed) return;
    
    setState(() {
      _isPerformingAction = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.delete(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/${widget.reportId}/delete-product'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product deleted successfully')),
        );
        
        setState(() {
          if (_reportData != null) {
            _reportData!['status'] = 'resolved';
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Failed to delete product')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isPerformingAction = false;
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
  
  Future<void> _viewChatHistory() async {
    if (_reportData == null || _reportData!['includeChat'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No chat history available or user did not consent to share')),
      );
      return;
    }
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminChatHistoryView(
          reportId: widget.reportId,
          participants: [
            _reportData!['reporter']['userName'] ?? 'Reporter',
            _reportData!['reportedUser']['userName'] ?? 'Reported User',
          ],
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.reportType.capitalize()} Report Details'),
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _isError
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(_errorMessage),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _fetchReportDetails,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _reportData == null
                      ? const Center(child: Text('Report not found'))
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
    );
  }
  
  Widget _buildReportDetailsView() {
    final status = _reportData!['status'] ?? 'pending';
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Report status banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: _getStatusColor(status).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _getStatusColor(status)),
            ),
            child: Row(
              children: [
                Icon(
                  _getStatusIcon(status),
                  color: _getStatusColor(status),
                ),
                const SizedBox(width: 12),
                Text(
                  'Status: ${status.toUpperCase()}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: _getStatusColor(status),
                  ),
                ),
                const Spacer(),
                if (status == 'pending')
                  PopupMenuButton<String>(
                    onSelected: _updateReportStatus,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'resolved',
                        child: Text('Mark as Resolved'),
                      ),
                      const PopupMenuItem(
                        value: 'dismissed',
                        child: Text('Dismiss Report'),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text('Update'),
                          SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down, size: 20),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Report basic info
          Text(
            widget.reportType == 'user' ? 'User Report' : 'Product Report',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Report creation date
          Text(
            'Reported on: ${_formatDateTime(_reportData!['createdAt'])}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
          
          // If reviewed, show review date
          if (_reportData!['reviewedAt'] != null) ...[
            const SizedBox(height: 4),
            Text(
              'Reviewed on: ${_formatDateTime(_reportData!['reviewedAt'])}',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ],
          
          const SizedBox(height: 24),
          
          // Report reason
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Reason for Report:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _getReasonText(_reportData!['reason'] ?? 'Not specified'),
                  style: const TextStyle(
                    fontSize: 18,
                  ),
                ),
                
                if (_reportData!['details'] != null || _reportData!['description'] != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Additional Details:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _reportData!['details'] ?? _reportData!['description'] ?? 'None provided',
                    style: const TextStyle(fontSize: 15),
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Reporter information
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reporter Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade100,
                      child: const Icon(Icons.person, color: Colors.blue),
                    ),
                    title: Text(
                      _reportData!['reporter'] != null 
                          ? _reportData!['reporter']['userName'] ?? 'Unknown User'
                          : 'Unknown User',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: _reportData!['reporter'] != null && _reportData!['reporter']['email'] != null
                        ? Text(_reportData!['reporter']['email'])
                        : null,
                    trailing: ElevatedButton(
                      onPressed: () {
                        if (_reportData!['reporter'] != null && _reportData!['reporter']['_id'] != null) {
                          _viewUserProfile(_reportData!['reporter']['_id']);
                        }
                      },
                      child: const Text('View Profile'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Reported User or Product information
          Card(
            elevation: 2,
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.reportType == 'user' 
                        ? 'Reported User Information' 
                        : 'Reported Product Information',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  widget.reportType == 'user'
                      ? _buildReportedUserDetails()
                      : _buildReportedProductDetails(),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),

          // Chat history section (only for user reports)
          if (widget.reportType == 'user') ...[
            Card(
              elevation: 2,
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Conversation History',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _reportData!['includeChat'] == true 
                        ? const Text(
                            'The reporter has shared their conversation history as evidence.',
                            style: TextStyle(fontSize: 14),
                          )
                        : const Text(
                            'No conversation was shared with this report.',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.chat),
                        label: const Text('View Conversation'),
                        onPressed: _reportData!['includeChat'] == true 
                            ? _viewChatHistory 
                            : null, // Disable button if no chat is shared
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
          
          // Admin notes
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Admin Notes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _adminNotesController,
                    decoration: const InputDecoration(
                      hintText: 'Add notes about this report...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Save Notes'),
                      onPressed: _saveAdminNotes,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Actions
          if (status == 'pending') ...[
            const Text(
              'Actions',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Mark as Resolved'),
                    onPressed: () => _updateReportStatus('resolved'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.block),
                    label: const Text('Block User'),
                    onPressed: _blockUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.reportType == 'product')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete Product'),
                  onPressed: _deleteProduct,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.close),
                label: const Text('Dismiss Report'),
                onPressed: () => _updateReportStatus('dismissed'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
  
  Widget _buildReportedUserDetails() {
    final reportedUser = _reportData!['reportedUser'];
    
    if (reportedUser == null) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: Colors.red,
          child: Icon(Icons.error, color: Colors.white),
        ),
        title: Text('User information not found'),
      );
    }
    
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Colors.red.shade100,
        child: const Icon(Icons.person_off, color: Colors.red),
      ),
      title: Text(
        reportedUser['userName'] ?? 'Unknown User',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: reportedUser['email'] != null
          ? Text(reportedUser['email'])
          : null,
      trailing: ElevatedButton(
        onPressed: () {
          if (reportedUser['_id'] != null) {
            _viewUserProfile(reportedUser['_id']);
          }
        },
        child: const Text('View Profile'),
      ),
    );
  }
  
  Widget _buildReportedProductDetails() {
    final reportedProduct = _reportData!['product'];
    
    if (reportedProduct == null) {
      return const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: CircleAvatar(
          backgroundColor: Colors.red,
          child: Icon(Icons.error, color: Colors.white),
        ),
        title: Text('Product information not found'),
      );
    }
    
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Colors.orange.shade100,
        child: const Icon(Icons.shopping_bag, color: Colors.orange),
      ),
      title: Text(
        reportedProduct['name'] ?? 'Unknown Product',
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: reportedProduct['price'] != null
          ? Text('Price: ₹${reportedProduct['price']}')
          : null,
      trailing: ElevatedButton(
        onPressed: () {
          if (reportedProduct['_id'] != null) {
            _viewProductDetails(reportedProduct['_id']);
          }
        },
        child: const Text('View Product'),
      ),
    );
  }
  
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'dismissed':
      case 'rejected':
        return Colors.red;
      case 'reviewed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
  
  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Icons.pending_actions;
      case 'resolved':
        return Icons.check_circle;
      case 'dismissed':
      case 'rejected':
        return Icons.cancel;
      case 'reviewed':
        return Icons.visibility;
      default:
        return Icons.help;
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
