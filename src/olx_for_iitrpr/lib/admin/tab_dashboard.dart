import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  // Time filters for each tab
  final Map<int, String> _selectedTimeRanges = {
    0: 'Last 30 Days', // Overview
    1: 'Last 30 Days', // Users
    2: 'Last 30 Days', // Products
    3: 'Last 30 Days', // Donations
    4: 'Last 30 Days', // Volunteers
    5: 'Last 30 Days', // Reports
  };
  final List<String> _timeRanges = ['Today', 'Last 7 Days', 'Last 30 Days', 'Last 90 Days', 'This Year', 'All Time'];
  
  // Dashboard data for each tab
  bool _isLoading = true;
  Map<String, dynamic> _overviewData = {};
  Map<String, dynamic> _usersData = {};
  Map<String, dynamic> _productsData = {};
  Map<String, dynamic> _donationsData = {};
  Map<String, dynamic> _volunteersData = {};
  Map<String, dynamic> _reportsData = {};
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(_handleTabChange);
    _fetchAllData();
  }
  
  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    setState(() {});
  }

  Future<void> _fetchAllData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // Fetch data for all tabs
      await Future.wait([
        _fetchOverviewData(authCookie),
        _fetchUsersData(authCookie),
        _fetchProductsData(authCookie),
        _fetchDonationsData(authCookie),
        _fetchVolunteersData(authCookie),
        _fetchReportsData(authCookie)
      ]);
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Separate API calls for each tab
  Future<void> _fetchOverviewData(String? authCookie) async {
    final timeRange = _getTimeRangeParams(_selectedTimeRanges[0]!);
    final response = await http.get(
      Uri.parse(
        'https://olx-for-iitrpr-backend.onrender.com/api/admin/dashboard?startDate=${timeRange['startDate']}&endDate=${timeRange['endDate']}'
      ),
      headers: {
        'Content-Type': 'application/json',
        'auth-cookie': authCookie ?? '',
      },
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        setState(() {
          _overviewData = data;
        });
      }
    }
  }
  
  Future<void> _fetchUsersData(String? authCookie) async {
    final timeRange = _getTimeRangeParams(_selectedTimeRanges[1]!);
    final response = await http.get(
      Uri.parse(
        'https://olx-for-iitrpr-backend.onrender.com/api/admin/users/stats?startDate=${timeRange['startDate']}&endDate=${timeRange['endDate']}'
      ),
      headers: {
        'Content-Type': 'application/json',
        'auth-cookie': authCookie ?? '',
      },
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        setState(() {
          _usersData = data;
        });
      }
    }
  }
  
  Future<void> _fetchProductsData(String? authCookie) async {
    final timeRange = _getTimeRangeParams(_selectedTimeRanges[2]!);
    final response = await http.get(
      Uri.parse(
        'https://olx-for-iitrpr-backend.onrender.com/api/admin/products/stats?startDate=${timeRange['startDate']}&endDate=${timeRange['endDate']}'
      ),
      headers: {
        'Content-Type': 'application/json',
        'auth-cookie': authCookie ?? '',
      },
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        setState(() {
          _productsData = data;
        });
      }
    }
  }
  
  Future<void> _fetchDonationsData(String? authCookie) async {
    final timeRange = _getTimeRangeParams(_selectedTimeRanges[3]!);
    final response = await http.get(
      Uri.parse(
        'https://olx-for-iitrpr-backend.onrender.com/api/admin/donations/stats?startDate=${timeRange['startDate']}&endDate=${timeRange['endDate']}'
      ),
      headers: {
        'Content-Type': 'application/json',
        'auth-cookie': authCookie ?? '',
      },
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        setState(() {
          _donationsData = data;
        });
      }
    }
  }
  
  Future<void> _fetchVolunteersData(String? authCookie) async {
    final timeRange = _getTimeRangeParams(_selectedTimeRanges[4]!);
    final response = await http.get(
      Uri.parse(
        'https://olx-for-iitrpr-backend.onrender.com/api/admin/volunteers/stats?startDate=${timeRange['startDate']}&endDate=${timeRange['endDate']}'
      ),
      headers: {
        'Content-Type': 'application/json',
        'auth-cookie': authCookie ?? '',
      },
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        setState(() {
          _volunteersData = data;
        });
      }
    }
  }
  
  Future<void> _fetchReportsData(String? authCookie) async {
    final timeRange = _getTimeRangeParams(_selectedTimeRanges[5]!);
    final response = await http.get(
      Uri.parse(
        'https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/stats?startDate=${timeRange['startDate']}&endDate=${timeRange['endDate']}'
      ),
      headers: {
        'Content-Type': 'application/json',
        'auth-cookie': authCookie ?? '',
      },
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['success'] == true) {
        setState(() {
          _reportsData = data;
        });
      }
    }
  }
  
  // Update time range for specific tab and refresh its data
  Future<void> _updateTimeRange(int tabIndex, String newValue) async {
    setState(() {
      _selectedTimeRanges[tabIndex] = newValue;
    });
    
    final authCookie = await _secureStorage.read(key: 'authCookie');
    
    switch (tabIndex) {
      case 0:
        await _fetchOverviewData(authCookie);
        break;
      case 1:
        await _fetchUsersData(authCookie);
        break;
      case 2:
        await _fetchProductsData(authCookie);
        break;
      case 3:
        await _fetchDonationsData(authCookie);
        break;
      case 4:
        await _fetchVolunteersData(authCookie);
        break;
      case 5:
        await _fetchReportsData(authCookie);
        break;
    }
  }
  
  Map<String, String> _getTimeRangeParams(String range) {
    final now = DateTime.now();
    late DateTime startDate;
    
    switch (range) {
      case 'Today':
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case 'Last 7 Days':
        startDate = now.subtract(const Duration(days: 7));
        break;
      case 'Last 30 Days':
        startDate = now.subtract(const Duration(days: 30));
        break;
      case 'Last 90 Days':
        startDate = now.subtract(const Duration(days: 90));
        break;
      case 'This Year':
        startDate = DateTime(now.year, 1, 1);
        break;
      case 'All Time':
        startDate = DateTime(2020, 1, 1);
        break;
    }
    
    return {
      'startDate': DateFormat('yyyy-MM-dd').format(startDate),
      'endDate': DateFormat('yyyy-MM-dd').format(now),
    };
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Tab bar without any labels
            Material(
              elevation: 2,
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: Theme.of(context).primaryColor,
                labelColor: Theme.of(context).primaryColor,
                unselectedLabelColor: Colors.grey.shade600,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontSize: 13),
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Users'),
                  Tab(text: 'Products'),
                  Tab(text: 'Donations'),
                  Tab(text: 'Volunteers'),
                  Tab(text: 'Reports'),
                ],
              ),
            ),
            
            // Tab content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildOverviewTab(),
                        _buildUsersTab(),
                        _buildProductsTab(),
                        _buildDonationsTab(),
                        _buildVolunteersTab(),
                        _buildReportsTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final data = _overviewData['success'] == true ? 
        _overviewData['overview'] ?? {} : {};
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calendar in each tab
          Align(
            alignment: Alignment.centerRight,
            child: _buildTimeRangeSelector(0),
          ),
          
          const SizedBox(height: 8),
          
          // Key metrics grid - more compact for mobile
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: [
              _buildCompactMetricCard(
                'Total Users',
                data['totalUsers']?.toString() ?? '0',
                Icons.people,
                Theme.of(context).primaryColor,
              ),
              _buildCompactMetricCard(
                'New Users',
                '+${data['newUsers']?.toString() ?? '0'}',
                Icons.person_add,
                Colors.green,
              ),
              _buildCompactMetricCard(
                'Products',
                data['totalProducts']?.toString() ?? '0',
                Icons.shopping_bag,
                Colors.orange,
              ),
              _buildCompactMetricCard(
                'Sold',
                data['soldProducts']?.toString() ?? '0',
                Icons.check_circle,
                Colors.purple,
              ),
              _buildCompactMetricCard(
                'Donations',
                data['totalDonations']?.toString() ?? '0',
                Icons.volunteer_activism,
                Colors.teal,
              ),
              _buildCompactMetricCard(
                'Reports',
                data['pendingReports']?.toString() ?? '0',
                Icons.flag,
                Colors.red,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // User growth chart
          _buildSectionHeader('User Growth', Icons.trending_up),
          SizedBox(
            height: 180,
            child: _buildLineChart(
              data['userGrowthData'] ?? [], 
              'month', 
              'count',
              Theme.of(context).primaryColor,
              labelFormatter: (value) => _getMonthAbbreviation(value.toInt()),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Category distribution
          _buildSectionHeader('Categories', Icons.pie_chart),
          SizedBox(
            height: 180,
            child: _buildPieChart(data['categoryDistribution'] ?? []),
          ),
          
          const SizedBox(height: 16),
          
          // Recent activity
          _buildSectionHeader('Recent Activity', Icons.history),
          _buildRecentActivityList(data['recentActivity'] ?? []),
        ],
      ),
    );
  }

  Widget _buildUsersTab() {
    final data = _usersData['success'] == true ? 
        _usersData['users'] ?? {} : {};
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calendar in each tab
          Align(
            alignment: Alignment.centerRight,
            child: _buildTimeRangeSelector(1),
          ),
          
          const SizedBox(height: 8),
          
          // Key metrics grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: [
              _buildCompactMetricCard(
                'Total Users',
                data['totalUsers']?.toString() ?? '0',
                Icons.people,
                Theme.of(context).primaryColor,
              ),
              _buildCompactMetricCard(
                'New Users',
                '+${data['newUsers']?.toString() ?? '0'}',
                Icons.person_add,
                Colors.green,
              ),
              _buildCompactMetricCard(
                'Active',
                data['activeUsers']?.toString() ?? '0',
                Icons.person,
                Colors.orange,
              ),
              _buildCompactMetricCard(
                'Inactive',
                data['inactiveUsers']?.toString() ?? '0',
                Icons.person_off,
                Colors.grey,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // User growth chart
          _buildSectionHeader('Monthly Growth', Icons.trending_up),
          SizedBox(
            height: 180,
            child: _buildLineChart(
              data['userGrowth'] ?? [], 
              'month', 
              'count',
              Theme.of(context).primaryColor,
              labelFormatter: (value) => _getMonthAbbreviation(value.toInt()),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // User activity by hour
          _buildSectionHeader('Activity by Hour', Icons.access_time),
          SizedBox(
            height: 160,
            child: _buildBarChart(
              data['userActivity'] ?? [], 
              'hour', 
              'count',
              Colors.orange,
              labelFormatter: (value) => '${value.toInt()}:00',
            ),
          ),
          
          const SizedBox(height: 16),
          
          // User engagement breakdown
          _buildSectionHeader('User Engagement', Icons.pie_chart),
          SizedBox(
            height: 180,
            child: _buildEngagementPieChart(data['userEngagement'] ?? {}),
          ),
          
          const SizedBox(height: 16),
          
          // Most active users
          _buildSectionHeader('Most Active Users', Icons.star),
          _buildActiveUsersList(data['mostActiveUsers'] ?? []),
        ],
      ),
    );
  }

  Widget _buildProductsTab() {
    final data = _productsData['success'] == true ? 
        _productsData['products'] ?? {} : {};
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calendar in each tab
          Align(
            alignment: Alignment.centerRight,
            child: _buildTimeRangeSelector(2),
          ),
          
          const SizedBox(height: 8),
          
          // Key metrics grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: [
              _buildCompactMetricCard(
                'Products',
                data['totalProducts']?.toString() ?? '0',
                Icons.inventory_2,
                Theme.of(context).primaryColor,
              ),
              _buildCompactMetricCard(
                'New',
                '+${data['newProducts']?.toString() ?? '0'}',
                Icons.add_box,
                Colors.green,
              ),
              _buildCompactMetricCard(
                'Sold',
                data['soldProducts']?.toString() ?? '0',
                Icons.check_circle,
                Colors.orange,
              ),
              _buildCompactMetricCard(
                'Avg Time',
                '${data['averageTimeToSell']?.toString() ?? '0'} d',
                Icons.timer,
                Colors.purple,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Category distribution
          _buildSectionHeader('Categories', Icons.pie_chart),
          SizedBox(
            height: 180,
            child: _buildPieChart(data['categoryDistribution'] ?? []),
          ),
          
          const SizedBox(height: 16),
          
          // Price range distribution
          _buildSectionHeader('Price Ranges', Icons.monetization_on),
          SizedBox(
            height: 160,
            child: _buildBarChart(
              data['priceRanges'] ?? [], 
              'range', 
              'count',
              Colors.green,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Top selling categories
          _buildSectionHeader('Sale Success Rate', Icons.analytics),
          _buildHorizontalBarChart(data['topSellingCategories'] ?? []),
        ],
      ),
    );
  }

  Widget _buildDonationsTab() {
    final data = _donationsData['success'] == true ? 
        _donationsData['donations'] ?? {} : {};
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calendar in each tab
          Align(
            alignment: Alignment.centerRight,
            child: _buildTimeRangeSelector(3),
          ),
          
          const SizedBox(height: 8),
          
          // Key metrics grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: [
              _buildCompactMetricCard(
                'Donations',
                data['totalDonations']?.toString() ?? '0',
                Icons.volunteer_activism,
                Theme.of(context).primaryColor,
              ),
              _buildCompactMetricCard(
                'New',
                '+${data['newDonations']?.toString() ?? '0'}',
                Icons.add_box,
                Colors.green,
              ),
              _buildCompactMetricCard(
                'Claimed',
                data['claimedDonations']?.toString() ?? '0',
                Icons.check_circle,
                Colors.blue,
              ),
              _buildCompactMetricCard(
                'Pending',
                data['pendingDonations']?.toString() ?? '0',
                Icons.pending_actions,
                Colors.orange,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Monthly donations trend
          _buildSectionHeader('Monthly Donations', Icons.trending_up),
          SizedBox(
            height: 180,
            child: _buildLineChart(
              data['monthlyDonations'] ?? [], 
              'month', 
              'count',
              Theme.of(context).primaryColor,
              labelFormatter: (value) => _getMonthAbbreviation(value.toInt()),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Top donors
          _buildSectionHeader('Top Donors', Icons.star),
          _buildTopDonorsList(data['topDonors'] ?? []),
          
          const SizedBox(height: 16),
          
          // Claim rates
          _buildSectionHeader('Claim Rates', Icons.speed),
          _buildHorizontalBarChartFromPercentage(data['claimRates'] ?? []),
        ],
      ),
    );
  }

  Widget _buildVolunteersTab() {
    final data = _volunteersData['success'] == true ? 
        _volunteersData['volunteers'] ?? {} : {};
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calendar in each tab
          Align(
            alignment: Alignment.centerRight,
            child: _buildTimeRangeSelector(4),
          ),
          
          const SizedBox(height: 8),
          
          // Key metrics grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: [
              _buildCompactMetricCard(
                'Volunteers',
                data['totalVolunteers']?.toString() ?? '0',
                Icons.volunteer_activism,
                Theme.of(context).primaryColor,
              ),
              _buildCompactMetricCard(
                'Active',
                data['activeVolunteers']?.toString() ?? '0',
                Icons.people,
                Colors.green,
              ),
              _buildCompactMetricCard(
                'Pending',
                data['pendingVolunteers']?.toString() ?? '0',
                Icons.pending,
                Colors.amber,
              ),
              _buildCompactMetricCard(
                'Response',
                '${data['avgResponseTime']?.toString() ?? '0'} h',
                Icons.timer,
                Colors.purple,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Volunteer activity
          _buildSectionHeader('Monthly Activity', Icons.trending_up),
          SizedBox(
            height: 180,
            child: _buildLineChart(
              data['volunteerActivity'] ?? [], 
              'month', 
              'tasks',
              Theme.of(context).primaryColor,
              labelFormatter: (value) => _getMonthAbbreviation(value.toInt()),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Task categories
          _buildSectionHeader('Task Categories', Icons.pie_chart),
          SizedBox(
            height: 180,
            child: _buildPieChart(data['taskCategories'] ?? []),
          ),
          
          const SizedBox(height: 16),
          
          // Top volunteers
          _buildSectionHeader('Top Volunteers', Icons.star),
          _buildTopVolunteersList(data['topVolunteers'] ?? []),
        ],
      ),
    );
  }

  Widget _buildReportsTab() {
    final data = _reportsData['success'] == true ? 
        _reportsData['reports'] ?? {} : {};
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calendar in each tab
          Align(
            alignment: Alignment.centerRight,
            child: _buildTimeRangeSelector(5),
          ),
          
          const SizedBox(height: 8),
          
          // Key metrics grid
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.8,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            children: [
              _buildCompactMetricCard(
                'Reports',
                data['totalReports']?.toString() ?? '0',
                Icons.flag,
                Theme.of(context).primaryColor,
              ),
              _buildCompactMetricCard(
                'New',
                '+${data['newReports']?.toString() ?? '0'}',
                Icons.new_releases,
                Colors.orange,
              ),
              _buildCompactMetricCard(
                'Resolved',
                data['resolvedReports']?.toString() ?? '0',
                Icons.check_circle,
                Colors.green,
              ),
              _buildCompactMetricCard(
                'Pending',
                data['pendingReports']?.toString() ?? '0',
                Icons.pending_actions,
                Colors.amber,
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Monthly reports
          _buildSectionHeader('Monthly Reports', Icons.trending_up),
          SizedBox(
            height: 180,
            child: _buildLineChart(
              data['monthlyReports'] ?? [], 
              'month', 
              'count',
              Theme.of(context).primaryColor,
              labelFormatter: (value) => _getMonthAbbreviation(value.toInt()),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Report categories
          _buildSectionHeader('Categories', Icons.pie_chart),
          SizedBox(
            height: 180,
            child: _buildPieChart(data['reportCategories'] ?? []),
          ),
          
          const SizedBox(height: 16),
          
          // Most reported users
          _buildSectionHeader('Most Reported Users', Icons.person_off),
          _buildReportedUsersList(data['reportedUsers'] ?? []),
          
          const SizedBox(height: 16),
          
          // Resolution outcomes
          _buildSectionHeader('Resolution Outcomes', Icons.analytics),
          _buildHorizontalBarChartFromPercentage(data['resolutionOutcomes'] ?? []),
        ],
      ),
    );
  }

  // Time range selector that's in each tab
  Widget _buildTimeRangeSelector(int tabIndex) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300)
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today, size: 14, color: Theme.of(context).primaryColor),
          const SizedBox(width: 4),
          DropdownButton<String>(
            value: _selectedTimeRanges[tabIndex],
            isDense: true,
            underline: Container(height: 0),
            icon: Icon(Icons.arrow_drop_down, size: 18, color: Theme.of(context).primaryColor),
            borderRadius: BorderRadius.circular(8),
            onChanged: (String? newValue) {
              if (newValue != null && newValue != _selectedTimeRanges[tabIndex]) {
                _updateTimeRange(tabIndex, newValue);
              }
            },
            items: _timeRanges
              .map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // Reusable widget components - more compact for mobile
  Widget _buildCompactMetricCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  // Charts and visualizations
  Widget _buildLineChart(List data, String xKey, String yKey, Color color, {String Function(double)? labelFormatter}) {
    if (data.isEmpty) {
      return const Center(child: Text('No data available', style: TextStyle(fontSize: 12)));
    }

    final spots = data.asMap().entries.map((entry) {
      final x = entry.value[xKey] is int 
          ? entry.value[xKey].toDouble() 
          : double.tryParse(entry.value[xKey].toString()) ?? 0.0;
      final y = entry.value[yKey] is int 
          ? entry.value[yKey].toDouble() 
          : double.tryParse(entry.value[yKey].toString()) ?? 0.0;
      return FlSpot(x, y);
    }).toList();

    final maxY = spots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b) * 1.2;

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval: maxY / 3,
          verticalInterval: 2,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.shade200,
              strokeWidth: 1,
            );
          },
          getDrawingVerticalLine: (value) {
            return FlLine(
              color: Colors.grey.shade200,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              interval: 2,
              getTitlesWidget: (value, meta) {
                final text = labelFormatter != null 
                    ? labelFormatter(value)
                    : value.toInt().toString();
                return Padding(
                  padding: const EdgeInsets.only(top: 5.0),
                  child: Text(text, style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: maxY / 3,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                );
              },
              reservedSize: 24,
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: spots.first.x,
        maxX: spots.last.x,
        minY: 0,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 2.5,
                  color: color,
                  strokeWidth: 1,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: color.withOpacity(0.15),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List data, String xKey, String yKey, Color color, {String Function(double)? labelFormatter}) {
    if (data.isEmpty) {
      return const Center(child: Text('No data available', style: TextStyle(fontSize: 12)));
    }

    final spots = data.asMap().entries.map((entry) {
      final x = entry.value[xKey] is int 
          ? entry.value[xKey].toDouble() 
          : double.tryParse(entry.value[xKey].toString()) ?? 0.0;
      final y = entry.value[yKey] is int 
          ? entry.value[yKey].toDouble() 
          : double.tryParse(entry.value[yKey].toString()) ?? 0.0;
      return FlSpot(x, y);
    }).toList();

    final maxY = spots.map((spot) => spot.y).reduce((a, b) => a > b ? a : b) * 1.2;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                if (xKey == 'hour' && value.toInt() % 4 != 0) {
                  return const SizedBox.shrink();
                }
                
                final text = labelFormatter != null 
                    ? labelFormatter(value)
                    : xKey == 'range' 
                      ? data[value.toInt()][xKey].toString() 
                      : value.toInt().toString();
                return Padding(
                  padding: const EdgeInsets.only(top: 5.0),
                  child: Text(
                    text,
                    style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                  ),
                );
              },
              reservedSize: 18,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: maxY / 3,
              getTitlesWidget: (double value, TitleMeta meta) {
                return Text(
                  value.toInt().toString(),
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          horizontalInterval: maxY / 3,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.shade200,
              strokeWidth: 1,
            );
          },
        ),
        barGroups: spots.map((spot) => 
          BarChartGroupData(
            x: spot.x.toInt(),
            barRods: [
              BarChartRodData(
                toY: spot.y,
                color: color,
                width: 8,
                borderRadius: BorderRadius.circular(2),
                backDrawRodData: BackgroundBarChartRodData(
                  show: true,
                  toY: maxY,
                  color: Colors.grey.shade100,
                ),
              ),
            ],
          )
        ).toList(),
      ),
    );
  }

  Widget _buildPieChart(List data) {
    if (data.isEmpty) {
      return const Center(child: Text('No data available', style: TextStyle(fontSize: 12)));
    }

    final total = data.fold<int>(0, (sum, item) => 
      sum + (item['count'] is int ? item['count'] as int : 0));
    
    final List<PieChartSectionData> sections = data.asMap().entries.map((entry) {
      final color = _getCategoryColor(entry.key);
      final value = entry.value['count'] is int 
          ? entry.value['count'].toDouble() 
          : double.tryParse(entry.value['count'].toString()) ?? 0.0;
      final percent = total > 0 ? (value / total * 100).toStringAsFixed(0) : '0';
      
      return PieChartSectionData(
        value: value,
        title: '$percent%',
        color: color,
        radius: 70,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        titlePositionPercentageOffset: 0.55,
      );
    }).toList();

    return Row(
      children: [
        // Pie chart
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 30,
              sectionsSpace: 2,
              pieTouchData: PieTouchData(
                touchCallback: (FlTouchEvent event, pieTouchResponse) {},
              ),
            ),
          ),
        ),
        
        // Legend
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: data.asMap().entries.map((entry) {
                final color = _getCategoryColor(entry.key);
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          entry.value['category'].toString(),
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        entry.value['count'].toString(),
                        style: const TextStyle(
                          fontSize: 10, 
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEngagementPieChart(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return const Center(child: Text('No data available', style: TextStyle(fontSize: 12)));
    }

    final List<Map<String, dynamic>> pieData = [
      {'label': 'Highly Engaged', 'value': data['highlyEngaged'] ?? 0, 'color': Colors.green},
      {'label': 'Moderately Engaged', 'value': data['moderatelyEngaged'] ?? 0, 'color': Theme.of(context).primaryColor},
      {'label': 'Low Engagement', 'value': data['lowEngagement'] ?? 0, 'color': Colors.grey},
    ];

    final total = pieData.fold<int>(0, (sum, item) => 
      sum + (item['value'] is int ? item['value'] as int : 0));
    
    final List<PieChartSectionData> sections = pieData.map((item) {
      final value = item['value'] is int 
          ? item['value'].toDouble() 
          : double.tryParse(item['value'].toString()) ?? 0.0;
      final percent = total > 0 ? (value / total * 100).toStringAsFixed(0) : '0';
      
      return PieChartSectionData(
        value: value,
        title: '$percent%',
        color: item['color'] as Color,
        radius: 70,
        titleStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        titlePositionPercentageOffset: 0.55,
      );
    }).toList();

    return Row(
      children: [
        // Pie chart
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 30,
              sectionsSpace: 2,
            ),
          ),
        ),
        
        // Legend
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.only(left: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: pieData.map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: item['color'] as Color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item['label'].toString(),
                          style: const TextStyle(fontSize: 10),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        item['value'].toString(),
                        style: const TextStyle(
                          fontSize: 10, 
                          fontWeight: FontWeight.bold
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalBarChart(List data) {
    if (data.isEmpty) {
      return const Center(child: Text('No data available', style: TextStyle(fontSize: 12)));
    }

    return SizedBox(
      height: data.length * 34.0,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: data.length,
        itemBuilder: (context, index) {
          final item = data[index];
          final percentage = item['soldPercentage'] is int
              ? item['soldPercentage'].toDouble()
              : double.tryParse(item['soldPercentage'].toString()) ?? 0.0;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item['category'],
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${percentage.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Stack(
                  children: [
                    Container(
                      height: 10,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: percentage / 100,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: _getCategoryColor(index),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHorizontalBarChartFromPercentage(List data) {
    if (data.isEmpty) {
      return const Center(child: Text('No data available', style: TextStyle(fontSize: 12)));
    }

    return SizedBox(
      height: data.length * 34.0,
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: data.length,
        itemBuilder: (context, index) {
          final item = data[index];
          final percentage = item['percentage'] is int
              ? item['percentage'].toDouble()
              : double.tryParse(item['percentage'].toString()) ?? 0.0;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        item.containsKey('timeFrame') ? item['timeFrame'] : item['outcome'],
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${percentage.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Stack(
                  children: [
                    Container(
                      height: 10,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: percentage / 100,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: _getCategoryColor(index),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // List builders for data tables
  Widget _buildRecentActivityList(List activities) {
    if (activities.isEmpty) {
      return const Center(child: Text('No recent activity', style: TextStyle(fontSize: 12)));
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: activities.length > 5 ? 5 : activities.length, // Show max 5 items
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final activity = activities[index];
          final DateTime time = DateTime.parse(activity['time']);
          final timeAgo = _getTimeAgo(time);
          
          IconData activityIcon;
          Color iconColor;
          
          switch (activity['type']) {
            case 'New User':
              activityIcon = Icons.person_add;
              iconColor = Colors.green;
              break;
            case 'New Listing':
              activityIcon = Icons.add_box;
              iconColor = Theme.of(context).primaryColor;
              break;
            case 'Sale':
              activityIcon = Icons.check_circle;
              iconColor = Colors.orange;
              break;
            case 'Donation':
              activityIcon = Icons.volunteer_activism;
              iconColor = Colors.purple;
              break;
            case 'Report':
              activityIcon = Icons.flag;
              iconColor = Colors.red;
              break;
            default:
              activityIcon = Icons.info;
              iconColor = Colors.grey;
          }
          
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            leading: Icon(activityIcon, color: iconColor, size: 16),
            title: Text(
              '${activity['type']} - ${activity['user']}',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              activity['details'],
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              timeAgo,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActiveUsersList(List users) {
    if (users.isEmpty) {
      return const Center(child: Text('No user data available', style: TextStyle(fontSize: 12)));
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: users.length > 5 ? 5 : users.length, // Show max 5 items
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final user = users[index];
          
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
              child: Text(
                user['userId'].toString()[0],
                style: TextStyle(fontSize: 10, color: Theme.of(context).primaryColor),
              ),
            ),
            title: Text(
              user['userId'],
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'Listings: ${user['listings']} · ${user['purchases'] != null ? 'Purchases: ${user['purchases']}' : ''}',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${user['activity']}',
                style: TextStyle(
                  fontSize: 10, 
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopDonorsList(List donors) {
    if (donors.isEmpty) {
      return const Center(child: Text('No donor data available', style: TextStyle(fontSize: 12)));
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: donors.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final donor = donors[index];
          
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.teal.shade100,
              child: Text(
                donor['userId'].toString()[0],
                style: TextStyle(fontSize: 10, color: Colors.teal.shade800),
              ),
            ),
            title: Text(
              donor['userId'],
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${donor['donations']}',
                style: TextStyle(
                  fontSize: 10, 
                  color: Colors.teal.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopVolunteersList(List volunteers) {
    if (volunteers.isEmpty) {
      return const Center(child: Text('No volunteer data available', style: TextStyle(fontSize: 12)));
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: volunteers.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final volunteer = volunteers[index];
          
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
              child: Text(
                volunteer['userId'].toString()[0],
                style: TextStyle(fontSize: 10, color: Theme.of(context).primaryColor),
              ),
            ),
            title: Text(
              volunteer['userId'],
              style: const TextStyle(fontSize: 12),
            ),
            subtitle: Text(
              'Response Time: ${volunteer['responseTime']} hrs',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${volunteer['tasksCompleted']}',
                style: TextStyle(
                  fontSize: 10, 
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReportedUsersList(List users) {
    if (users.isEmpty) {
      return const Center(child: Text('No reported users data', style: TextStyle(fontSize: 12)));
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: users.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final user = users[index];
          
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.red.shade100,
              child: Text(
                user['userId'].toString()[0],
                style: TextStyle(fontSize: 10, color: Colors.red.shade800),
              ),
            ),
            title: Text(
              user['userId'],
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${user['reportCount']}',
                style: TextStyle(
                  fontSize: 10, 
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // Helper methods
  Color _getCategoryColor(int index) {
    final colors = [
      Theme.of(context).primaryColor,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.indigo,
      Colors.pink,
      Colors.amber,
      Colors.cyan,
      Colors.deepOrange,
    ];
    
    return colors[index % colors.length];
  }

  String _getMonthAbbreviation(int month) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month < 1 || month > 12 ? 0 : month];
  }

  String _getTimeAgo(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }
}
