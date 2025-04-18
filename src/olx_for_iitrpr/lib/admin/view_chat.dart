import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../config/api_config.dart';

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
  Map<String, Color> _userIdToColorMap = {};
  final ScrollController _scrollController = ScrollController();
  
  // List of colors for different users
  final List<Color> _userColors = [
    Colors.blue,
    Colors.green,
    Colors.purple,
    Colors.orange,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
    Colors.brown,
  ];

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
        Uri.parse('${ApiConfig.baseUrl}/api/admin/reports/${widget.reportId}/messages'),
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
          int colorIndex = 0;
          
          for (var participant in participants) {
            final userId = participant['_id'];
            _userIdToNameMap[userId] = participant['userName'] ?? 'Unknown User';
            
            // Assign a color to this user
            _userIdToColorMap[userId] = _userColors[colorIndex % _userColors.length];
            colorIndex++;
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
      return DateFormat('h:mm a').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }
  
  String _formatMessageDate(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
      
      if (messageDate == today) {
        return 'Today';
      } else if (messageDate == yesterday) {
        return 'Yesterday';
      } else if (now.difference(messageDate).inDays < 7) {
        return DateFormat('EEEE').format(dateTime); // Day name like "Monday"
      } else {
        return DateFormat('MMMM d, yyyy').format(dateTime); // Full date
      }
    } catch (e) {
      return dateTimeStr;
    }
  }
  
  bool _shouldShowDateHeader(int index) {
    if (index == 0) return true;
    
    final currentMessageDate = DateTime.parse(_messages[index]['createdAt']);
    final previousMessageDate = DateTime.parse(_messages[index - 1]['createdAt']);
    
    return currentMessageDate.year != previousMessageDate.year ||
           currentMessageDate.month != previousMessageDate.month ||
           currentMessageDate.day != previousMessageDate.day;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chat History',
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${widget.participants.length} participants',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.info_outline, color: Colors.blue.shade700),
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
                      const Text(
                        'Participants:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...widget.participants.map((name) => Padding(
                        padding: const EdgeInsets.only(left: 16, bottom: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.person, size: 16),
                            const SizedBox(width: 8),
                            Text(name),
                          ],
                        ),
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
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.blue.shade700),
            onPressed: _fetchChatHistory,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isError
              ? _buildErrorView()
              : _messages.isEmpty
                  ? _buildEmptyChatView()
                  : _buildChatView(),
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
              onPressed: _fetchChatHistory,
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
  
  Widget _buildEmptyChatView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No messages in this conversation',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchChatHistory,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildChatView() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final senderId = message['sender']['_id'];
        final senderName = message['sender']['userName'] ?? 'Unknown User';
        final bool isFirstMessageFromSender = index == 0 || 
            _messages[index - 1]['sender']['_id'] != senderId;
        final userColor = _userIdToColorMap[senderId] ?? Colors.blue;
        
        // Check if we need to show a date header
        final showDateHeader = _shouldShowDateHeader(index);
        
        return Column(
          children: [
            // Date header when day changes
            if (showDateHeader)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _formatMessageDate(message['createdAt']),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            
            // Message bubble
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Only show avatar for first message in a group
                      if (isFirstMessageFromSender)
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: userColor.withOpacity(0.2),
                          child: Text(
                            senderName[0].toUpperCase(),
                            style: TextStyle(
                              color: userColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 32), // Space for alignment
                        
                      const SizedBox(width: 8),
                      
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Show sender name only for first message in group
                            if (isFirstMessageFromSender)
                              Padding(
                                padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
                                child: Text(
                                  senderName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: userColor,
                                  ),
                                ),
                              ),
                              
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(18).copyWith(
                                  topLeft: isFirstMessageFromSender 
                                      ? const Radius.circular(4) 
                                      : const Radius.circular(18),
                                ),
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
                                ],
                              ),
                            ),
                            
                            // Time below the message
                            Padding(
                              padding: const EdgeInsets.only(left: 4.0, top: 4.0),
                              child: Text(
                                _formatDateTime(message['createdAt']),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
