import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

import 'view_report.dart' hide StringExtension;

class ReportsTab extends StatefulWidget {
  const ReportsTab({Key? key}) : super(key: key);

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final _secureStorage = const FlutterSecureStorage();
  List<dynamic> _allReports = []; // All reports for client-side filtering
  List<dynamic> _filteredReports = []; // Filtered reports to display
  bool _isLoading = true;
  bool _isError = false;
  String _errorMessage = '';
  final bool _isPerformingAction = false;
  bool _isFilterExpanded = false;
  
  // Pagination for initial fetch
  int _currentPage = 1;
  int _totalPages = 1;
  final int _pageSize = 100; // Increased to fetch more reports at once
  
  // Filters - now applied client-side
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
    _fetchAllReports();
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

  // Method to fetch all reports at once
  Future<void> _fetchAllReports() async {
    setState(() {
      _isLoading = true;
      _isError = false;
      _currentPage = 1;
    });

    try {
      final authCookie = await _secureStorage.read(key: 'authCookie');
      
      final uri = Uri.https(
        'olx-for-iitrpr-backend.onrender.com',
        '/api/admin/reports',
        {
          'page': '1',
          'limit': '100', // Get more reports at once
        }
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
          _allReports = data['reports'] ?? [];
          _totalPages = data['totalPages'] ?? 1;
          _applyFilters(); // Apply initial filters
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
      
      final uri = Uri.https(
        'olx-for-iitrpr-backend.onrender.com',
        '/api/admin/reports',
        {
          'page': (_currentPage + 1).toString(),
          'limit': '100',
        }
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
          _allReports.addAll(data['reports'] ?? []);
          _currentPage++;
          _applyFilters(); // Reapply filters with new data
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
  
  // New method to apply filters client-side
  void _applyFilters() {
    setState(() {
      _filteredReports = _allReports.where((report) {
        // Filter by report type
        if (_selectedReportType != 'all' && 
            report['reportType'] != _selectedReportType) {
          return false;
        }
        
        // Filter by status
        if (_selectedStatus != 'all' && 
            report['status'] != _selectedStatus) {
          return false;
        }
        
        // Filter by date range
        if (_startDate != null && _endDate != null) {
          final reportDate = DateTime.parse(report['createdAt']);
          // Add one day to end date to include the whole day
          final adjustedEndDate = _endDate!.add(const Duration(days: 1));
          
          if (reportDate.isBefore(_startDate!) || 
              reportDate.isAfter(adjustedEndDate)) {
            return false;
          }
        }
        
        return true;
      }).toList();
    });
  }

  // IMPROVED: Custom date range picker using Syncfusion widget
  Future<void> _selectDateRange() async {
    DateTime? localStartDate = _startDate;
    DateTime? localEndDate = _endDate;
    
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: Colors.white,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A73E8),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Text(
                      'Select Date Range',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              
              // Date picker - Using Expanded to avoid overflow
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  width: double.infinity,
                  child: SfDateRangePicker(
                    backgroundColor: Colors.white,
                    view: DateRangePickerView.month,
                    selectionMode: DateRangePickerSelectionMode.range,
                    monthViewSettings: const DateRangePickerMonthViewSettings(
                      firstDayOfWeek: 1,
                    ),
                    selectionColor: const Color(0xFF1A73E8),
                    startRangeSelectionColor: const Color(0xFF1A73E8),
                    endRangeSelectionColor: const Color(0xFF1A73E8),
                    rangeSelectionColor: const Color(0xFF1A73E8).withOpacity(0.1),
                    todayHighlightColor: const Color(0xFF1A73E8),
                    initialSelectedRange: PickerDateRange(
                      _startDate ?? DateTime.now().subtract(const Duration(days: 7)),
                      _endDate ?? DateTime.now(),
                    ),
                    onSelectionChanged: (DateRangePickerSelectionChangedArgs args) {
                      if (args.value is PickerDateRange) {
                        final range = args.value as PickerDateRange;
                        localStartDate = range.startDate;
                        localEndDate = range.endDate ?? range.startDate;
                      }
                    },
                  ),
                ),
              ),
              
              // Action buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF1A73E8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A73E8),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        if (localStartDate != null && localEndDate != null) {
                          setState(() {
                            _startDate = localStartDate;
                            _endDate = localEndDate;
                          });
                          _applyFilters();
                        }
                        Navigator.pop(context);
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _clearFilters() {
    setState(() {
      _selectedReportType = 'all';
      _selectedStatus = 'all';
      _startDate = null;
      _endDate = null;
    });
    
    _applyFilters(); // Reset to show all reports
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
        return Colors.red;
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
      backgroundColor: Colors.white, // Set white background
      body: Stack(
        children: [
          Column(
            children: [
              // Filter section
              _buildCompactFilterBar(),
              
              // Reports list
              Expanded(
                child: _isLoading && _allReports.isEmpty
                    ? _buildShimmerLoading()
                    : _isError && _allReports.isEmpty
                        ? _buildErrorView()
                        : _filteredReports.isEmpty
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
                                onRefresh: _fetchAllReports,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  itemCount: _filteredReports.length + (_currentPage < _totalPages ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index == _filteredReports.length) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 16.0),
                                        child: Center(child: CircularProgressIndicator()),
                                      );
                                    }
                                    
                                    final report = _filteredReports[index];
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
  
  // Improved error view with sad emoji
  Widget _buildErrorView() {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(16),
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage,
                  style: TextStyle(color: Colors.red.shade800),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchAllReports,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A73E8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Shimmer loading effect that matches report card style
  Widget _buildShimmerLoading() {
    return Column(
      children: [        
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Shimmer.fromColors(
              baseColor: Colors.grey[300]!,
              highlightColor: Colors.grey[100]!,
              child: ListView.builder(
                itemCount: 8,
                itemBuilder: (_, __) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      height: 100,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // Circle avatar placeholder
                          Container(
                            width: 48.0,
                            height: 48.0,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 16.0),
                          // Content placeholder
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Container(
                                  width: double.infinity,
                                  height: 14.0,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 8.0),
                                Container(
                                  width: MediaQuery.of(context).size.width * 0.6,
                                  height: 12.0,
                                  color: Colors.white,
                                ),
                                const SizedBox(height: 8.0),
                                Container(
                                  width: MediaQuery.of(context).size.width * 0.4,
                                  height: 10.0,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                          // Status badge placeholder
                          Container(
                            width: 60.0,
                            height: 24.0,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  // Improved compact filter bar with consistent colors
  Widget _buildCompactFilterBar() {
    // Unified color scheme for all filters
    const filterColor = Color(0xFF1A73E8);
    
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Filter button is full width
          InkWell(
            onTap: () {
              setState(() {
                _isFilterExpanded = !_isFilterExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _hasActiveFilters() ? filterColor.withOpacity(0.1) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hasActiveFilters() ? filterColor : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list,
                    size: 16,
                    color: _hasActiveFilters() ? filterColor : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Filters',
                    style: TextStyle(
                      color: _hasActiveFilters() ? filterColor : Colors.grey.shade700,
                      fontWeight: _hasActiveFilters() ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (_hasActiveFilters())
                    Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: filterColor,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _getActiveFilterCount().toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const Spacer(),
                  if (_hasActiveFilters())
                    TextButton(
                      onPressed: _clearFilters,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: filterColor,
                      ),
                      child: const Text('Clear All', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
          
          // Active filter chips
          if (_hasActiveFilters())
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Report type filter chip
                    if (_selectedReportType != 'all')
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          height: 28, // Even smaller
                          padding: const EdgeInsets.only(left: 8, right: 4),
                          decoration: BoxDecoration(
                            color: filterColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: filterColor.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _selectedReportType == 'user' ? 'User Reports' : 'Product Reports',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: filterColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    setState(() {
                                      _selectedReportType = 'all';
                                    });
                                    _applyFilters();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: filterColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    // Status filter chip
                    if (_selectedStatus != 'all')
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          height: 28, // Even smaller
                          padding: const EdgeInsets.only(left: 8, right: 4),
                          decoration: BoxDecoration(
                            color: filterColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: filterColor.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _selectedStatus.capitalize(),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: filterColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    setState(() {
                                      _selectedStatus = 'all';
                                    });
                                    _applyFilters();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: filterColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    // Date range filter chip
                    if (_startDate != null && _endDate != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Container(
                          height: 28, // Even smaller
                          padding: const EdgeInsets.only(left: 8, right: 4),
                          decoration: BoxDecoration(
                            color: filterColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: filterColor.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${DateFormat('MM/dd').format(_startDate!)} - ${DateFormat('MM/dd').format(_endDate!)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: filterColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    setState(() {
                                      _startDate = null;
                                      _endDate = null;
                                    });
                                    _applyFilters();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(4.0),
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: filterColor,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          
          // Expanded filter options (only shown when expanded)
          if (_isFilterExpanded)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              margin: const EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Report type filter - FIX: Made full width using container and row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Report Type',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          child: Row(
                            children: [
                              _buildFilterOptionChip(
                                'All',
                                _selectedReportType == 'all',
                                () {
                                  setState(() {
                                    _selectedReportType = 'all';
                                  });
                                  _applyFilters();
                                },
                                filterColor,
                              ),
                              const SizedBox(width: 8),
                              _buildFilterOptionChip(
                                'User',
                                _selectedReportType == 'user',
                                () {
                                  setState(() {
                                    _selectedReportType = 'user';
                                  });
                                  _applyFilters();
                                },
                                filterColor,
                              ),
                              const SizedBox(width: 8),
                              _buildFilterOptionChip(
                                'Product',
                                _selectedReportType == 'product',
                                () {
                                  setState(() {
                                    _selectedReportType = 'product';
                                  });
                                  _applyFilters();
                                },
                                filterColor,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Status filter - FIX: Made full width using container and row
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Status',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          child: Row(
                            children: [
                              _buildFilterOptionChip(
                                'All',
                                _selectedStatus == 'all',
                                () {
                                  setState(() {
                                    _selectedStatus = 'all';
                                  });
                                  _applyFilters();
                                },
                                filterColor,
                              ),
                              const SizedBox(width: 8),
                              _buildFilterOptionChip(
                                'Pending',
                                _selectedStatus == 'pending',
                                () {
                                  setState(() {
                                    _selectedStatus = 'pending';
                                  });
                                  _applyFilters();
                                },
                                filterColor,
                              ),
                              const SizedBox(width: 8),
                              _buildFilterOptionChip(
                                'Resolved',
                                _selectedStatus == 'resolved',
                                () {
                                  setState(() {
                                    _selectedStatus = 'resolved';
                                  });
                                  _applyFilters();
                                },
                                filterColor,
                              ),
                              const SizedBox(width: 8),
                              _buildFilterOptionChip(
                                'Dismissed',
                                _selectedStatus == 'dismissed',
                                () {
                                  setState(() {
                                    _selectedStatus = 'dismissed';
                                  });
                                  _applyFilters();
                                },
                                filterColor,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 8),
                  
                  // Date range filter button - FIX: Made full width with Container
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Date Range',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Full width date picker button
                        InkWell(
                          onTap: _selectDateRange,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.date_range, 
                                    size: 14, 
                                    color: filterColor),
                                const SizedBox(width: 6),
                                Text(
                                  _startDate != null && _endDate != null
                                      ? '${DateFormat('MM/dd/yy').format(_startDate!)} - ${DateFormat('MM/dd/yy').format(_endDate!)}'
                                      : 'Select Date Range',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _startDate != null ? Colors.black87 : Colors.grey.shade600,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.arrow_drop_down,
                                  size: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          // Results counter - Always shown, even during loading
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4, left: 0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _isLoading && _allReports.isEmpty
                ? 'Showing 0 reports'
                : 'Showing ${_filteredReports.length} report${_filteredReports.length != 1 ? 's' : ''}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          
          const Divider(height: 1),
        ],
      ),
    );
  }
  
  // Helper method to build consistent filter option chips
  Widget _buildFilterOptionChip(String label, bool isSelected, VoidCallback onTap, Color color) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 28, // Smaller height
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color.withOpacity(0.5) : Colors.grey.shade300,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: isSelected ? color : Colors.grey.shade700,
              fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
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
    
    // Updated to match the notification style
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: _getReportTypeIcon(reportType).color!.withOpacity(0.1),
          child: _getReportTypeIcon(reportType),
        ),
        title: Text(
          reportType == 'user'
              ? 'User Report: $reportedEntity'
              : 'Product Report: $reportedEntity',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Reported by $reporter',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 2),
            Text(
              'Reason: $reason • $createdAt',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _getStatusColor(status).withOpacity(0.1),
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
            _fetchAllReports();
          });
        },
      ),
    );
  }
  
  // Helper methods for filter UI
  bool _hasActiveFilters() {
    return _selectedReportType != 'all' || 
           _selectedStatus != 'all' || 
           (_startDate != null && _endDate != null);
  }
  
  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedReportType != 'all') count++;
    if (_selectedStatus != 'all') count++;
    if (_startDate != null && _endDate != null) count++;
    return count;
  }
}

// Extension to add capitalize functionality to String
extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${this.substring(1)}";
  }
}
