/*
 * Purpose: 历史记录页面，展示使用历史的时间线视图
 * Inputs: 会话块数据、时间维度选择
 * Outputs: 按日/月/年维度展示的历史卡片列表
 */

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/session_block.dart';
import '../services/isolate_data_processor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎时间维度枚举
// ═══════════════════════════════════════════════════════════════════════════

enum TimeView { day, month, year }

// ═══════════════════════════════════════════════════════════════════════════
// ▎历史页面主组件
// ═══════════════════════════════════════════════════════════════════════════

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────────────
  // ▎状态变量
  // ─────────────────────────────────────────────────────────────────────────

  TimeView _currentView = TimeView.day;
  bool _isRefreshing = false;
  Timer? _autoRefreshTimer;

  // 动画控制器
  late AnimationController _fadeController;
  late AnimationController _rotationController;

  // 数据
  List<SessionBlock> _sessionBlocks = [];
  Map<String, List<SessionBlock>> _groupedData = {};

  @override
  void initState() {
    super.initState();

    // 初始化动画控制器
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _rotationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );

    // 启动动画
    _fadeController.forward();

    // 初始加载数据
    _loadData();

    // 设置自动刷新
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _rotationController.dispose();
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎数据加载
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    if (_isRefreshing) return;

    setState(() => _isRefreshing = true);
    _rotationController.repeat();

    try {
      // 根据当前视图确定时间范围
      final endTime = DateTime.now().toUtc();
      final startTime = _getStartTimeForView(endTime);

      // 使用 Isolate 加载数据
      final metrics = await IsolateDataProcessor.processInBackground(
        startTime: startTime,
        endTime: endTime,
      );

      if (mounted) {
        setState(() {
          _sessionBlocks = metrics.sessionBlocks;
          _groupData();
          _calculateStatistics();
        });
      }
    } catch (e) {
      debugPrint('加载历史数据失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载数据失败: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
        _rotationController.stop();
        _rotationController.reset();
      }
    }
  }

  DateTime _getStartTimeForView(DateTime endTime) {
    switch (_currentView) {
      case TimeView.day:
        // 日视图：显示所有历史数据
        return DateTime(2020, 1, 1); // 从足够早的日期开始，确保获取所有数据
      case TimeView.month:
        // 月视图：显示最近12个月的数据
        return endTime.subtract(const Duration(days: 365));
      case TimeView.year:
        // 年视图：显示最近5年的数据
        return endTime.subtract(const Duration(days: 365 * 5));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎数据分组和统计
  // ─────────────────────────────────────────────────────────────────────────

  void _groupData() {
    _groupedData.clear();

    for (final block in _sessionBlocks) {
      if (block.isGap || block.perModelStats.isEmpty) continue;

      final key = _getGroupKey(block.startTime);
      if (!_groupedData.containsKey(key)) {
        _groupedData[key] = [];
      }
      _groupedData[key]!.add(block);
    }
  }

  String _getGroupKey(DateTime time) {
    final local = time.toLocal();
    switch (_currentView) {
      case TimeView.day:
        // 按日分组（显示当月每一天）
        return '${local.day}日';
      case TimeView.month:
        // 按月份分组（显示每个月的数据）
        return '${local.year}年${local.month.toString().padLeft(2, '0')}月';
      case TimeView.year:
        // 按年份分组（显示每年的数据）
        return '${local.year}年';
    }
  }

  void _calculateStatistics() {
    // 统计数据现在在各个视图中单独计算
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎自动刷新
  // ─────────────────────────────────────────────────────────────────────────

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted && !_isRefreshing) {
        _loadData();
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎UI构建
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          // 顶部控制栏
          _buildControlBar(),

          // 主体内容
          Expanded(
            child: FadeTransition(
              opacity: _fadeController,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 时间维度切换
          Expanded(
            child: SegmentedButton<TimeView>(
              segments: const [
                ButtonSegment(
                  value: TimeView.day,
                  label: Text('日'),
                  icon: Icon(Icons.today),
                ),
                ButtonSegment(
                  value: TimeView.month,
                  label: Text('月'),
                  icon: Icon(Icons.calendar_month),
                ),
                ButtonSegment(
                  value: TimeView.year,
                  label: Text('年'),
                  icon: Icon(Icons.calendar_today),
                ),
              ],
              selected: {_currentView},
              onSelectionChanged: (Set<TimeView> newSelection) {
                setState(() {
                  _currentView = newSelection.first;
                });
                _loadData();
              },
            ),
          ),

          const SizedBox(width: 16),

          // 刷新按钮
          IconButton.filled(
            icon: RotationTransition(
              turns: _rotationController,
              child: const Icon(Icons.refresh),
            ),
            onPressed: _isRefreshing ? null : _loadData,
            tooltip: '刷新数据',
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_groupedData.isEmpty && !_isRefreshing) {
      return _buildEmptyState();
    }

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        // 历史记录列表
        _buildTabContent(),

        // 底部间距
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无历史记录',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎根据视图构建不同内容
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTabContent() {
    switch (_currentView) {
      case TimeView.day:
        return _buildDayView();
      case TimeView.month:
        return _buildMonthView();
      case TimeView.year:
        return _buildYearView();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎日视图 - 月历展示
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDayView() {
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    // 找出数据中最早的日期
    DateTime? earliestDate;
    for (final block in _sessionBlocks) {
      if (!block.isGap) {
        final blockDate = block.startTime.toLocal();
        if (earliestDate == null || blockDate.isBefore(earliestDate)) {
          earliestDate = blockDate;
        }
      }
    }

    // 如果没有数据，默认显示最近30天
    final startDate = earliestDate != null
        ? DateTime(earliestDate.year, earliestDate.month, earliestDate.day)
        : endDate.subtract(const Duration(days: 30));

    // 按日期组织数据（使用完整日期作为key）
    Map<String, List<SessionBlock>> dayData = {};
    Map<String, double> dayCost = {};
    Map<String, int> dayTokens = {};
    double totalCost = 0;
    int totalTokens = 0;
    double maxDayCost = 0; // 记录最高单日消费

    for (final block in _sessionBlocks) {
      if (block.isGap) continue;
      final blockDate = block.startTime.toLocal();
      final dateKey =
          '${blockDate.year}-${blockDate.month.toString().padLeft(2, '0')}-${blockDate.day.toString().padLeft(2, '0')}';

      dayData.putIfAbsent(dateKey, () => []).add(block);
      dayCost[dateKey] = (dayCost[dateKey] ?? 0) + block.costUsd;
      dayTokens[dateKey] =
          (dayTokens[dateKey] ?? 0) + block.tokenCounts.usageTokens;

      totalCost += block.costUsd;
      totalTokens += block.tokenCounts.usageTokens;
    }

    // 计算最高单日消费
    for (final cost in dayCost.values) {
      if (cost > maxDayCost) maxDayCost = cost;
    }

    // 生成日期列表（从今天开始往前到最早的数据日期）
    List<DateTime> dates = [];
    DateTime currentDate = endDate;
    while (currentDate.isAfter(startDate) ||
        currentDate.isAtSameMomentAs(startDate)) {
      dates.add(currentDate);
      currentDate = currentDate.subtract(const Duration(days: 1));
    }

    // 为折线图准备数据（最近30天）
    final chartDates = dates.take(30).toList().reversed.toList();
    final chartData = <double>[];
    double maxChartValue = 0;

    for (final date in chartDates) {
      final dateKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final cost = dayCost[dateKey] ?? 0;
      chartData.add(cost);
      if (cost > maxChartValue) maxChartValue = cost;
    }

    final weekDays = ['一', '二', '三', '四', '五', '六', '日'];

    // 计算需要在前面添加的空格数，让今天对齐到正确的星期列
    // weekday: 1=周一, 7=周日
    final todayWeekday = now.weekday;
    final emptySlots = todayWeekday - 1; // 周一是0个空格，周日是6个空格

    // 创建包含空格和日期的完整列表
    List<DateTime?> gridItems = [];
    // 添加空格
    for (int i = 0; i < emptySlots; i++) {
      gridItems.add(null);
    }
    // 添加日期
    gridItems.addAll(dates);

    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 统计卡片和折线图
            _buildDayViewHeader(
                totalCost, totalTokens, chartData, maxChartValue),
            const SizedBox(height: 20),

            // 分割线
            Divider(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              thickness: 1,
            ),
            const SizedBox(height: 16),

            // 星期标签
            Row(
              children: weekDays
                  .map(
                    (day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),

            // 日期网格
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 0.85,
              ),
              itemCount: gridItems.length,
              itemBuilder: (context, index) {
                final date = gridItems[index];
                if (date == null) {
                  return const SizedBox(); // 空格
                }

                final dateKey =
                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                final hasData = dayData.containsKey(dateKey);
                final cost = dayCost[dateKey] ?? 0;
                final tokens = dayTokens[dateKey] ?? 0;

                return _buildDayCard(date, hasData, cost, tokens, maxDayCost);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCard(
      DateTime date, bool hasData, double cost, int tokens, double maxDayCost) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    // 计算颜色强度（基于消费金额相对于最高日消费的比例）
    final intensity =
        hasData && maxDayCost > 0 ? (cost / maxDayCost).clamp(0.0, 1.0) : 0.0;
    final cardColor = hasData
        ? colorScheme.primary.withValues(alpha: 0.1 + intensity * 0.5)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.2);

    return Card(
      elevation: 0,
      color: cardColor,
      child: InkWell(
        onTap: hasData
            ? () {
                // 可以在这里显示当天详情
              }
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isToday
                  ? colorScheme.primary.withValues(alpha: 0.8)
                  : hasData
                      ? colorScheme.primary
                          .withValues(alpha: 0.2 + intensity * 0.3)
                      : colorScheme.outline.withValues(alpha: 0.1),
              width: isToday ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 月日
              Text(
                '${date.month}/${date.day}',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: isToday ? FontWeight.bold : FontWeight.w600,
                  color: hasData
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              if (hasData) ...[
                const SizedBox(height: 6),
                Text(
                  _formatCompactTokens(tokens),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '\$${cost.toStringAsFixed(2)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎日视图头部 - 统计和折线图
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDayViewHeader(double totalCost, int totalTokens,
      List<double> chartData, double maxValue) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题和统计
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '近30天趋势',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '总消费: \$${totalCost.toStringAsFixed(2)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_formatCompactTokens(totalTokens)} tokens',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 折线图
            SizedBox(
              height: 120,
              child: _buildMiniLineChart(chartData, maxValue),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniLineChart(List<double> data, double maxValue) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (data.isEmpty || maxValue == 0) {
      return Center(
        child: Text(
          '暂无数据',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    return CustomPaint(
      size: const Size(double.infinity, 120),
      painter: SimpleLineChartPainter(
        data: data,
        maxValue: maxValue,
        lineColor: colorScheme.primary,
        fillColor: colorScheme.primary.withValues(alpha: 0.1),
        gridColor: colorScheme.outline.withValues(alpha: 0.1),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎月视图 - 月份卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMonthView() {
    // 按月份组织数据
    Map<String, List<SessionBlock>> monthData = {};
    for (final block in _sessionBlocks) {
      if (block.isGap) continue;
      final key = _getGroupKey(block.startTime);
      monthData.putIfAbsent(key, () => []).add(block);
    }

    final sortedMonths = monthData.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // 最新月份在前

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= sortedMonths.length) return null;
          final monthKey = sortedMonths[index];
          final blocks = monthData[monthKey]!;
          return _buildMonthCard(monthKey, blocks);
        },
        childCount: sortedMonths.length,
      ),
    );
  }

  Widget _buildMonthCard(String monthKey, List<SessionBlock> blocks) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 解析月份信息
    final yearMonth = monthKey.replaceAll('年', '-').replaceAll('月', '');
    final parts = yearMonth.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);

    // 计算月度统计
    double monthCost = 0;
    int monthTokens = 0;
    int monthMessages = 0;
    Map<String, int> modelUsage = {};
    Map<int, double> dailyCost = {};
    Set<int> activeDays = {};

    for (final block in blocks) {
      final blockTime = block.startTime.toLocal();
      // 只统计属于当前月份的数据
      if (blockTime.year == year && blockTime.month == month) {
        monthCost += block.costUsd;
        monthTokens += block.tokenCounts.usageTokens;
        monthMessages += block.sentMessagesCount;

        final day = blockTime.day;
        activeDays.add(day);
        dailyCost[day] = (dailyCost[day] ?? 0) + block.costUsd;

        for (final model in block.perModelStats.keys) {
          modelUsage[model] = (modelUsage[model] ?? 0) + 1;
        }
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              // 月份标题栏
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primaryContainer.withValues(alpha: 0.25),
                      colorScheme.secondaryContainer.withValues(alpha: 0.25),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_month,
                          color: colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          monthKey,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${activeDays.length} 天活跃',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 统计信息
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 主要指标
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMonthStatItem(
                          icon: Icons.attach_money,
                          label: '月度金额',
                          value: '\$${monthCost.toStringAsFixed(2)}',
                          color: Colors.green,
                        ),
                        _buildMonthStatItem(
                          icon: Icons.token,
                          label: '总Token',
                          value: _formatTokenCount(monthTokens),
                          color: Colors.blue,
                        ),
                        _buildMonthStatItem(
                          icon: Icons.message,
                          label: '总消息',
                          value: monthMessages.toString(),
                          color: Colors.orange,
                        ),
                      ],
                    ),

                    // 月度日历热力图
                    const SizedBox(height: 20),
                    _buildMonthCalendarHeatmap(year, month, dailyCost),

                    // 模型使用统计
                    if (modelUsage.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '模型使用分布',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...modelUsage.entries.map((entry) {
                            final percentage =
                                (entry.value / blocks.length * 100);
                            return _buildModelUsageBar(
                              entry.key,
                              percentage,
                              entry.value,
                            );
                          }),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建月度日历热力图
  Widget _buildMonthCalendarHeatmap(
      int year, int month, Map<int, double> dailyCost) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final daysInMonth = DateTime(year, month + 1, 0).day;

    // 找出最大成本用于颜色映射
    double maxCost = 0;
    for (final cost in dailyCost.values) {
      if (cost > maxCost) maxCost = cost;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '日度活跃度',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),

        // 日历网格 - 与年度统计中的月份格子大小一致
        Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: WrapAlignment.start,
          children: List.generate(daysInMonth, (index) {
            final day = index + 1; // 从1号开始
            final cost = dailyCost[day] ?? 0;
            final intensity = maxCost > 0 ? cost / maxCost : 0;

            return Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: cost > 0
                    ? colorScheme.primary
                        .withValues(alpha: 0.15 + intensity * 0.65)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: cost > 0
                      ? colorScheme.primary.withValues(alpha: 0.3)
                      : colorScheme.outline.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  day.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: cost > 0
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    fontWeight: cost > 0 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildMonthStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎年视图 - 年度卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildYearView() {
    // 按年份组织数据
    Map<String, List<SessionBlock>> yearData = {};
    for (final block in _sessionBlocks) {
      if (block.isGap) continue;
      final key = _getGroupKey(block.startTime);
      yearData.putIfAbsent(key, () => []).add(block);
    }

    final sortedYears = yearData.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // 最新年份在前

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= sortedYears.length) return null;
          final yearKey = sortedYears[index];
          final blocks = yearData[yearKey]!;
          return _buildYearCard(yearKey, blocks);
        },
        childCount: sortedYears.length,
      ),
    );
  }

  Widget _buildYearCard(String yearKey, List<SessionBlock> blocks) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 计算年度统计
    double yearCost = 0;
    int yearTokens = 0;
    int yearMessages = 0;
    Set<String> activeMonths = {};
    Map<String, int> modelUsage = {};

    for (final block in blocks) {
      yearCost += block.costUsd;
      yearTokens += block.tokenCounts.usageTokens;
      yearMessages += block.sentMessagesCount;

      final monthKey = '${block.startTime.month}月';
      activeMonths.add(monthKey);

      for (final model in block.perModelStats.keys) {
        modelUsage[model] = (modelUsage[model] ?? 0) + 1;
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              // 年份标题栏
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorScheme.primaryContainer.withValues(alpha: 0.3),
                      colorScheme.secondaryContainer.withValues(alpha: 0.3),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          yearKey,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${activeMonths.length} 个月活跃',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 年度统计
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // 主要指标
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildYearStatItem(
                          icon: Icons.attach_money,
                          label: '年度金额',
                          value: '\$${yearCost.toStringAsFixed(2)}',
                          color: Colors.green,
                        ),
                        _buildYearStatItem(
                          icon: Icons.token,
                          label: '总Token',
                          value: _formatTokenCount(yearTokens),
                          color: Colors.blue,
                        ),
                        _buildYearStatItem(
                          icon: Icons.message,
                          label: '总消息',
                          value: yearMessages.toString(),
                          color: Colors.orange,
                        ),
                      ],
                    ),

                    // 月度活跃情况
                    const SizedBox(height: 20),
                    _buildMonthActivityIndicator(activeMonths),

                    // 模型使用统计
                    if (modelUsage.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '模型使用分布',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...modelUsage.entries.map((entry) {
                            final percentage =
                                (entry.value / blocks.length * 100);
                            return _buildModelUsageBar(
                              entry.key,
                              percentage,
                              entry.value,
                            );
                          }),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildYearStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildMonthActivityIndicator(Set<String> activeMonths) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final allMonths = [
      '1月',
      '2月',
      '3月',
      '4月',
      '5月',
      '6月',
      '7月',
      '8月',
      '9月',
      '10月',
      '11月',
      '12月'
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '月度活跃度',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: allMonths.map((month) {
            final isActive = activeMonths.contains(month);
            return Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isActive
                    ? colorScheme.primary.withValues(alpha: 0.3)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive
                      ? colorScheme.primary
                      : colorScheme.outline.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  month.substring(0, month.length - 1),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: isActive
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildModelUsageBar(String model, double percentage, int count) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _getModelColor(model);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              model,
              style: theme.textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Stack(
              children: [
                Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: percentage / 100,
                  child: Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${percentage.toStringAsFixed(1)}%',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // 格式化紧凑的Token显示
  String _formatCompactTokens(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(1)}M';
    } else if (tokens >= 1000) {
      return '${(tokens / 1000).toStringAsFixed(1)}K';
    }
    return tokens.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎工具方法
  // ─────────────────────────────────────────────────────────────────────────

  String _formatTokenCount(int tokens) {
    final formatter = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final tokenString = tokens.toString();
    return tokenString.replaceAllMapped(formatter, (Match m) => '${m[1]},');
  }

  Color _getModelColor(String model) {
    final modelLower = model.toLowerCase();
    if (modelLower.contains('opus')) return Colors.purple;
    if (modelLower.contains('sonnet')) return Colors.blue;
    if (modelLower.contains('haiku')) return Colors.green;
    return Colors.grey;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎简单折线图绘制器
// ═══════════════════════════════════════════════════════════════════════════

class SimpleLineChartPainter extends CustomPainter {
  final List<double> data;
  final double maxValue;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  SimpleLineChartPainter({
    required this.data,
    required this.maxValue,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // 绘制网格线
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // 计算点的位置
    final points = <Offset>[];
    final stepX = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedValue = maxValue > 0 ? data[i] / maxValue : 0;
      final y = size.height - (normalizedValue * size.height * 0.9); // 留10%边距
      points.add(Offset(x, y));
    }

    // 绘制填充区域
    final fillPath = Path();
    fillPath.moveTo(0, size.height);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    canvas.drawPath(fillPath, fillPaint);

    // 绘制折线
    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(path, paint);

    // 绘制点
    final pointPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;

    for (final point in points) {
      canvas.drawCircle(point, 3, pointPaint);
    }
  }

  @override
  bool shouldRepaint(SimpleLineChartPainter oldDelegate) {
    return oldDelegate.data != data || oldDelegate.maxValue != maxValue;
  }
}
