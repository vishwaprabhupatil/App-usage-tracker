import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../supabase_config.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class UsageAnalysisScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const UsageAnalysisScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<UsageAnalysisScreen> createState() => _UsageAnalysisScreenState();
}

class _UsageAnalysisScreenState extends State<UsageAnalysisScreen> {
  String _selectedView = 'Monthly';
  late final ScrollController _chartScrollController;
  
  Map<String, Uint8List?> _appIcons = {};
  
  @override
  void initState() {
    super.initState();
    _chartScrollController = ScrollController();
    _loadAppIcons();
  }

  @override
  void dispose() {
    _chartScrollController.dispose();
    super.dispose();
  }
  
  Future<void> _loadAppIcons() async {
    try {
      final screentimeDoc = await SupabaseConfig.client
          .from('screentime')
          .select('apps')
          .eq('id', widget.childId)
          .maybeSingle();

      final childDoc = await SupabaseConfig.client
          .from('children')
          .select('installed_apps')
          .eq('id', widget.childId)
          .maybeSingle();
          
      final Map<String, Uint8List?> icons = {};

      if (screentimeDoc != null) {
        final apps = (screentimeDoc['apps'] as List<dynamic>?) ?? [];

        for (final app in apps) {
          if (app is! Map<String, dynamic>) continue;
          final packageName = app['packageName']?.toString();
          final iconBase64 = app['icon']?.toString();
          if (packageName == null || packageName.isEmpty) continue;
          if (iconBase64 != null && iconBase64.isNotEmpty) {
            try {
              icons[packageName] = base64Decode(iconBase64);
            } catch (_) {
              // Ignore decoding errors.
            }
          }
        }
      }

      // Merge installed-app icons without overwriting existing usage icons.
      if (childDoc != null) {
        final installedApps = (childDoc['installed_apps'] as List<dynamic>?) ?? [];
        for (final app in installedApps) {
          if (app is! Map<String, dynamic>) continue;
          final packageName = app['packageName']?.toString();
          final iconBase64 = app['icon_base64']?.toString();
          if (packageName == null || packageName.isEmpty) continue;
          if (icons.containsKey(packageName) && icons[packageName] != null) continue;
          if (iconBase64 != null && iconBase64.isNotEmpty) {
            try {
              icons[packageName] = base64Decode(iconBase64);
            } catch (_) {
              // Ignore decoding errors.
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _appIcons = icons;
        });
      }
    } catch (e) {
      debugPrint('Error loading icons: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.childName} Analysis'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                _buildTab('Weekly'),
                const SizedBox(width: 12),
                _buildTab('Monthly'),
              ],
            ),
          ),
        ),
      ),
      body: _buildBody(),
    );
  }
  
  Widget _buildTab(String title) {
    final bool isSelected = _selectedView == title;
    return InkWell(
      onTap: () {
        setState(() => _selectedView = title);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isSelected 
              ? null 
              : Border.all(color: Theme.of(context).colorScheme.outline),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Theme.of(context).colorScheme.onPrimary : null,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final bool isMonthly = _selectedView == 'Monthly';
    final int limit = isMonthly ? 35 : 7;

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: SupabaseConfig.client
          .from('daily_usage')
          .stream(primaryKey: ['id'])
          .eq('child_id', widget.childId)
          .order('date', ascending: false)
          .limit(limit),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bar_chart, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No historical data yet',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Text(
                  'Data will appear here after the first sync.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final docs = snapshot.data ?? [];
        final Map<String, Map<String, dynamic>> usageByDate = {};
        for (final doc in docs) {
          final dateStr = doc['date']?.toString();
          if (dateStr != null) {
            usageByDate[dateStr] = doc;
          }
        }
        
        final List<_DailyData> chartData = [];
        final Map<String, int> aggregateApps = {};
        final Map<String, int> aggregateOpens = {};
        final Map<String, String> appNames = {};
        
        int maxMinutes = 0;
        int sumMinutes = 0;
        final now = DateTime.now();

        if (isMonthly) {
          // Generate entries for all dates of the month (1st to 31st / end of month)
          final year = now.year;
          final month = now.month;
          final daysInMonth = DateTime(year, month + 1, 0).day;
          
          for (int day = 1; day <= daysInMonth; day++) {
            final dateObj = DateTime(year, month, day);
            final dateStr = DateFormat('yyyy-MM-dd').format(dateObj);
            final doc = usageByDate[dateStr];
            final int minutes = doc != null ? (doc['total_minutes'] ?? 0) : 0;
            
            if (minutes > maxMinutes) maxMinutes = minutes;
            sumMinutes += minutes;
            
            chartData.add(_DailyData(dateObj, minutes));
            
            if (doc != null) {
              final apps = (doc['apps'] as List<dynamic>?) ?? [];
              for (final app in apps) {
                if (app is Map<String, dynamic>) {
                  final String pkg = app['packageName'] ?? '';
                  final String name = app['appName'] ?? 'Unknown';
                  final int appMins = app['minutes'] ?? 0;
                  final int appOpenCount = (app['openCount'] as num?)?.toInt() ?? 0;
                  
                  if (pkg.isNotEmpty && appMins > 0) {
                    aggregateApps[pkg] = (aggregateApps[pkg] ?? 0) + appMins;
                    aggregateOpens[pkg] = (aggregateOpens[pkg] ?? 0) + appOpenCount;
                    appNames[pkg] = name;
                  }
                }
              }
            }
          }
        } else {
          // Past 7 days up to today
          for (int i = 6; i >= 0; i--) {
            final dateObj = DateTime(now.year, now.month, now.day - i);
            final dateStr = DateFormat('yyyy-MM-dd').format(dateObj);
            final doc = usageByDate[dateStr];
            final int minutes = doc != null ? (doc['total_minutes'] ?? 0) : 0;
            
            if (minutes > maxMinutes) maxMinutes = minutes;
            sumMinutes += minutes;
            
            chartData.add(_DailyData(dateObj, minutes));
            
            if (doc != null) {
              final apps = (doc['apps'] as List<dynamic>?) ?? [];
              for (final app in apps) {
                if (app is Map<String, dynamic>) {
                  final String pkg = app['packageName'] ?? '';
                  final String name = app['appName'] ?? 'Unknown';
                  final int appMins = app['minutes'] ?? 0;
                  final int appOpenCount = (app['openCount'] as num?)?.toInt() ?? 0;
                  
                  if (pkg.isNotEmpty && appMins > 0) {
                    aggregateApps[pkg] = (aggregateApps[pkg] ?? 0) + appMins;
                    aggregateOpens[pkg] = (aggregateOpens[pkg] ?? 0) + appOpenCount;
                    appNames[pkg] = name;
                  }
                }
              }
            }
          }
        }
        
        // Sort aggregate apps by time
        final List<MapEntry<String, int>> sortedApps = aggregateApps.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
          
        final avgMinutes = chartData.isEmpty ? 0 : sumMinutes ~/ chartData.length;

        // Auto scroll to today (right side) on load
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_chartScrollController.hasClients) {
            _chartScrollController.jumpTo(_chartScrollController.position.maxScrollExtent);
          }
        });

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Banner
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.tertiary,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Average',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.8),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatMinutes(avgMinutes),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.insights,
                      size: 48,
                      color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),

              // Chart section header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isMonthly
                          ? 'Screen Time (Past 30 Days)'
                          : 'Screen Time (Past 7 Days)',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (isMonthly)
                      Row(
                        children: [
                          Icon(Icons.swipe, size: 16, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                          Text(
                            '1st - 31st',
                            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Scrollable Chart
              SizedBox(
                height: 250,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16.0, left: 8.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const double itemWidth = 44.0;
                      final double totalWidth = isMonthly 
                          ? math.max(constraints.maxWidth, chartData.length * itemWidth)
                          : constraints.maxWidth;
                          
                      return SingleChildScrollView(
                        controller: _chartScrollController,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: SizedBox(
                          width: totalWidth,
                          child: _buildChart(chartData, maxMinutes, isMonthly: isMonthly),
                        ),
                      );
                    },
                  ),
                ),
              ),
              
              // Date Quick-Scroller Strip below dates (1 to 31st)
              if (isMonthly) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Scroll Dates (1 to 31st)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        'Tap date to jump',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: chartData.length,
                    itemBuilder: (context, index) {
                      final date = chartData[index].date;
                      final dayNum = date.day;
                      final isToday = dayNum == DateTime.now().day && 
                                      date.month == DateTime.now().month &&
                                      date.year == DateTime.now().year;
                      
                      return GestureDetector(
                        onTap: () {
                          if (_chartScrollController.hasClients) {
                            const double itemWidth = 44.0;
                            final double targetScroll = (index * itemWidth).clamp(
                              0.0,
                              _chartScrollController.position.maxScrollExtent,
                            );
                            _chartScrollController.animateTo(
                              targetScroll,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isToday 
                                ? Theme.of(context).colorScheme.primary 
                                : Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              isToday ? 'Today' : '$dayNum',
                              style: TextStyle(
                                color: isToday 
                                    ? Colors.white 
                                    : Theme.of(context).colorScheme.onSurface,
                                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              
              const SizedBox(height: 24),

              // Apps Breakdown
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Top Apps',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 8),
              if (sortedApps.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('No app usage recorded')),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sortedApps.length > 10 ? 10 : sortedApps.length,
                  itemBuilder: (context, index) {
                    final entry = sortedApps[index];
                    final String pkg = entry.key;
                    final int totalMins = entry.value;
                    final int totalOpens = aggregateOpens[pkg] ?? 0;
                    final String name = appNames[pkg] ?? pkg;
                    
                    final double percentage = sumMinutes > 0 ? (totalMins / sumMinutes) * 100 : 0;
                    
                    return _buildAppRow(
                      name,
                      pkg,
                      totalMins,
                      totalOpens,
                      percentage,
                    );
                  },
                ),
                
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChart(List<_DailyData> data, int maxVal, {required bool isMonthly}) {
    if (maxVal == 0) maxVal = 60; // Default max 1 hour if no data
    
    // Add 20% headroom to max value
    final double maxY = maxVal * 1.2;

    return BarChart(
      BarChartData(
        alignment: isMonthly ? BarChartAlignment.spaceAround : BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            tooltipPadding: const EdgeInsets.all(8),
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                _formatMinutes(rod.toY.toInt()),
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final int index = value.toInt();
                if (index < 0 || index >= data.length) return const SizedBox.shrink();
                
                final DateTime date = data[index].date;
                final bool isToday = date.day == DateTime.now().day && 
                                date.month == DateTime.now().month &&
                                date.year == DateTime.now().year;
                
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    isToday
                        ? 'Today'
                        : (isMonthly
                            ? DateFormat('d').format(date)
                            : DateFormat('E').format(date)),
                    style: TextStyle(
                      color: isToday 
                          ? Theme.of(context).colorScheme.primary 
                          : Colors.grey[600],
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                );
              },
              reservedSize: 32,
              interval: 1,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                
                if (value % 60 == 0) { // Every hour
                  return Text(
                    '${value ~/ 60}h',
                    style: const TextStyle(color: Colors.grey, fontSize: 10),
                  );
                } 
                return const SizedBox.shrink();
              },
              reservedSize: 32,
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 60, // Grid every 1 hour
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.withValues(alpha: 0.2),
              strokeWidth: 1,
            );
          },
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(data.length, (index) {
          final isToday = data[index].date.day == DateTime.now().day && 
                          data[index].date.month == DateTime.now().month &&
                          data[index].date.year == DateTime.now().year;
                          
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: data[index].minutes.toDouble(),
                color: isToday 
                    ? Theme.of(context).colorScheme.primary 
                    : Theme.of(context).colorScheme.secondary.withValues(alpha: 0.6),
                width: isMonthly ? 14 : 20,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildAppRow(
    String name,
    String packageName,
    int minutes,
    int openCount,
    double percentage,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildAppIcon(name, packageName),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: Colors.grey[200],
                          color: Theme.of(context).colorScheme.primary,
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const Expanded(flex: 1, child: SizedBox()),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  openCount == 1 ? 'Opened 1 time' : 'Opened $openCount times',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatMinutes(minutes),
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAppIcon(String appName, String packageName) {
    if (_appIcons.containsKey(packageName) && _appIcons[packageName] != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _appIcons[packageName]!,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildFallbackIcon(appName),
        ),
      );
    }
    
    return _buildFallbackIcon(appName);
  }

  Widget _buildFallbackIcon(String appName) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          appName.isNotEmpty ? appName[0].toUpperCase() : '?',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
        ),
      ),
    );
  }

  String _formatMinutes(int totalMinutes) {
    if (totalMinutes < 60) return '${totalMinutes}m';
    final int hours = totalMinutes ~/ 60;
    final int minutes = totalMinutes % 60;
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }
}

class _DailyData {
  final DateTime date;
  final int minutes;
  
  _DailyData(this.date, this.minutes);
}
