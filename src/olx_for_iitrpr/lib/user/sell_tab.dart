import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('SellTab');

class SellTab extends StatefulWidget {
  const SellTab({super.key});

  @override
  State<SellTab> createState() => _SellTabState();
}

class _SellTabState extends State<SellTab> {
  final _formKey = GlobalKey<FormState>();
  String _title = '';
  String _description = '';
  double _price = 0.0;
  String _category = 'Electronics';

  final List<String> _categories = [
    'Electronics',
    'Furniture',
    'Books',
    'Clothing',
    'Other'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sell an Item',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
                onSaved: (value) => _title = value!,
              ),
              const SizedBox(height: 20),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
                onSaved: (value) => _description = value!,
              ),
              const SizedBox(height: 20),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Price',
                  border: OutlineInputBorder(),
                  prefixText: '₹ ',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a price';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
                onSaved: (value) => _price = double.parse(value!),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                value: _category,
                items: _categories.map((String category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _category = newValue!;
                  });
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _formKey.currentState!.save();
                    // Here you would typically send the data to your backend
                    // For now, we'll just print it
                    _logger.info('Title: $_title');
                    _logger.info('Description: $_description');
                    _logger.info('Price: $_price');
                    _logger.info('Category: $_category');
                                        
                    // Show a success message
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Item posted successfully!')),
                    );
                    
                    // Clear the form
                    _formKey.currentState!.reset();
                  }
                },
                child: const Text('Post Item'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
