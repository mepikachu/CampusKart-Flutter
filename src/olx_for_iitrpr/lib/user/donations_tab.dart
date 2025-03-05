import 'package:flutter/material.dart';

class DonationsTab extends StatelessWidget {
  const DonationsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              "Donations",
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: 10, // Replace with the actual number of donation items
                itemBuilder: (context, index) {
                  return Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: const Icon(Icons.volunteer_activism, color: Colors.blue),
                      ),
                      title: Text("Donation Item ${index + 1}"),
                      subtitle: Text("Description of donation item ${index + 1}"),
                      trailing: ElevatedButton(
                        onPressed: () {
                          // Handle donation action here
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("You requested Donation Item ${index + 1}!")),
                          );
                        },
                        child: const Text("Request"),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
