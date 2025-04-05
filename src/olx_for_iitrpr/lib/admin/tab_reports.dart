// tab_reports.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'view_report.dart';

class ReportsTab extends StatefulWidget {
  const ReportsTab({Key? key}) : super(key: key);

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _secureStorage = const FlutterSecureStorage();
  List<dynamic> _reports = [];
  bool _isLoading = true;
  bool _isError = false;
  String _errorMessage = '';
  final bool _isPerformingAction = false;
  
  // Pagination
  int _currentPage = 1;
  int _totalPages = 1;
  final int _pageSize = 10;
  
  // Filters
  String _selectedReportType = 'all';
  String _selectedStatus = 'all';
  DateTime? _startDate;
  DateTime? _endDate;
  
  // Expanded report
  String? _expandedReportId;
  
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchReports();
    _scrollController.addListener(_scrollListener);
  }
  
  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    super.dispose();
  }
  
  void _scrollListener() {
    if (_scrollController.offset >= _scrollController.position.maxScrollExtent &&
        !_scrollController.position.outOfRange) {
      if (_currentPage < _totalPages && !_isLoading) {
        _loadMoreReports();
      }
    }
  }

  Future<void> _fetchReports() async {
    setState(() {
      _isLoading = true;
      _isError = false;
      _currentPage = 1;
    });

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // Build query parameters
      final Map<String, String> queryParams = {
        'page': _currentPage.toString(),
        'limit': _pageSize.toString(),
      };
      
      if (_selectedReportType != 'all') {
        queryParams['type'] = _selectedReportType;
      }
      
      if (_selectedStatus != 'all') {
        queryParams['status'] = _selectedStatus;
      }
      
      if (_startDate != null) {
        queryParams['startDate'] = DateFormat('yyyy-MM-dd').format(_startDate!);
      }
      
      if (_endDate != null) {
        queryParams['endDate'] = DateFormat('yyyy-MM-dd').format(_endDate!);
      }
      
      final uri = Uri.https(
        'olx-for-iitrpr-backend.onrender.com',
        '/api/admin/reports',
        queryParams
      );
      
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _reports = data['reports'] ?? [];
          _totalPages = data['totalPages'] ?? 1;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isError = true;
          _errorMessage = data['message'] ?? 'Failed to load reports';
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
  
  Future<void> _loadMoreReports() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      // Build query parameters
      final Map<String, String> queryParams = {
        'page': (_currentPage + 1).toString(),
        'limit': _pageSize.toString(),
      };
      
      if (_selectedReportType != 'all') {
        queryParams['type'] = _selectedReportType;
      }
      
      if (_selectedStatus != 'all') {
        queryParams['status'] = _selectedStatus;
      }
      
      if (_startDate != null) {
        queryParams['startDate'] = DateFormat('yyyy-MM-dd').format(_startDate!);
      }
      
      if (_endDate != null) {
        queryParams['endDate'] = DateFormat('yyyy-MM-dd').format(_endDate!);
      }
      
      final uri = Uri.https(
        'olx-for-iitrpr-backend.onrender.com',
        '/api/admin/reports',
        queryParams
      );
      
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'auth-cookie': authCookie ?? '',
        },
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _reports.addAll(data['reports'] ?? []);
          _currentPage++;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isError = true;
          _errorMessage = data['message'] ?? 'Failed to load more reports';
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

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      
      _fetchReports();
    }
  }
  
  void _clearFilters() {
    setState(() {
      _selectedReportType = 'all';
      _selectedStatus = 'all';
      _startDate = null;
      _endDate = null;
    });
    
    _fetchReports();
  }
  
  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return 'N/A';
    
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return DateFormat('MMM d, yyyy h:mm a').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }
  
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'resolved':
        return Colors.green;
      case 'dismissed':
      case 'rejected':
        return Colors.red;
      case 'reviewed':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
  
  Icon _getReportTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'user':
        return const Icon(Icons.person, color: Colors.blue);
      case 'product':
        return const Icon(Icons.shopping_bag, color: Colors.green);
      default:
        return const Icon(Icons.report, color: Colors.orange);
    }
  }
  
  String _getReasonText(String reason, String reportType) {
    if (reportType == 'user') {
      switch (reason) {
        case 'spam':
          return 'Spam';
        case 'harassment':
          return 'Harassment';
        case 'inappropriate_content':
          return 'Inappropriate Content';
        case 'fake_account':
          return 'Fake Account';
        case 'other':
          return 'Other';
        default:
          return reason;
      }
    } else {
      return reason;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              // Filter section
              _buildFilterSection(),
              
              // Reports list
              Expanded(
                child: _isLoading && _reports.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _isError && _reports.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                                const SizedBox(height: 16),
                                Text(_errorMessage),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _fetchReports,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          )
                        : _reports.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No reports found',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _fetchReports,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  itemCount: _reports.length + (_currentPage < _totalPages ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == _reports.length) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 16.0),
                                        child: Center(child: CircularProgressIndicator()),
                                      );
                                    }
                                    
                                    final report = _reports[index];
                                    final bool isExpanded = _expandedReportId == report['_id'];
                                    
                                    return _buildReportItem(report, isExpanded);
                                  },
                                ),
                              ),
              ),
            ],
          ),
          
          // Loading overlay
          if (_isPerformingAction)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildFilterSection() {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_list, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Filters',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear All'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Report Type',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    value: _selectedReportType,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Types')),
                      DropdownMenuItem(value: 'user', child: Text('User Reports')),
                      DropdownMenuItem(value: 'product', child: Text('Product Reports')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedReportType = value!;
                      });
                      _fetchReports();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    value: _selectedStatus,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Statuses')),
                      DropdownMenuItem(value: 'pending', child: Text('Pending')),
                      DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                      DropdownMenuItem(value: 'dismissed', child: Text('Dismissed')),
                      DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                      DropdownMenuItem(value: 'reviewed', child: Text('Reviewed')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedStatus = value!;
                      });
                      _fetchReports();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _selectDateRange,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.date_range, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _startDate != null && _endDate != null
                          ? '${DateFormat('MMM d, yyyy').format(_startDate!)} - ${DateFormat('MMM d, yyyy').format(_endDate!)}'
                          : 'Select Date Range',
                      style: TextStyle(
                        color: _startDate != null ? Colors.black : Colors.grey.shade600,
                      ),
                    ),
                    const Spacer(),
                    if (_startDate != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          setState(() {
                            _startDate = null;
                            _endDate = null;
                          });
                          _fetchReports();
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildReportItem(Map<String, dynamic> report, bool isExpanded) {
    final reportType = report['reportType'] ?? 'unknown';
    final reportId = report['_id'] ?? '';
    final status = report['status'] ?? 'pending';
    final createdAt = _formatDateTime(report['createdAt']);
    final reason = _getReasonText(report['reason'] ?? '', reportType);
    
    final reporter = report['reporter'] != null
        ? report['reporter']['userName'] ?? 'Unknown User'
        : 'Unknown User';
    
    final reportedEntity = reportType == 'user'
        ? report['reportedUser'] != null
            ? report['reportedUser']['userName'] ?? 'Unknown User'
            : 'Unknown User'
        : report['product'] != null
            ? report['product']['name'] ?? 'Unknown Product'
            : 'Unknown Product';
    
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: _getReportTypeIcon(reportType),
        title: Text(
          reportType == 'user'
              ? 'User Report: $reportedEntity'
              : 'Product Report: $reportedEntity',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reported by $reporter on $createdAt'),
            const SizedBox(height: 4),
            Text('Reason: $reason'),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getStatusColor(status).withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            status.toUpperCase(),
            style: TextStyle(
              color: _getStatusColor(status),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ReportDetailScreen(
                reportId: reportId,
                reportType: reportType,
              ),
            ),
          ).then((_) {
            // Refresh the reports list when returning from detail screen
            _fetchReports();
          });
        },
      ),
    );
  }
}
