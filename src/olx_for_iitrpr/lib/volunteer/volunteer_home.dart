import 'package:flutter/material.dart';

class VolunteerHomeScreen extends StatelessWidget {
  const VolunteerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Volunteer Home"),
      ),
      body: const Center(
        child: Text("Welcome, Volunteer!"),
      ),
    );
  }
}