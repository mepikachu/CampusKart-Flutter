import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'server.dart';
import 'view_all_users.dart';
import 'view_product.dart';
import 'view_donation.dart';
import 'tab_reports.dart';

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
  
  // Dashboard data
  bool _isLoading = true;
  Map<String, dynamic> _dashboardData = {};
  bool _hasError = false;
  String _errorMessage = '';
  
  // Category colors for sections
  final Map<String, Color> _categoryColors = {
    'users': Colors.black,
    'products': Color(0xFF4CAF50),
    'donations': Color(0xFFFF9800),
    'volunteers': Color(0xFF9C27B0),
    'reports': Color(0xFFE53935),
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
      
      // Fetch dashboard overview data
      final response = await http.get(
        Uri.parse('$serverUrl/api/admin/dashboard'),
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );
      
      if (response.statusCode == 200) {
        final overviewData = json.decode(response.body);
        
        // Now fetch more detailed data for each section in parallel
        final List<Future> fetchFutures = [
          _fetchSectionData('users/stats', authCookie),
          _fetchSectionData('products/stats', authCookie),
          _fetchSectionData('donations/stats', authCookie), 
          _fetchSectionData('volunteers/stats', authCookie),
          _fetchSectionData('reports/stats', authCookie),
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
  ) async {
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/api/admin/$endpoint'),
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
      color: Colors.white, // Set pure white background
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!), // Add subtle border
      ),
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
          // See All button removed as per update
        ],
      ),
    );
  }

  /// Users section with user metrics and charts
  Widget _buildUsersSection() {
    final usersData = _dashboardData['usersData'] ?? {};
    final userGrowth = usersData['userGrowth'] ?? [];
    final userEngagement = usersData['userEngagement'] ?? {};
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'User Activity',
          Icons.people,
          _categoryColors['users']!,
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AllUsersScreen()),
          ),
        ),
        SizedBox(
          height: 220,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
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
                  'User Engagement',
                  userEngagement.isNotEmpty
                    ? _buildPieChartCentered({
                        'Highly Engaged': userEngagement['highlyEngaged'] ?? 0,
                        'Moderately Engaged': userEngagement['moderatelyEngaged'] ?? 0,
                        'Low Engagement': userEngagement['lowEngagement'] ?? 0,
                      }, _categoryColors['users']!)
                    : _buildEmptyPlaceholder('No user engagement data available'),
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
          () {}, // Remove navigation
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
                    ? _buildCategoryPieChartCentered(categoryDistribution, _categoryColors['products']!)
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
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Donations Overview',
          Icons.volunteer_activism,
          _categoryColors['donations']!,
          () {}, // Remove navigation
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
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AllUsersScreen()),
          ),
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
                    ? _buildCategoryPieChartCentered(taskCategories, _categoryColors['volunteers']!)
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
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Reports Overview',
          Icons.report_problem,
          _categoryColors['reports']!,
          () {},
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
                    ? _buildCategoryPieChartCentered(reportCategories, _categoryColors['reports']!)
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
          color: Colors.white,
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
                        children: recentActivity.take(10).map<Widget>((activity) {
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

  /// Chart card implementation
  Widget _buildChartCard(String title, Widget child) {
    return Card(
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: child),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
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

  /// Pie chart implementation with centered layout and legend below
  Widget _buildPieChartCentered(Map<String, dynamic> data, Color baseColor) {
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
      
      final legendItems = <Map<String, dynamic>>[];
      int i = 0;
      data.forEach((key, value) {
        final double percentage = (value as num) / total * 100;
        sections.add(
          PieChartSectionData(
            color: colors[i % colors.length],
            value: value.toDouble(),
            title: percentage >= 10 ? '${percentage.toStringAsFixed(0)}%' : '',
            radius: 40, // Reduced from 60
            titleStyle: const TextStyle(
              fontSize: 10, // Reduced from 12
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            titlePositionPercentageOffset: 0.55,
          ),
        );
        
        legendItems.add({
          'color': colors[i % colors.length],
          'label': key,
          'value': value,
        });
        
        i++;
      });

      return Column(
        mainAxisSize: MainAxisSize.min, // Add this to make column compact
        children: [
          SizedBox(
            height: 100, // Fixed height for chart
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 20, // Reduced from 25
                sectionsSpace: 1, // Reduced from 2
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView( // Make legend scrollable
              child: Wrap(
                spacing: 8, // Reduced spacing
                runSpacing: 4, // Reduced spacing
                alignment: WrapAlignment.center,
                children: legendItems.map((item) {
                  return Container(
                    margin: EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, // Smaller indicator
                          height: 6,
                          decoration: BoxDecoration(
                            color: item['color'] as Color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item['label']} (${_formatNumber(item['value'])})',
                          style: const TextStyle(fontSize: 9), // Smaller text
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

  Widget _buildCategoryPieChartCentered(List data, Color baseColor) {
    if (data.isEmpty) {
      return Center(child: Text('No data available'));
    }

    try {
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
      
      final legendItems = <Map<String, dynamic>>[];
      
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
            radius: 40, // Reduced from 60
            titleStyle: const TextStyle(
              fontSize: 10, // Reduced from 12
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

      return Column(
        mainAxisSize: MainAxisSize.min, // Add this to make column compact
        children: [
          SizedBox(
            height: 100, // Fixed height for chart
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 20, // Reduced from 25
                sectionsSpace: 1, // Reduced from 2
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView( // Make legend scrollable
              child: Wrap(
                spacing: 8, // Reduced spacing
                runSpacing: 4, // Reduced spacing
                alignment: WrapAlignment.center,
                children: legendItems.map((item) {
                  return Container(
                    margin: EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, // Smaller indicator
                          height: 6,
                          decoration: BoxDecoration(
                            color: item['color'] as Color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${item['label']} (${item['value']})',
                          style: const TextStyle(fontSize: 9), // Smaller text
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
}

/// Product detail page with modified UI
class ViewProduct extends StatefulWidget {
  const ViewProduct({Key? key}) : super(key: key);

  @override
  State<ViewProduct> createState() => _ViewProductState();
}

class _ViewProductState extends State<ViewProduct> {
  bool _isLoading = true;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.shade200,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text(
          'Products',
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: Center(
        child: Text('Product list will be shown here'),
      ),
    );
  }
}

/// Donation detail page with modified UI
class ViewDonation extends StatefulWidget {
  const ViewDonation({Key? key}) : super(key: key);

  @override
  State<ViewDonation> createState() => _ViewDonationState();
}

class _ViewDonationState extends State<ViewDonation> {
  bool _isLoading = true;
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey.shade200,
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text(
          'Donations',
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: Center(
        child: Text('Donation list will be shown here'),
      ),
    );
  }
}
