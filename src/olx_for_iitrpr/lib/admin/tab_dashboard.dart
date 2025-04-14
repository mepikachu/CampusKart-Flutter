import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// AdminDashboard widget that displays comprehensive analytics data
/// for IITRPR MarketPlace administrators
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({Key? key}) : super(key: key);

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  // Storage for authentication
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  // Time range selection
  String _selectedTimeRange = 'Last 30 Days';
  final List<String> _timeRanges = [
    'Today', 
    'Last 7 Days', 
    'Last 30 Days', 
    'Last 90 Days', 
    'This Year', 
    'All Time'
  ];
  
  // Dashboard data
  bool _isLoading = true;
  Map<String, dynamic> _dashboardData = {};
  bool _hasError = false;
  String _errorMessage = '';
  
  // Category colors for sections
  final Map<String, Color> _categoryColors = {
    'users': Color(0xFF1A73E8),       // Blue
    'products': Color(0xFF4CAF50),    // Green
    'donations': Color(0xFFFF9800),   // Orange
    'volunteers': Color(0xFF9C27B0),  // Purple
    'reports': Color(0xFFE53935),     // Red
  };
  
  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
  }

  /// Fetches all dashboard data from the server
  Future<void> _fetchDashboardData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      final timeRange = _getTimeRangeParams(_selectedTimeRange);
      
      // Fetch dashboard overview data
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
        final overviewData = json.decode(response.body);
        
        // Now fetch more detailed data for each section in parallel
        final List<Future> fetchFutures = [
          _fetchSectionData('users/stats', authCookie, timeRange),
          _fetchSectionData('products/stats', authCookie, timeRange),
          _fetchSectionData('donations/stats', authCookie, timeRange), 
          _fetchSectionData('volunteers/stats', authCookie, timeRange),
          _fetchSectionData('reports/stats', authCookie, timeRange),
        ];
        
        final results = await Future.wait(fetchFutures);
        
        setState(() {
          _dashboardData = {
            'overview': overviewData['success'] == true ? overviewData['overview'] : {},
            'usersData': results[0]['success'] == true ? results[0]['users'] : {},
            'productsData': results[1]['success'] == true ? results[1]['products'] : {},
            'donationsData': results[2]['success'] == true ? results[2]['donations'] : {},
            'volunteersData': results[3]['success'] == true ? results[3]['volunteers'] : {},
            'reportsData': results[4]['success'] == true ? results[4]['reports'] : {},
          };
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load dashboard data: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading dashboard data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  /// Fetches data for a specific section (users, products, etc)
  Future<Map<String, dynamic>> _fetchSectionData(
    String endpoint, 
    String? authCookie, 
    Map<String, String> timeRange
  ) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://olx-for-iitrpr-backend.onrender.com/api/admin/$endpoint?startDate=${timeRange['startDate']}&endDate=${timeRange['endDate']}'
        ),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('Error fetching $endpoint data: ${response.statusCode}');
        return {'success': false};
      }
    } catch (e) {
      print('Exception fetching $endpoint data: $e');
      return {'success': false};
    }
  }
  
  /// Converts time range to start and end date parameters
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
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading dashboard data...'),
          ],
        ),
      );
    }
    
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Error loading dashboard',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_errorMessage),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _fetchDashboardData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: _fetchDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTimeRangeSelector(),
            const SizedBox(height: 16),
            _buildSummaryCards(),
            const SizedBox(height: 24),
            _buildUsersSection(),
            const SizedBox(height: 24),
            _buildProductsSection(),
            const SizedBox(height: 24),
            _buildDonationsSection(),
            const SizedBox(height: 24),
            _buildVolunteersSection(),
            const SizedBox(height: 24),
            _buildReportsSection(),
            const SizedBox(height: 24),
            _buildRecentActivitySection(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Time range selector dropdown
  Widget _buildTimeRangeSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Time Range: ',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedTimeRange,
              icon: const Icon(Icons.keyboard_arrow_down),
              elevation: 2,
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedTimeRange = newValue;
                  });
                  _fetchDashboardData();
                }
              },
              items: _timeRanges.map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  /// Summary metrics cards at the top of dashboard
  Widget _buildSummaryCards() {
    final overview = _dashboardData['overview'] ?? {};
    
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = constraints.maxWidth > 800 ? 4 : 
                            constraints.maxWidth > 600 ? 3 : 2;
        
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          childAspectRatio: 1.5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            _buildSummaryCard(
              'Total Users',
              overview['totalUsers']?.toString() ?? '0',
              Icons.people,
              _categoryColors['users']!,
              '+${overview['newUsers']?.toString() ?? '0'} new',
            ),
            _buildSummaryCard(
              'Products',
              overview['totalProducts']?.toString() ?? '0',
              Icons.shopping_bag,
              _categoryColors['products']!,
              '${overview['soldProducts']?.toString() ?? '0'} sold',
            ),
            _buildSummaryCard(
              'Donations',
              overview['totalDonations']?.toString() ?? '0',
              Icons.volunteer_activism,
              _categoryColors['donations']!,
              'Donations platform',
            ),
            _buildSummaryCard(
              'Reports',
              overview['pendingReports']?.toString() ?? '0',
              Icons.report_problem,
              _categoryColors['reports']!,
              'Pending reports',
            ),
          ],
        );
      }
    );
  }

  /// Individual summary card widget
  Widget _buildSummaryCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Section header with title and "See All" button
  Widget _buildSectionHeader(String title, IconData icon, Color color, VoidCallback onSeeAll) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: onSeeAll,
            child: Row(
              children: [
                Text('See All', style: TextStyle(color: color)),
                Icon(Icons.arrow_forward, color: color, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Users section with user metrics and charts
  Widget _buildUsersSection() {
    final usersData = _dashboardData['usersData'] ?? {};
    final userGrowth = usersData['userGrowth'] ?? [];
    final userActivity = usersData['userActivity'] ?? [];
    final mostActiveUsers = usersData['mostActiveUsers'] ?? [];
    final userEngagement = usersData['userEngagement'] ?? {};
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'User Activity',
          Icons.people,
          _categoryColors['users']!,
          () => _navigateToDetailPage('users'),
        ),
        SizedBox(
          height: 220,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'User Growth',
                  userGrowth.isNotEmpty
                    ? _buildLineChart(
                        userGrowth, 
                        'month', 
                        'count',
                        _categoryColors['users']!,
                        labelFormatter: (value) => _getMonthAbbreviation(value.toInt()),
                      )
                    : _buildEmptyPlaceholder('No user growth data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Daily Activity',
                  userActivity.isNotEmpty
                    ? _buildBarChart(userActivity, 'hour', 'count', _categoryColors['users']!)
                    : _buildEmptyPlaceholder('No user activity data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'User Engagement',
                  userEngagement.isNotEmpty
                    ? _buildPieChart({
                        'Highly Engaged': userEngagement['highlyEngaged'] ?? 0,
                        'Moderately Engaged': userEngagement['moderatelyEngaged'] ?? 0,
                        'Low Engagement': userEngagement['lowEngagement'] ?? 0,
                      }, _categoryColors['users']!)
                    : _buildEmptyPlaceholder('No user engagement data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Most Active Users',
                  mostActiveUsers.isNotEmpty
                    ? _buildActiveUsersList(mostActiveUsers)
                    : _buildEmptyPlaceholder('No active users data available'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Products section with product metrics and charts
  Widget _buildProductsSection() {
    final productsData = _dashboardData['productsData'] ?? {};
    final categoryDistribution = productsData['categoryDistribution'] ?? [];
    final priceRanges = productsData['priceRanges'] ?? [];
    final monthlySales = productsData['monthlySales'] ?? [];
    final topSellingCategories = productsData['topSellingCategories'] ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Products Overview',
          Icons.shopping_bag,
          _categoryColors['products']!,
          () => _navigateToDetailPage('products'),
        ),
        SizedBox(
          height: 220,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Category Distribution',
                  categoryDistribution.isNotEmpty
                    ? _buildCategoryPieChart(categoryDistribution, _categoryColors['products']!)
                    : _buildEmptyPlaceholder('No category data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Price Ranges',
                  priceRanges.isNotEmpty
                    ? _buildHorizontalBarChart(priceRanges, 'range', 'count', _categoryColors['products']!)
                    : _buildEmptyPlaceholder('No price range data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Monthly Sales',
                  monthlySales.isNotEmpty
                    ? _buildLineChart(
                        monthlySales, 
                        'month', 
                        'count',
                        _categoryColors['products']!,
                        labelFormatter: (value) => _getMonthAbbreviation(value.toInt()),
                      )
                    : _buildEmptyPlaceholder('No sales data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Top Selling Categories',
                  topSellingCategories.isNotEmpty
                    ? _buildTopSellingCategoriesChart(topSellingCategories, _categoryColors['products']!)
                    : _buildEmptyPlaceholder('No top selling data available'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Donations section with donation metrics and charts
  Widget _buildDonationsSection() {
    final donationsData = _dashboardData['donationsData'] ?? {};
    final monthlyDonations = donationsData['monthlyDonations'] ?? [];
    final topDonors = donationsData['topDonors'] ?? [];
    final claimRates = donationsData['claimRates'] ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Donations Overview',
          Icons.volunteer_activism,
          _categoryColors['donations']!,
          () => _navigateToDetailPage('donations'),
        ),
        SizedBox(
          height: 220,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Monthly Donations',
                  monthlyDonations.isNotEmpty
                    ? _buildLineChart(
                        monthlyDonations, 
                        'month', 
                        'count',
                        _categoryColors['donations']!,
                        labelFormatter: (value) => _getMonthAbbreviation(value.toInt()),
                      )
                    : _buildEmptyPlaceholder('No monthly donation data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Top Donors',
                  topDonors.isNotEmpty
                    ? _buildDonorsList(topDonors)
                    : _buildEmptyPlaceholder('No top donor data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Claim Rates',
                  claimRates.isNotEmpty
                    ? _buildClaimRatesChart(claimRates, _categoryColors['donations']!)
                    : _buildEmptyPlaceholder('No claim rate data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Donation Status',
                  _buildDonationStatusInfo(donationsData),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Volunteers section with volunteer metrics and charts
  Widget _buildVolunteersSection() {
    final volunteersData = _dashboardData['volunteersData'] ?? {};
    final volunteerActivity = volunteersData['volunteerActivity'] ?? [];
    final topVolunteers = volunteersData['topVolunteers'] ?? [];
    final taskCategories = volunteersData['taskCategories'] ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Volunteers Overview',
          Icons.people_outline,
          _categoryColors['volunteers']!,
          () => _navigateToDetailPage('volunteers'),
        ),
        SizedBox(
          height: 220,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Volunteer Activity',
                  volunteerActivity.isNotEmpty
                    ? _buildLineChart(
                        volunteerActivity, 
                        'month', 
                        'tasks',
                        _categoryColors['volunteers']!,
                        labelFormatter: (value) => _getMonthAbbreviation(value.toInt()),
                      )
                    : _buildEmptyPlaceholder('No volunteer activity data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Task Categories',
                  taskCategories.isNotEmpty
                    ? _buildCategoryPieChart(taskCategories, _categoryColors['volunteers']!)
                    : _buildEmptyPlaceholder('No task categories available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Top Volunteers',
                  topVolunteers.isNotEmpty
                    ? _buildVolunteersList(topVolunteers)
                    : _buildEmptyPlaceholder('No top volunteers data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Volunteer Stats',
                  _buildVolunteerStatsInfo(volunteersData),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Reports section with report metrics and charts
  Widget _buildReportsSection() {
    final reportsData = _dashboardData['reportsData'] ?? {};
    final monthlyReports = reportsData['monthlyReports'] ?? [];
    final reportCategories = reportsData['reportCategories'] ?? [];
    final reportedUsers = reportsData['reportedUsers'] ?? [];
    final resolutionOutcomes = reportsData['resolutionOutcomes'] ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Reports Overview',
          Icons.report_problem,
          _categoryColors['reports']!,
          () => _navigateToDetailPage('reports'),
        ),
        SizedBox(
          height: 220,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Monthly Reports',
                  monthlyReports.isNotEmpty
                    ? _buildLineChart(
                        monthlyReports, 
                        'month', 
                        'count',
                        _categoryColors['reports']!,
                        labelFormatter: (value) => _getMonthAbbreviation(value.toInt()),
                      )
                    : _buildEmptyPlaceholder('No monthly report data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Report Categories',
                  reportCategories.isNotEmpty
                    ? _buildCategoryPieChart(reportCategories, _categoryColors['reports']!)
                    : _buildEmptyPlaceholder('No report categories available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Most Reported Users',
                  reportedUsers.isNotEmpty
                    ? _buildReportedUsersList(reportedUsers)
                    : _buildEmptyPlaceholder('No reported users data available'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 300,
                child: _buildChartCard(
                  'Resolution Outcomes',
                  resolutionOutcomes.isNotEmpty
                    ? _buildResolutionOutcomesChart(resolutionOutcomes, _categoryColors['reports']!)
                    : _buildEmptyPlaceholder('No resolution data available'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Recent activity section showing latest platform events
  Widget _buildRecentActivitySection() {
    final recentActivity = _dashboardData['overview']?['recentActivity'] ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              Icon(Icons.access_time, color: Colors.black87, size: 20),
              const SizedBox(width: 8),
              Text(
                'Recent Activity',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                recentActivity.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Icon(Icons.event_busy, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 16),
                              Text(
                                'No recent activity',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: recentActivity.take(10).map((activity) {
                          IconData activityIcon;
                          Color iconColor;
                          
                          switch (activity['type']) {
                            case 'New User':
                              activityIcon = Icons.person_add;
                              iconColor = Colors.green;
                              break;
                            case 'New Listing':
                              activityIcon = Icons.add_box;
                              iconColor = _categoryColors['products']!;
                              break;
                            case 'Sale':
                              activityIcon = Icons.check_circle;
                              iconColor = Colors.orange;
                              break;
                            case 'Donation':
                              activityIcon = Icons.volunteer_activism;
                              iconColor = _categoryColors['donations']!;
                              break;
                            case 'Report':
                              activityIcon = Icons.flag;
                              iconColor = _categoryColors['reports']!;
                              break;
                            default:
                              activityIcon = Icons.info;
                              iconColor = Colors.grey;
                          }
                          
                          return Column(
                            children: [
                              ListTile(
                                leading: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: iconColor.withOpacity(0.1),
                                  child: Icon(activityIcon, color: iconColor, size: 16),
                                ),
                                title: Text(
                                  activity['user'] ?? '',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  activity['details'] ?? '',
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Text(
                                  _formatTimeAgo(activity['time'] ?? ''),
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                                dense: true,
                              ),
                              if (recentActivity.indexOf(activity) < recentActivity.length - 1)
                                const Divider(height: 1),
                            ],
                          );
                        }).toList(),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Generic chart card container with consistent styling
  Widget _buildChartCard(String title, Widget child) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  /// Empty state placeholder for charts with no data
  Widget _buildEmptyPlaceholder(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Line chart implementation
  Widget _buildLineChart(
    List data, 
    String xKey, 
    String yKey, 
    Color color, 
    {String Function(double)? labelFormatter}
  ) {
    if (data.isEmpty) {
      return Center(child: Text('No data available'));
    }

    try {
      // Format data points for the chart
      final spots = data.map((item) {
        final x = item[xKey] is int 
            ? item[xKey].toDouble() 
            : double.tryParse(item[xKey].toString()) ?? 0.0;
        final y = item[yKey] is int 
            ? item[yKey].toDouble() 
            : double.tryParse(item[yKey].toString()) ?? 0.0;
        return FlSpot(x, y);
      }).toList();
      
      // Calculate Y axis bounds safely
      final maxY = spots.map((spot) => spot.y).fold<double>(0, (max, y) => math.max(max, y)) * 1.2;
      final minX = spots.map((spot) => spot.x).fold<double>(double.infinity, (min, x) => math.min(min, x));
      final maxX = spots.map((spot) => spot.x).fold<double>(0, (max, x) => math.max(max, x));

      return LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: maxY / 4,
            verticalInterval: 1,
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
                reservedSize: 22,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  String text = '';
                  if (labelFormatter != null) {
                    text = labelFormatter(value);
                  } else {
                    text = value.toInt().toString();
                  }
                  
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      text,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: maxY / 4,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
                reservedSize: 28,
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          minX: minX,
          maxX: maxX,
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
                    radius: 3,
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
    } catch (e) {
      print('Error building line chart: $e');
      return Center(child: Text('Error building chart'));
    }
  }

  /// Bar chart implementation
  Widget _buildBarChart(
    List data, 
    String xKey, 
    String yKey, 
    Color color
  ) {
    if (data.isEmpty) {
      return Center(child: Text('No data available'));
    }

    try {
      // Get max value for scaling
      final maxY = data.map((item) => 
        item[yKey] is int ? 
        item[yKey].toDouble() : 
        double.tryParse(item[yKey].toString()) ?? 0.0
      ).fold<double>(0, (max, y) => math.max(max, y)) * 1.2;

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
                  // For hourly data, show every 6 hours
                  if (xKey == 'hour' && value.toInt() % 6 != 0) {
                    return const SizedBox.shrink();
                  }
                  
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      xKey == 'hour' ? '${value.toInt()}h' : value.toInt().toString(),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
                reservedSize: 20,
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: maxY / 4,
                getTitlesWidget: (value, meta) {
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      value.toInt().toString(),
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
                reservedSize: 28,
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey.shade200,
                strokeWidth: 1,
              );
            },
          ),
          barGroups: data.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            
            final x = item[xKey] is int ? 
                      item[xKey].toDouble() : 
                      double.tryParse(item[xKey].toString()) ?? index.toDouble();
            
            final y = item[yKey] is int ? 
                      item[yKey].toDouble() : 
                      double.tryParse(item[yKey].toString()) ?? 0.0;
            
            return BarChartGroupData(
              x: x.toInt(),
              barRods: [
                BarChartRodData(
                  toY: y,
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
            );
          }).toList(),
        ),
      );
    } catch (e) {
      print('Error building bar chart: $e');
      return Center(child: Text('Error building chart'));
    }
  }

  /// Pie chart implementation for key-value data
  Widget _buildPieChart(Map<String, dynamic> data, Color baseColor) {
    if (data.isEmpty) {
      return Center(child: Text('No data available'));
    }

    try {
      final total = data.values.fold<num>(0, (sum, value) => sum + (value as num));
      
      final List<PieChartSectionData> sections = [];
      final List<Color> colors = [
        baseColor,
        baseColor.withOpacity(0.8),
        baseColor.withOpacity(0.6),
        baseColor.withOpacity(0.4),
        baseColor.withOpacity(0.2),
      ];
      
      // Create pie chart sections
      int i = 0;
      data.forEach((key, value) {
        final double percentage = (value as num) / total * 100;
        sections.add(
          PieChartSectionData(
            color: colors[i % colors.length],
            value: value.toDouble(),
            title: percentage >= 10 ? '${percentage.toStringAsFixed(0)}%' : '',
            radius: 60,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            titlePositionPercentageOffset: 0.55,
          ),
        );
        i++;
      });

      return Row(
        children: [
          // Pie chart
          Expanded(
            flex: 3,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 25,
                sectionsSpace: 2,
              ),
            ),
          ),
          
          // Legend
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: data.entries.toList().asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: colors[i % colors.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.key,
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          _formatNumber(item.value),
                          style: const TextStyle(
                            fontSize: 11, 
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
    } catch (e) {
      print('Error building pie chart: $e');
      return Center(child: Text('Error building chart'));
    }
  }

  /// Pie chart implementation for category-count data from list
  Widget _buildCategoryPieChart(List data, Color baseColor) {
    if (data.isEmpty) {
      return Center(child: Text('No data available'));
    }

    try {
      // Calculate total for percentages
      final total = data.fold<int>(0, (sum, item) => 
        sum + (item['count'] is int ? item['count'] as int : 0));
      
      final List<PieChartSectionData> sections = [];
      final List<Color> colors = [
        baseColor,
        baseColor.withOpacity(0.8),
        baseColor.withOpacity(0.6),
        baseColor.withOpacity(0.4),
        baseColor.withOpacity(0.2),
      ];
      
      // Generate legend items in the same order as pie sections
      final List<Map<String, dynamic>> legendItems = [];
      
      for (int i = 0; i < data.length; i++) {
        final item = data[i];
        final value = item['count'] is int 
            ? item['count'].toDouble() 
            : double.tryParse(item['count'].toString()) ?? 0.0;
        final category = item['category'] ?? '';
        final percent = total > 0 ? (value / total * 100) : 0.0;
        
        sections.add(
          PieChartSectionData(
            color: colors[i % colors.length],
            value: value,
            title: percent >= 10 ? '${percent.toStringAsFixed(0)}%' : '',
            radius: 60,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            titlePositionPercentageOffset: 0.55,
          ),
        );
        
        legendItems.add({
          'color': colors[i % colors.length],
          'label': category,
          'value': value.toInt(),
        });
      }

      return Row(
        children: [
          // Pie chart
          Expanded(
            flex: 3,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 25,
                sectionsSpace: 2,
              ),
            ),
          ),
          
          // Legend
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: legendItems.map((item) {
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
                            style: const TextStyle(fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          item['value'].toString(),
                          style: const TextStyle(
                            fontSize: 11, 
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
    } catch (e) {
      print('Error building category pie chart: $e');
      return Center(child: Text('Error building chart'));
    }
  }

  /// Horizontal bar chart implementation
  Widget _buildHorizontalBarChart(
    List data, 
    String labelKey, 
    String valueKey, 
    Color color
  ) {
    if (data.isEmpty) {
      return Center(child: Text('No data available'));
    }

    try {
      // Find maximum value for scaling the bars
      final maxValue = data.fold<int>(0, (max, item) => 
        math.max(max, item[valueKey] is int ? item[valueKey] as int : 0));

      return ListView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: data.length,
        itemBuilder: (context, index) {
          final item = data[index];
          final value = item[valueKey] is int
              ? item[valueKey].toDouble()
              : double.tryParse(item[valueKey].toString()) ?? 0.0;
          final percentage = maxValue > 0 ? value / maxValue : 0.0;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        item[labelKey].toString(),
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      value.toInt().toString(),
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
                      widthFactor: percentage,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
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
      );
    } catch (e) {
      print('Error building horizontal bar chart: $e');
      return Center(child: Text('Error building chart'));
    }
  }

  /// Chart for top selling categories
  Widget _buildTopSellingCategoriesChart(List data, Color color) {
    if (data.isEmpty) {
      return Center(child: Text('No data available'));
    }

    try {
      return ListView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: data.length,
        itemBuilder: (context, index) {
          final item = data[index];
          final category = item['category'] ?? '';
          final percentage = item['soldPercentage'] is num
              ? item['soldPercentage'].toDouble()
              : double.tryParse(item['soldPercentage'].toString()) ?? 0.0;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        category,
                        style: const TextStyle(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${percentage.toStringAsFixed(1)}%',
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
                          color: color,
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
      );
    } catch (e) {
      print('Error building top selling categories chart: $e');
      return Center(child: Text('Error building chart'));
    }
  }

  /// Chart for donation claim rates
  Widget _buildClaimRatesChart(List data, Color color) {
    if (data.isEmpty) {
      return Center(child: Text('No data available'));
    }

    try {
      return ListView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: data.length,
        itemBuilder: (context, index) {
          final item = data[index];
          final timeFrame = item['timeFrame'] ?? '';
          final percentage = item['percentage'] is num
              ? item['percentage'].toDouble()
              : double.tryParse(item['percentage'].toString()) ?? 0.0;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        timeFrame,
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
                          color: color,
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
      );
    } catch (e) {
      print('Error building claim rates chart: $e');
      return Center(child: Text('Error building chart'));
    }
  }

  /// Chart for resolution outcomes
  Widget _buildResolutionOutcomesChart(List data, Color color) {
    if (data.isEmpty) {
      return Center(child: Text('No data available'));
    }

    try {
      return ListView.builder(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: data.length,
        itemBuilder: (context, index) {
          final item = data[index];
          final outcome = item['outcome'] ?? '';
          final percentage = item['percentage'] is num
              ? item['percentage'].toDouble()
              : double.tryParse(item['percentage'].toString()) ?? 0.0;
          
          return Padding(
            padding: const EdgeInsets.only(bottom: 10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        outcome,
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
                          color: color,
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
      );
    } catch (e) {
      print('Error building resolution outcomes chart: $e');
      return Center(child: Text('Error building chart'));
    }
  }

  /// List of active users
  Widget _buildActiveUsersList(List users) {
    if (users.isEmpty) {
      return Center(child: Text('No user data available'));
    }

    try {
      return ListView.separated(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: users.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final user = users[index];
          final userId = user['userId'] ?? '';
          
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: _categoryColors['users']!.withOpacity(0.1),
              child: Text(
                userId.isNotEmpty ? userId[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 11, 
                  color: _categoryColors['users']!,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              userId,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: user['listings'] != null && user['purchases'] != null ? 
              Text(
                'Listed: ${user['listings']} · Purchases: ${user['purchases']}',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis,
              ) : null,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _categoryColors['users']!.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                user['activity']?.toString() ?? '0',
                style: TextStyle(
                  fontSize: 10, 
                  color: _categoryColors['users']!,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      print('Error building active users list: $e');
      return Center(child: Text('Error building user list'));
    }
  }

  /// List of top donors
  Widget _buildDonorsList(List donors) {
    if (donors.isEmpty) {
      return Center(child: Text('No donor data available'));
    }

    try {
      return ListView.separated(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: donors.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final donor = donors[index];
          final userId = donor['userId'] ?? '';
          
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: _categoryColors['donations']!.withOpacity(0.1),
              child: Text(
                userId.isNotEmpty ? userId[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 11, 
                  color: _categoryColors['donations']!,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              userId,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _categoryColors['donations']!.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${donor['donations'] ?? 0} items',
                style: TextStyle(
                  fontSize: 10, 
                  color: _categoryColors['donations']!,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      print('Error building donors list: $e');
      return Center(child: Text('Error building donors list'));
    }
  }

  /// List of top volunteers
  Widget _buildVolunteersList(List volunteers) {
    if (volunteers.isEmpty) {
      return Center(child: Text('No volunteer data available'));
    }

    try {
      return ListView.separated(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: volunteers.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final volunteer = volunteers[index];
          final userId = volunteer['userId'] ?? '';
          
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: _categoryColors['volunteers']!.withOpacity(0.1),
              child: Text(
                userId.isNotEmpty ? userId[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 11, 
                  color: _categoryColors['volunteers']!,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              userId,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: volunteer['responseTime'] != null ?
              Text(
                'Response: ${volunteer['responseTime']} hrs',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              ) : null,
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _categoryColors['volunteers']!.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${volunteer['tasksCompleted'] ?? 0}',
                style: TextStyle(
                  fontSize: 10, 
                  color: _categoryColors['volunteers']!,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      print('Error building volunteers list: $e');
      return Center(child: Text('Error building volunteers list'));
    }
  }

  /// List of most reported users
  Widget _buildReportedUsersList(List users) {
    if (users.isEmpty) {
      return Center(child: Text('No reported users data available'));
    }

    try {
      return ListView.separated(
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: users.length,
        separatorBuilder: (context, index) => Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (context, index) {
          final user = users[index];
          final userId = user['userId'] ?? '';
          
          return ListTile(
            dense: true,
            visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: _categoryColors['reports']!.withOpacity(0.1),
              child: Text(
                userId.isNotEmpty ? userId[0].toUpperCase() : '?',
                style: TextStyle(
                  fontSize: 11, 
                  color: _categoryColors['reports']!,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              userId,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _categoryColors['reports']!.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${user['reportCount'] ?? 0}',
                style: TextStyle(
                  fontSize: 10, 
                  color: _categoryColors['reports']!,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      print('Error building reported users list: $e');
      return Center(child: Text('Error building reported users list'));
    }
  }

  /// Donation status information widget
  Widget _buildDonationStatusInfo(Map<String, dynamic> data) {
    final totalDonations = data['totalDonations'] ?? 0;
    final claimedDonations = data['claimedDonations'] ?? 0;
    final pendingDonations = data['pendingDonations'] ?? 0;
    
    final claimedPercentage = totalDonations > 0 
        ? (claimedDonations / totalDonations * 100).toStringAsFixed(1) 
        : '0';
    final pendingPercentage = totalDonations > 0 
        ? (pendingDonations / totalDonations * 100).toStringAsFixed(1) 
        : '0';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total Donations',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              totalDonations.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _categoryColors['donations']!,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatusCard(
                'Claimed',
                claimedDonations.toString(),
                '$claimedPercentage%',
                Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatusCard(
                'Pending',
                pendingDonations.toString(),
                '$pendingPercentage%',
                Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 12),
        const Text(
          'Donation Platform Impact',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.volunteer_activism, 
                color: _categoryColors['donations']!, size: 18),
            const SizedBox(width: 4),
            Text(
              'Promoting Sustainability',
              style: TextStyle(
                fontSize: 11,
                color: _categoryColors['donations']!,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Volunteer statistics information widget
  Widget _buildVolunteerStatsInfo(Map<String, dynamic> data) {
    final totalVolunteers = data['totalVolunteers'] ?? 0;
    final activeVolunteers = data['activeVolunteers'] ?? 0;
    final pendingVolunteers = data['pendingVolunteers'] ?? 0;
    final tasksCompleted = data['tasksCompleted'] ?? 0;
    final avgResponseTime = data['avgResponseTime'] ?? 0;
    
    final activePercentage = totalVolunteers > 0 
        ? (activeVolunteers / totalVolunteers * 100).toStringAsFixed(1) 
        : '0';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Total Volunteers',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              totalVolunteers.toString(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _categoryColors['volunteers']!,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatusCard(
                'Active',
                activeVolunteers.toString(),
                '$activePercentage%',
                Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildStatusCard(
                'Pending',
                pendingVolunteers.toString(),
                'Approvals',
                Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tasks Completed',
                  style: TextStyle(fontSize: 11),
                ),
                Text(
                  tasksCompleted.toString(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _categoryColors['volunteers']!,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Avg. Response Time',
                  style: TextStyle(fontSize: 11),
                ),
                Text(
                  '${avgResponseTime.toString()} hrs',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _categoryColors['volunteers']!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// Status card for simple statistics
  Widget _buildStatusCard(String title, String value, String subtitle, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: color,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper method to format large numbers
  String _formatNumber(num number) {
    if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    } else {
      return number.toString();
    }
  }

  /// Helper method to get month abbreviation
  String _getMonthAbbreviation(int month) {
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month < 1 || month > 12 ? 0 : month];
  }

  /// Helper method to format time ago from ISO date
  String _formatTimeAgo(String timeString) {
    try {
      final dateTime = DateTime.parse(timeString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inDays > 7) {
        return DateFormat('MMM d').format(dateTime);
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'just now';
      }
    } catch (e) {
      return timeString;
    }
  }

  /// Navigation to detailed section pages
  void _navigateToDetailPage(String section) {
    final authCookie = _secureStorage.read(key: 'authCookie');
    final timeRange = _getTimeRangeParams(_selectedTimeRange);
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailPage(
          section: section,
          timeRange: _selectedTimeRange,
          startDate: timeRange['startDate']!,
          endDate: timeRange['endDate']!,
          authCookie: authCookie,
        ),
      ),
    );
  }
}

/// Detail page for each dashboard section
class DetailPage extends StatefulWidget {
  final String section;
  final String timeRange;
  final String startDate;
  final String endDate;
  final Future<String?> authCookie;
  
  const DetailPage({
    Key? key,
    required this.section,
    required this.timeRange,
    required this.startDate,
    required this.endDate,
    required this.authCookie,
  }) : super(key: key);

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  bool _isLoading = true;
  Map<String, dynamic> _detailData = {};
  String _errorMessage = '';
  String _filterQuery = '';
  String _sortBy = 'latest';
  
  @override
  void initState() {
    super.initState();
    _fetchDetailData();
  }
  
  Future<void> _fetchDetailData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    
    try {
      final authCookie = await widget.authCookie;
      
      // Build API endpoint based on section
      String endpoint = 'https://olx-for-iitrpr-backend.onrender.com/api/admin';
      
      switch (widget.section) {
        case 'users':
          endpoint += '/users';
          break;
        case 'products':
          endpoint += '/products';
          break;
        case 'donations':
          endpoint += '/donations';
          break;
        case 'volunteers':
          // For volunteers, we'll use the users endpoint with role filter
          endpoint += '/users?role=volunteer';
          break;
        case 'reports':
          endpoint += '/reports';
          break;
        default:
          endpoint += '/${widget.section}';
      }
      
      // Add common query params
      final queryParams = {
        'startDate': widget.startDate,
        'endDate': widget.endDate,
        'page': '1',
        'limit': '50',
      };
      
      // Add search param if filtering
      if (_filterQuery.isNotEmpty) {
        queryParams['search'] = _filterQuery;
      }
      
      // Add sorting param
      if (_sortBy.isNotEmpty) {
        final sortingParams = _sortBy.split('_');
        if (sortingParams.length == 2) {
          queryParams['sortBy'] = sortingParams[0];
          queryParams['order'] = sortingParams[1];
        }
      }
      
      // Build URI with query parameters
      final uri = Uri.parse(endpoint).replace(
        queryParameters: queryParams,
      );
      
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _detailData = data;
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load detail data: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Convert section to title case for display
    String title = widget.section.substring(0, 1).toUpperCase() + widget.section.substring(1);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Center(
            child: Text(
              widget.timeRange,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportData,
            tooltip: 'Export data',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchDetailData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search and filter bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search ${widget.section}...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _filterQuery = value;
                      });
                    },
                    onSubmitted: (_) => _fetchDetailData(),
                  ),
                ),
                const SizedBox(width: 12),
                PopupMenuButton<String>(
                  icon: Row(
                    children: [
                      const Icon(Icons.sort),
                      const SizedBox(width: 4),
                      Text(
                        'Sort',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  onSelected: (value) {
                    setState(() {
                      _sortBy = value;
                    });
                    _fetchDetailData();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'createdAt_desc',
                      child: Text('Newest First'),
                    ),
                    const PopupMenuItem(
                      value: 'createdAt_asc',
                      child: Text('Oldest First'),
                    ),
                    if (widget.section == 'products')
                      const PopupMenuItem(
                        value: 'price_desc',
                        child: Text('Price: High to Low'),
                      ),
                    if (widget.section == 'products')
                      const PopupMenuItem(
                        value: 'price_asc',
                        child: Text('Price: Low to High'),
                      ),
                    if (widget.section == 'users')
                      const PopupMenuItem(
                        value: 'userName_asc',
                        child: Text('Name A-Z'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          
          // Main content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage.isNotEmpty
                    ? _buildErrorView()
                    : _buildDetailContent(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            'Error loading data',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(_errorMessage),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _fetchDetailData,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDetailContent() {
    // Extract the relevant list data based on section
    List<dynamic> items = [];
    int totalItems = 0;
    int currentPage = 1;
    int totalPages = 1;
    
    if (_detailData['success'] == true) {
      switch (widget.section) {
        case 'users':
          items = _detailData['users'] ?? [];
          totalItems = _detailData['totalUsers'] ?? 0;
          currentPage = _detailData['currentPage'] ?? 1;
          totalPages = _detailData['totalPages'] ?? 1;
          break;
        case 'products':
          items = _detailData['products'] ?? [];
          totalItems = _detailData['totalProducts'] ?? 0;
          currentPage = _detailData['currentPage'] ?? 1;
          totalPages = _detailData['totalPages'] ?? 1;
          break;
        case 'donations':
          items = _detailData['donations'] ?? [];
          totalItems = _detailData['totalDonations'] ?? 0;
          currentPage = _detailData['currentPage'] ?? 1;
          totalPages = _detailData['totalPages'] ?? 1;
          break;
        case 'reports':
          items = _detailData['reports'] ?? [];
          totalItems = _detailData['totalReports'] ?? 0;
          currentPage = _detailData['currentPage'] ?? 1;
          totalPages = _detailData['totalPages'] ?? 1;
          break;
        default:
          // Try a generic approach for other sections
          final sectionKey = '${widget.section}List';
          items = _detailData[sectionKey] ?? [];
          final totalKey = 'total${widget.section.substring(0, 1).toUpperCase()}${widget.section.substring(1)}';
          totalItems = _detailData[totalKey] ?? 0;
          currentPage = _detailData['currentPage'] ?? 1;
          totalPages = _detailData['totalPages'] ?? 1;
      }
    }
    
    if (items.isEmpty) {
      return _buildEmptyView();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Results count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'Showing ${items.length} of $totalItems ${widget.section}',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        
        // Items list
        Expanded(
          child: _buildItemsList(items),
        ),
        
        // Pagination
        if (totalPages > 1)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: currentPage > 1 ? () {
                    // Handle previous page
                  } : null,
                  child: const Text('Previous'),
                ),
                const SizedBox(width: 16),
                Text(
                  'Page $currentPage of $totalPages',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: currentPage < totalPages ? () {
                    // Handle next page
                  } : null,
                  child: const Text('Next'),
                ),
              ],
            ),
          ),
      ],
    );
  }
  
  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'No ${widget.section} found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _filterQuery.isNotEmpty
                ? 'Try changing your search query'
                : 'No data available for the selected time range',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_filterQuery.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _filterQuery = '';
                });
                _fetchDetailData();
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear Filters'),
            ),
        ],
      ),
    );
  }
  
  Widget _buildItemsList(List<dynamic> items) {
    switch (widget.section) {
      case 'users':
        return _buildUsersList(items);
      case 'products':
        return _buildProductsList(items);
      case 'donations':
        return _buildDonationsList(items);
      case 'reports':
        return _buildReportsList(items);
      default:
        return _buildGenericList(items);
    }
  }
  
  Widget _buildUsersList(List<dynamic> users) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final user = users[index];
        
        // Extract user data safely
        final userName = user['userName'] ?? '';
        final email = user['email'] ?? '';
        final role = user['role'] ?? 'user';
        final lastSeen = user['lastSeen'] != null 
            ? _formatTimeAgo(user['lastSeen']) 
            : 'Never';
        
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF1A73E8).withOpacity(0.1),
            child: Text(
              userName.isNotEmpty ? userName[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Color(0xFF1A73E8),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(userName),
          subtitle: Text(email),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getRoleColor(role).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatRole(role),
                  style: TextStyle(
                    color: _getRoleColor(role),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  // Show action menu
                  _showUserActionMenu(user);
                },
              ),
            ],
          ),
          onTap: () {
            // Navigate to user detail view
            _navigateToItemDetail('users', user['_id']);
          },
        );
      },
    );
  }
  
  Widget _buildProductsList(List<dynamic> products) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: products.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final product = products[index];
        
        // Extract product data safely
        final name = product['name'] ?? '';
        final price = product['price'] != null 
            ? '₹${product['price']}' 
            : 'No price';
        final category = product['category'] ?? '';
        final status = product['status'] ?? 'unknown';
        final seller = product['seller'] != null 
            ? (product['seller'] is Map 
                ? product['seller']['userName'] ?? '' 
                : '')
            : '';
        
        return ListTile(
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shopping_bag, color: Color(0xFF4CAF50)),
          ),
          title: Text(name),
          subtitle: Text('$category · Seller: $seller'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                price,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatStatus(status),
                  style: TextStyle(
                    color: _getStatusColor(status),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  // Show action menu
                  _showProductActionMenu(product);
                },
              ),
            ],
          ),
          onTap: () {
            // Navigate to product detail view
            _navigateToItemDetail('products', product['_id']);
          },
        );
      },
    );
  }
  
  Widget _buildDonationsList(List<dynamic> donations) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: donations.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final donation = donations[index];
        
        // Extract donation data safely
        final name = donation['name'] ?? '';
        final description = donation['description'] ?? '';
        final status = donation['status'] ?? 'unknown';
        final donatedBy = donation['donatedBy'] != null 
            ? (donation['donatedBy'] is Map 
                ? donation['donatedBy']['userName'] ?? '' 
                : '')
            : '';
        final donationDate = donation['donationDate'] != null 
            ? _formatTimeAgo(donation['donationDate']) 
            : '';
        
        return ListTile(
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.volunteer_activism, color: Color(0xFFFF9800)),
          ),
          title: Text(name),
          subtitle: Text(
            description.isNotEmpty 
                ? description 
                : 'Donated by $donatedBy · $donationDate',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatStatus(status),
                  style: TextStyle(
                    color: _getStatusColor(status),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  // Show action menu
                  _showDonationActionMenu(donation);
                },
              ),
            ],
          ),
          onTap: () {
            // Navigate to donation detail view
            _navigateToItemDetail('donations', donation['_id']);
          },
        );
      },
    );
  }
  
  Widget _buildReportsList(List<dynamic> reports) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: reports.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final report = reports[index];
        
        // Extract report data safely
        final reason = report['reason'] ?? '';
        final status = report['status'] ?? 'pending';
        final reportType = report['reportType'] ?? 'unknown';
        final createdAt = report['createdAt'] != null 
            ? _formatTimeAgo(report['createdAt']) 
            : '';
        
        // Get reporter and reported entity based on report type
        String reporterName = '';
        String reportedEntity = '';
        
        if (report['reporter'] != null && report['reporter'] is Map) {
          reporterName = report['reporter']['userName'] ?? '';
        }
        
        if (reportType == 'user') {
          if (report['reportedUser'] != null && report['reportedUser'] is Map) {
            reportedEntity = report['reportedUser']['userName'] ?? '';
          }
        } else if (reportType == 'product') {
          if (report['product'] != null && report['product'] is Map) {
            reportedEntity = report['product']['name'] ?? '';
          }
        }
        
        return ListTile(
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFE53935).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.report_problem, color: Color(0xFFE53935)),
          ),
          title: Text(
            reportType == 'user' 
                ? 'User Report: $reportedEntity' 
                : 'Product Report: $reportedEntity',
          ),
          subtitle: Text(
            'Reason: $reason · Reporter: $reporterName · $createdAt',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getReportStatusColor(status).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: _getReportStatusColor(status),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {
                  // Show action menu
                  _showReportActionMenu(report);
                },
              ),
            ],
          ),
          onTap: () {
            // Navigate to report detail view
            _navigateToItemDetail('reports', report['_id'], type: reportType);
          },
        );
      },
    );
  }
  
  Widget _buildGenericList(List<dynamic> items) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        
        // Try to extract common fields that might be present
        String title = '';
        String subtitle = '';
        
        if (item is Map) {
          // Look for likely title fields
          if (item.containsKey('name')) {
            title = item['name'].toString();
          } else if (item.containsKey('title')) {
            title = item['title'].toString();
          } else if (item.containsKey('id')) {
            title = 'Item ${item['id']}';
          } else if (item.containsKey('_id')) {
            title = 'Item ${item['_id']}';
          } else {
            title = 'Item ${index + 1}';
          }
          
          // Look for likely subtitle fields
          if (item.containsKey('description')) {
            subtitle = item['description'].toString();
          } else if (item.containsKey('details')) {
            subtitle = item['details'].toString();
          } else if (item.containsKey('createdAt')) {
            subtitle = 'Created: ${_formatTimeAgo(item['createdAt'].toString())}';
          }
        } else {
          title = 'Item ${index + 1}';
          subtitle = item.toString();
        }
        
        return ListTile(
          title: Text(title),
          subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
          trailing: IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              // Show item details if possible
              if (item is Map && item.containsKey('_id')) {
                _navigateToItemDetail(widget.section, item['_id']);
              }
            },
          ),
          onTap: () {
            // Show expanded details in a dialog
            _showItemDetailsDialog(item);
          },
        );
      },
    );
  }

  /// Format role text
  String _formatRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Admin';
      case 'volunteer':
        return 'Volunteer';
      case 'user':
        return 'User';
      default:
        return role.substring(0, 1).toUpperCase() + role.substring(1);
    }
  }

  /// Get color based on user role
  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.purple;
      case 'volunteer':
        return Colors.blue;
      case 'user':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  /// Format product status
  String _formatStatus(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Active';
      case 'sold':
        return 'Sold';
      case 'reserved':
        return 'Reserved';
      case 'claimed':
        return 'Claimed';
      default:
        return status.substring(0, 1).toUpperCase() + status.substring(1);
    }
  }

  /// Get color based on product status
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'sold':
        return Colors.orange;
      case 'reserved':
        return Colors.blue;
      case 'claimed':
        return Colors.purple;
      case 'pending':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  /// Get color based on report status
  Color _getReportStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'resolved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'investigating':
        return Colors.blue;
      case 'dismissed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  /// Format time ago from ISO date
  String _formatTimeAgo(String timeString) {
    try {
      final dateTime = DateTime.parse(timeString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inDays > 30) {
        return DateFormat('MMM d, yyyy').format(dateTime);
      } else if (difference.inDays > 0) {
        return '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}m ago';
      } else {
        return 'just now';
      }
    } catch (e) {
      return timeString;
    }
  }

  /// Show action menu for users
  void _showUserActionMenu(Map<String, dynamic> user) {
    final userId = user['_id'];
    final isActive = user['isActive'] == true;
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('View User Profile'),
              onTap: () {
                Navigator.pop(context);
                _navigateToItemDetail('users', userId);
              },
            ),
            ListTile(
              leading: Icon(isActive ? Icons.block : Icons.check_circle),
              title: Text(isActive ? 'Deactivate User' : 'Activate User'),
              onTap: () {
                Navigator.pop(context);
                _confirmUserStatusChange(userId, !isActive);
              },
            ),
            ListTile(
              leading: const Icon(Icons.message),
              title: const Text('Send Message'),
              onTap: () {
                Navigator.pop(context);
                // Implement send message functionality
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Show action menu for products
  void _showProductActionMenu(Map<String, dynamic> product) {
    final productId = product['_id'];
    final isActive = product['status']?.toLowerCase() == 'active';
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.shopping_bag),
              title: const Text('View Product Details'),
              onTap: () {
                Navigator.pop(context);
                _navigateToItemDetail('products', productId);
              },
            ),
            ListTile(
              leading: Icon(isActive ? Icons.unpublished : Icons.public),
              title: Text(isActive ? 'Unpublish Product' : 'Publish Product'),
              onTap: () {
                Navigator.pop(context);
                _confirmProductStatusChange(productId, !isActive);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete Product'),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteItem('products', productId, product['name']);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Show action menu for donations
  void _showDonationActionMenu(Map<String, dynamic> donation) {
    final donationId = donation['_id'];
    final status = donation['status']?.toLowerCase() ?? '';
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.volunteer_activism),
              title: const Text('View Donation Details'),
              onTap: () {
                Navigator.pop(context);
                _navigateToItemDetail('donations', donationId);
              },
            ),
            if (status == 'pending')
              ListTile(
                leading: const Icon(Icons.check_circle),
                title: const Text('Approve Donation'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDonationStatusChange(donationId, 'approved');
                },
              ),
            if (status == 'pending')
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Reject Donation'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDonationStatusChange(donationId, 'rejected');
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete Donation'),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteItem('donations', donationId, donation['name']);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Show action menu for reports
  void _showReportActionMenu(Map<String, dynamic> report) {
    final reportId = report['_id'];
    final status = report['status']?.toLowerCase() ?? 'pending';
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.report_problem),
              title: const Text('View Report Details'),
              onTap: () {
                Navigator.pop(context);
                _navigateToItemDetail('reports', reportId);
              },
            ),
            if (status == 'pending')
              ListTile(
                leading: const Icon(Icons.check_circle),
                title: const Text('Mark as Resolved'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmReportStatusChange(reportId, 'resolved');
                },
              ),
            if (status == 'pending')
              ListTile(
                leading: const Icon(Icons.update),
                title: const Text('Mark as Investigating'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmReportStatusChange(reportId, 'investigating');
                },
              ),
            if (status == 'pending' || status == 'investigating')
              ListTile(
                leading: const Icon(Icons.not_interested),
                title: const Text('Dismiss Report'),
                onTap: () {
                  Navigator.pop(context);
                  _confirmReportStatusChange(reportId, 'dismissed');
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Show generic item details in a dialog
  void _showItemDetailsDialog(dynamic item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Item Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item is Map) ...{
                for (var entry in item.entries)
                  if (entry.value != null && 
                      entry.value is! Map && 
                      entry.value is! List)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.key,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            entry.value.toString(),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
              } else ...{
                Text(item.toString()),
              },
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Navigate to item detail page
  void _navigateToItemDetail(String section, dynamic itemId, {String? type}) {
    print('Navigating to $section detail for item $itemId');
    // Implement navigation to item detail page
    // This would be a separate screen dedicated to viewing a single item
  }

  /// Confirm changing a user's active status
  void _confirmUserStatusChange(String userId, bool activate) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(activate ? 'Activate User?' : 'Deactivate User?'),
        content: Text(
          activate
              ? 'This will allow the user to access the platform again. Continue?'
              : 'This will prevent the user from accessing the platform. Continue?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateUserStatus(userId, activate);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: activate ? Colors.green : Colors.red,
            ),
            child: Text(activate ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );
  }

  /// Confirm changing a product's status
  void _confirmProductStatusChange(String productId, bool publish) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(publish ? 'Publish Product?' : 'Unpublish Product?'),
        content: Text(
          publish
              ? 'This will make the product visible to all users. Continue?'
              : 'This will hide the product from users. Continue?'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateProductStatus(productId, publish ? 'active' : 'inactive');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: publish ? Colors.green : Colors.orange,
            ),
            child: Text(publish ? 'Publish' : 'Unpublish'),
          ),
        ],
      ),
    );
  }

  /// Confirm changing a donation's status
  void _confirmDonationStatusChange(String donationId, String newStatus) {
    String title, message, buttonText;
    Color buttonColor;
    
    switch (newStatus) {
      case 'approved':
        title = 'Approve Donation?';
        message = 'This will make the donation available for claiming. Continue?';
        buttonText = 'Approve';
        buttonColor = Colors.green;
        break;
      case 'rejected':
        title = 'Reject Donation?';
        message = 'This will reject the donation and notify the donor. Continue?';
        buttonText = 'Reject';
        buttonColor = Colors.red;
        break;
      default:
        title = 'Update Status?';
        message = 'Change donation status to $newStatus?';
        buttonText = 'Update';
        buttonColor = Colors.blue;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateDonationStatus(donationId, newStatus);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor,
            ),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Confirm changing a report's status
  void _confirmReportStatusChange(String reportId, String newStatus) {
    String title, message, buttonText;
    Color buttonColor;
    
    switch (newStatus) {
      case 'resolved':
        title = 'Mark as Resolved?';
        message = 'This will mark the report as resolved and notify the reporter. Continue?';
        buttonText = 'Resolve';
        buttonColor = Colors.green;
        break;
      case 'investigating':
        title = 'Mark as Investigating?';
        message = 'This will update the report status to investigating. Continue?';
        buttonText = 'Investigate';
        buttonColor = Colors.blue;
        break;
      case 'dismissed':
        title = 'Dismiss Report?';
        message = 'This will dismiss the report. Continue?';
        buttonText = 'Dismiss';
        buttonColor = Colors.orange;
        break;
      default:
        title = 'Update Status?';
        message = 'Change report status to $newStatus?';
        buttonText = 'Update';
        buttonColor = Colors.blue;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateReportStatus(reportId, newStatus);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor,
            ),
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  /// Confirm deleting an item
  void _confirmDeleteItem(String section, String itemId, String itemName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Are you sure you want to delete "$itemName"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteItem(section, itemId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// API function to update user status
  Future<void> _updateUserStatus(String userId, bool activate) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final authCookie = await widget.authCookie;
      
      final response = await http.patch(
        Uri.parse(
          'https://olx-for-iitrpr-backend.onrender.com/api/admin/users/$userId'
        ),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'isActive': activate,
        }),
      );
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User ${activate ? 'activated' : 'deactivated'} successfully'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Refresh data
        _fetchDetailData();
      } else {
        throw Exception('Failed to update user: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating user: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// API function to update product status
  Future<void> _updateProductStatus(String productId, String status) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final authCookie = await widget.authCookie;
      
      final response = await http.patch(
        Uri.parse(
          'https://olx-for-iitrpr-backend.onrender.com/api/admin/products/$productId'
        ),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'status': status,
        }),
      );
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Product status updated to $status'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Refresh data
        _fetchDetailData();
      } else {
        throw Exception('Failed to update product: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating product: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// API function to update donation status
  Future<void> _updateDonationStatus(String donationId, String status) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final authCookie = await widget.authCookie;
      
      final response = await http.patch(
        Uri.parse(
          'https://olx-for-iitrpr-backend.onrender.com/api/admin/donations/$donationId'
        ),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'status': status,
        }),
      );
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Donation status updated to $status'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Refresh data
        _fetchDetailData();
      } else {
        throw Exception('Failed to update donation: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating donation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// API function to update report status
  Future<void> _updateReportStatus(String reportId, String status) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final authCookie = await widget.authCookie;
      
      final response = await http.patch(
        Uri.parse(
          'https://olx-for-iitrpr-backend.onrender.com/api/admin/reports/$reportId'
        ),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
        body: json.encode({
          'status': status,
        }),
      );
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Report status updated to $status'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Refresh data
        _fetchDetailData();
      } else {
        throw Exception('Failed to update report: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// API function to delete an item
  Future<void> _deleteItem(String section, String itemId) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final authCookie = await widget.authCookie;
      
      final response = await http.delete(
        Uri.parse(
          'https://olx-for-iitrpr-backend.onrender.com/api/admin/$section/$itemId'
        ),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Item deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        
        // Refresh data
        _fetchDetailData();
      } else {
        throw Exception('Failed to delete item: ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting item: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Export data to CSV
  void _exportData() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Exporting data... This feature is not yet implemented.'),
      ),
    );
    
    // This would typically:
    // 1. Format the data as CSV
    // 2. Generate a downloadable file
    // 3. Either trigger a download or send to email
  }

}