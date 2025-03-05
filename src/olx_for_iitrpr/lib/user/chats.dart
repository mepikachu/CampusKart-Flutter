import 'package:flutter/material.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
      ),
      body: ListView.builder(
        itemCount: 10, // Replace with actual number of chats
        itemBuilder: (context, index) {
          return ListTile(
            leading: CircleAvatar(
              child: Text('U${index + 1}'),
            ),
            title: Text('User ${index + 1}'),
            subtitle: Text('Last message from User ${index + 1}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('12:00 PM', style: TextStyle(fontSize: 12)),
                SizedBox(height: 5),
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  radius: 10,
                  child: Text('2', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ],
            ),
            onTap: () {
              // Navigate to individual chat screen
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(userName: 'User ${index + 1}'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ChatScreen extends StatelessWidget {
  final String userName;

  const ChatScreen({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(userName),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: 20, // Replace with actual number of messages
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text('Message ${index + 1}'),
                  subtitle: Text('12:00 PM'),
                  leading: CircleAvatar(
                    child: Text(userName[0]),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Type a message',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send),
                  onPressed: () {
                    // Send message logic here
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
