import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ReportDialog extends StatefulWidget {
  final String userId;
  final String conversationId;

  const ReportDialog({
    Key? key,
    required this.userId,
    required this.conversationId,
  }) : super(key: key);

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  final _storage = const FlutterSecureStorage();
  final _detailsController = TextEditingController();
  String _selectedReason = 'spam';
  bool _includeChat = false;
  bool _isSubmitting = false;
  final List<Map<String, String>> _reasons = [
    {'value': 'spam', 'label': 'Spam'},
    {'value': 'harassment', 'label': 'Harassment'},
    {'value': 'inappropriate_content', 'label': 'Inappropriate Content'},
    {'value': 'fake_account', 'label': 'Fake Account'},
    {'value': 'other', 'label': 'Other'},
  ];

  Future<void> _submitReport() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final authCookie = await _storage.read(key: 'authCookie');
      
      if (authCookie == null) {
        throw Exception('Authentication required');
      }

      // Print request data for debugging
      print('Sending report with data:');
      print('reportedUserId: ${widget.userId}');
      print('reason: $_selectedReason');
      print('details: ${_detailsController.text}');
      print('includeChat: $_includeChat');
      print('conversationId: ${_includeChat ? widget.conversationId : null}');

      final response = await http.post(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/reports'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie,
        },
        body: json.encode({
          'reportedUserId': widget.userId,
          'reason': _selectedReason,
          'details': _detailsController.text.trim(),
          'includeChat': _includeChat,
          'conversationId': _includeChat ? widget.conversationId : null,
        }),
      );

      // Print response for debugging
      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (mounted) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          try {
            final data = json.decode(response.body);
            Navigator.of(context).pop(true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(data['message'] ?? 'Report submitted successfully')),
            );
          } catch (e) {
            print('JSON decode error: $e');
            Navigator.of(context).pop(true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Report submitted successfully')),
            );
          }
        } else {
          String errorMessage = 'Failed to submit report';
          print('Error response: ${response.body}');
          try {
            final data = json.decode(response.body);
            errorMessage = data['message'] ?? errorMessage;
          } catch (e) {
            print('Error parsing response: $e');
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage)),
          );
        }
      }
    } catch (e) {
      print('Error submitting report: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.report_problem, color: Colors.red),
                  const SizedBox(width: 8),
                  const Text(
                    'Report User',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Reason for reporting',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedReason,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: _reasons.map((reason) {
                  return DropdownMenuItem<String>(
                    value: reason['value'],
                    child: Text(reason['label']!),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedReason = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Additional Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _detailsController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Please provide more details about your report...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                maxLength: 500,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _includeChat,
                onChanged: (value) {
                  setState(() {
                    _includeChat = value ?? false;
                  });
                },
                title: const Text('Include chat history with report'),
                subtitle: const Text(
                  'This will help our team better understand the context',
                  style: TextStyle(fontSize: 12),
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitReport,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.red,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Submit Report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }
}
