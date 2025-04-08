import 'package:flutter/material.dart';
import 'tab_donations.dart';

class AddDonationScreen extends StatelessWidget {
  const AddDonationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Donation'),
        elevation: 0,
      ),
      body: const DonationsTab(
        showLeaderboard: false,
        labels: DonationLabels(
          imagesSectionTitle: 'Donation Images',
          imagesSubtitle: 'Add up to 5 images of items you want to donate',
          nameLabel: 'Donation Item Name',
          nameHint: 'Enter the name of items you want to donate',
          descriptionLabel: 'Donation Description',
          descriptionHint: 'Describe the items and their condition',
          submitButtonText: 'Submit Donation',
        ),
      ),
    );
  }
}
