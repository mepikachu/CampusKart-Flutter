import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class AdminChatHistoryView extends StatefulWidget {
  final String reportId;
  final List<String> participants;

  const AdminChatHistoryView({
    Key? key,
    required this.reportId,
    required this.participants,
  }) : super(key: key);

  @override
  State<AdminChatHistoryView> createState() => _AdminChatHistoryViewState();
}

class _AdminChatHistoryViewState extends State<AdminChatHistoryView> {
  final _secureStorage = const FlutterSecureStorage();
  bool _isLoading = true;
  bool _isError = false;
  String _errorMessage = '';
  List<dynamic> _messages = [];
  Map<String, String> _userIdToNameMap = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchChatHistory();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchChatHistory() async {
    setState(() {
      _isLoading = true;
      _isError = false;
    });

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final response = await http.get(
        Uri.parse('https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/${widget.reportId}/messages'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        // Create a mapping of user IDs to usernames from participants in the conversation
        if (data['conversation'] != null && data['conversation']['participants'] != null) {
          final participants = data['conversation']['participants'] as List;
          for (var participant in participants) {
            _userIdToNameMap[participant['_id']] = participant['userName'] ?? 'Unknown User';
          }
        }

        // Process messages - they are nested inside the conversation object
        final List<dynamic> rawMessages = data['conversation']?['messages'] ?? [];
        
        setState(() {
          // Transform messages to the format expected by the UI
          _messages = rawMessages.map((msg) => {
            'sender': {
              '_id': msg['sender'],
              'userName': _userIdToNameMap[msg['sender']] ?? 'Unknown User'
            },
            'content': msg['text'] ?? '',
            'createdAt': msg['createdAt']
          }).toList();
          _isLoading = false;
        });
        
        // Scroll to bottom after messages are loaded
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      } else {
        setState(() {
          _isError = true;
          _errorMessage = data['message'] ?? 'Failed to load chat history';
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
  
  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return DateFormat('MMM d, h:mm a').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Conversation Information'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'This is a conversation shared as part of a report. All messages are displayed for moderation purposes only.',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      const Text('Participants:'),
                      const SizedBox(height: 8),
                      ...widget.participants.map((name) => Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 4),
                        child: Text('• $name'),
                      )).toList(),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _isLoading
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
                        onPressed: _fetchChatHistory,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _messages.isEmpty
                  ? const Center(child: Text('No messages in this conversation'))
                  : _buildChatView(),
    );
  }
  
  Widget _buildChatView() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final bool isFirstMessageFromSender = index == 0 || 
            _messages[index - 1]['sender']['_id'] != message['sender']['_id'];
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isFirstMessageFromSender) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 4.0),
                  child: Text(
                    message['sender']['userName'] ?? 'Unknown User',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isFirstMessageFromSender)
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.blue.shade100,
                      child: Text(
                        (message['sender']['userName'] ?? 'U')[0].toUpperCase(),
                        style: TextStyle(
                          color: Colors.blue.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 32),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message['content'] ?? '',
                            style: const TextStyle(fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateTime(message['createdAt']),
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
