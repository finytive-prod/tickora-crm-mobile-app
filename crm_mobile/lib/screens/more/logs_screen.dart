import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:crm_mobile/core/theme/app_colors.dart';
import 'package:crm_mobile/core/network/network_log_manager.dart';

class NetworkLogsScreen extends StatefulWidget {
  const NetworkLogsScreen({super.key});

  @override
  State<NetworkLogsScreen> createState() => _NetworkLogsScreenState();
}

class _NetworkLogsScreenState extends State<NetworkLogsScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late final TabController _tabController;
  String _selectedFilter = 'ALL';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _clearLogs() {
    final isAudioTab = _tabController.index == 1;
    final tabLabel = isAudioTab ? 'Audio & Calls' : 'API Logs';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Clear Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text(
          'Choose whether to clear only $tabLabel or all recorded network logs.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (isAudioTab) {
                NetworkLogManager.instance.clearAudioAndCallLogs();
              } else {
                NetworkLogManager.instance.clearGeneralLogs();
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$tabLabel cleared successfully'),
                  backgroundColor: AppColors.primary,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Text(
              'Clear $tabLabel',
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              NetworkLogManager.instance.clearLogs();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('All logs cleared successfully'),
                  backgroundColor: AppColors.primary,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  List<NetworkLogItem> _filterLogs(List<NetworkLogItem> allLogs) {
    return allLogs.where((item) {
      // Filter by method / type
      if (_selectedFilter == 'ERRORS') {
        if (!item.isError && (item.statusCode == null || item.statusCode! < 400)) {
          return false;
        }
      } else if (_selectedFilter != 'ALL') {
        if (_selectedFilter == 'PUT/PATCH') {
          if (item.method != 'PUT' && item.method != 'PATCH') return false;
        } else if (item.method != _selectedFilter) {
          return false;
        }
      }

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final matchesUrl = item.url.toLowerCase().contains(query);
        final matchesPath = item.path.toLowerCase().contains(query);
        final matchesMethod = item.method.toLowerCase().contains(query);
        final matchesStatus = item.statusCode?.toString().contains(query) ?? false;
        final matchesBody = item.requestBody?.toString().toLowerCase().contains(query) ?? false;
        final matchesResp = item.responseBody?.toString().toLowerCase().contains(query) ?? false;

        if (!matchesUrl &&
            !matchesPath &&
            !matchesMethod &&
            !matchesStatus &&
            !matchesBody &&
            !matchesResp) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Color _getMethodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return const Color(0xFF2563EB); // Blue
      case 'POST':
        return const Color(0xFF16A34A); // Green
      case 'PUT':
      case 'PATCH':
        return const Color(0xFFD97706); // Amber
      case 'DELETE':
        return AppColors.primary;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _getStatusColor(int? statusCode, bool isPending, bool isError) {
    if (isPending) return const Color(0xFFF59E0B);
    if (isError || (statusCode != null && statusCode >= 400)) {
      return AppColors.primary;
    }
    if (statusCode != null && statusCode >= 200 && statusCode < 300) {
      return const Color(0xFF16A34A);
    }
    return AppColors.textSecondary;
  }

  void _openLogDetails(NetworkLogItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LogDetailModal(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: ListenableBuilder(
          listenable: NetworkLogManager.instance,
          builder: (context, _) {
            final count = NetworkLogManager.instance.count;
            return Row(
              children: [
                const Text(
                  'Network Logs',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: AppColors.primary),
            tooltip: 'Clear Logs',
            onPressed: _clearLogs,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: ListenableBuilder(
            listenable: NetworkLogManager.instance,
            builder: (context, _) {
              final generalCount = NetworkLogManager.instance.generalCount;
              final audioAndCallCount =
                  NetworkLogManager.instance.audioAndCallCount;
              return TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                indicatorWeight: 2.5,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                tabs: [
                  _buildTabItem(
                    icon: Icons.api_rounded,
                    label: 'API Logs',
                    count: generalCount,
                  ),
                  _buildTabItem(
                    icon: Icons.audiotrack_outlined,
                    label: 'Audio & Calls',
                    count: audioAndCallCount,
                  ),
                ],
              );
            },
          ),
        ),
      ),
      body: Column(
        children: [
          // Search & Filter Header Container
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                // Search Input
                Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim();
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search URL, method, status, body...',
                      hintStyle: const TextStyle(fontSize: 13, color: AppColors.textHint),
                      prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.textHint),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: AppColors.textHint),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                });
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 10),

                // Method Filters
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('ALL', 'All'),
                      _buildFilterChip('GET', 'GET'),
                      _buildFilterChip('POST', 'POST'),
                      _buildFilterChip('PUT/PATCH', 'PUT/PATCH'),
                      _buildFilterChip('DELETE', 'DELETE'),
                      _buildFilterChip('ERRORS', 'Errors 🔴'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Logs List Section (Separated Tabs: General API vs Audio Endpoints)
          Expanded(
            child: ListenableBuilder(
              listenable: NetworkLogManager.instance,
              builder: (context, _) {
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildLogsList(
                      NetworkLogManager.instance.generalLogs,
                      isAudioTab: false,
                    ),
                    _buildLogsList(
                      NetworkLogManager.instance.audioAndCallLogs,
                      isAudioTab: true,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required IconData icon,
    required String label,
    required int count,
  }) {
    return Tab(
      height: 44,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList(List<NetworkLogItem> sourceLogs, {required bool isAudioTab}) {
    final filtered = _filterLogs(sourceLogs);

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _searchQuery.isNotEmpty
                    ? Icons.search_off_rounded
                    : (isAudioTab ? Icons.audiotrack_outlined : Icons.receipt_long_outlined),
                size: 56,
                color: AppColors.textHint.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isNotEmpty
                    ? 'No logs match "$_searchQuery"'
                    : (isAudioTab
                        ? 'No audio or call log entries yet'
                        : 'No network logs recorded yet'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                _searchQuery.isNotEmpty
                    ? 'Try clearing search or filters.'
                    : (isAudioTab
                        ? 'Audio and call log API requests will appear here.'
                        : 'Network requests made across the app will appear here in real-time.'),
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index];
        return _buildLogCard(item);
      },
    );
  }

  Widget _buildFilterChip(String filterKey, String label) {
    final isSelected = _selectedFilter == filterKey;
    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (val) {
          setState(() {
            _selectedFilter = filterKey;
          });
        },
        backgroundColor: const Color(0xFFF1F5F9),
        selectedColor: AppColors.primary,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          color: isSelected ? Colors.white : AppColors.textSecondary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected ? AppColors.primary : const Color(0xFFE2E8F0),
          ),
        ),
      ),
    );
  }

  Widget _buildLogCard(NetworkLogItem item) {
    final methodColor = _getMethodColor(item.method);
    final statusColor = _getStatusColor(item.statusCode, item.isPending, item.isError);
    final timeStr =
        '${item.requestTime.hour.toString().padLeft(2, '0')}:${item.requestTime.minute.toString().padLeft(2, '0')}:${item.requestTime.second.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: item.isError ? AppColors.primary.withValues(alpha: 0.3) : const Color(0xFFE2E8F0),
          width: item.isError ? 1.5 : 1.0,
        ),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openLogDetails(item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Method Badge, Status Badge, Duration & Time
              Row(
                children: [
                  // Method badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: methodColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.method,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: methodColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.isPending) ...[
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Pending',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                        ] else ...[
                          Icon(
                            item.isError ? Icons.error_outline : Icons.check_circle_outline,
                            size: 13,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.statusCode?.toString() ?? 'ERR',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Duration (if finished)
                  if (item.durationMs != null) ...[
                    Text(
                      '${item.durationMs}ms',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Time
                  Text(
                    timeStr,
                    style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 16, color: AppColors.textHint),
                ],
              ),
              const SizedBox(height: 8),

              // Path / URL
              Text(
                item.path.isEmpty ? item.url : item.path,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              // Query Parameters (if any)
              if (item.queryParameters.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Query: ${item.queryParameters}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Error snippet (if error)
              if (item.isError && item.errorMessage != null) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.errorMessage!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Modal Sheet that displays the complete Request, Response, and cURL details.
class _LogDetailModal extends StatefulWidget {
  final NetworkLogItem item;

  const _LogDetailModal({required this.item});

  @override
  State<_LogDetailModal> createState() => _LogDetailModalState();
}

class _LogDetailModalState extends State<_LogDetailModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _copyToClipboard(String content, String label) {
    Clipboard.setData(ClipboardData(text: content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard!'),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag Handle & Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${item.method} Request #${item.id}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (item.statusCode != null && item.statusCode! < 400)
                                      ? Colors.green.withValues(alpha: 0.12)
                                      : AppColors.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.statusCode?.toString() ?? 'Pending',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: (item.statusCode != null && item.statusCode! < 400)
                                        ? Colors.green
                                        : AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.url,
                            style: const TextStyle(fontSize: 11, color: AppColors.textHint),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tab Bar
          TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'Request'),
              Tab(text: 'Response'),
              Tab(text: 'cURL'),
            ],
          ),

          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRequestTab(item),
                _buildResponseTab(item),
                _buildCurlTab(item),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestTab(NetworkLogItem item) {
    final reqBody = item.getFormattedRequestBody();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard(
          title: 'Request Info',
          rows: [
            {'URL': item.url},
            {'Method': item.method},
            {'Timestamp': item.requestTime.toIso8601String()},
          ],
        ),
        if (item.queryParameters.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildInfoCard(
            title: 'Query Parameters',
            rows: item.queryParameters.entries
                .map((e) => {e.key: e.value.toString()})
                .toList(),
          ),
        ],
        const SizedBox(height: 16),
        _buildSectionHeader('Headers', () => _copyToClipboard(item.requestHeaders.toString(), 'Headers')),
        _buildCodeBlock(item.requestHeaders.toString()),
        const SizedBox(height: 16),
        _buildSectionHeader('Request Payload / Body', () => _copyToClipboard(reqBody, 'Request Body')),
        _buildCodeBlock(reqBody),
      ],
    );
  }

  Widget _buildResponseTab(NetworkLogItem item) {
    final respBody = item.getFormattedResponseBody();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildInfoCard(
          title: 'Response Summary',
          rows: [
            {'Status Code': '${item.statusCode ?? "Pending"}'},
            {'Duration': item.durationMs != null ? '${item.durationMs} ms' : 'In Progress'},
            if (item.responseTime != null)
              {'Received At': item.responseTime!.toIso8601String()},
            if (item.errorMessage != null)
              {'Error': item.errorMessage!},
          ],
        ),
        if (item.responseHeaders != null && item.responseHeaders!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _buildSectionHeader(
            'Response Headers',
            () => _copyToClipboard(item.responseHeaders.toString(), 'Response Headers'),
          ),
          _buildCodeBlock(item.responseHeaders.toString()),
        ],
        const SizedBox(height: 16),
        _buildSectionHeader('Response Body', () => _copyToClipboard(respBody, 'Response Body')),
        _buildCodeBlock(respBody),
      ],
    );
  }

  Widget _buildCurlTab(NetworkLogItem item) {
    final curl = item.toCurl();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Replay Request via cURL',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        const Text(
          'Copy this command to easily test or reproduce this network request in Postman or Terminal.',
          style: TextStyle(fontSize: 12, color: AppColors.textHint),
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: () => _copyToClipboard(curl, 'cURL command'),
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy cURL Command'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        const SizedBox(height: 16),
        _buildCodeBlock(curl),
      ],
    );
  }

  Widget _buildSectionHeader(String title, VoidCallback onCopy) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: AppColors.textPrimary,
          ),
        ),
        TextButton.icon(
          onPressed: onCopy,
          icon: const Icon(Icons.copy, size: 14, color: AppColors.primary),
          label: const Text('Copy', style: TextStyle(fontSize: 12, color: AppColors.primary)),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({required String title, required List<Map<String, String>> rows}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      r.keys.first,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      r.values.first,
                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(String content) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Dark slate terminal bg
        borderRadius: BorderRadius.circular(10),
      ),
      child: SelectableText(
        content.isEmpty ? '(Empty)' : content,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Color(0xFFF1F5F9),
          height: 1.4,
        ),
      ),
    );
  }
}
