/*
 * Purpose: 可复用的今日消耗组件，支持紧凑和完整两种显示模式
 * Inputs: sessionBlocks数据、compact模式标志、maxHourGroups限制
 * Outputs: 响应式今日消耗时间线UI，根据模式自适应显示
 */

import 'package:flutter/material.dart';

import '../models/session_block.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎今日消耗组件 - 支持紧凑/完整两种模式
// ═══════════════════════════════════════════════════════════════════════════

class TodayActivityWidget extends StatelessWidget {
  final List<SessionBlock> sessionBlocks; // 会话数据块列表
  final bool compact; // 紧凑模式标志：true-托盘显示（精简信息），false-主窗口显示（完整信息）
  final int maxHourGroups; // 紧凑模式限制：最多显示N个时段，避免托盘UI过长

  const TodayActivityWidget({
    super.key,
    required this.sessionBlocks,
    this.compact = false,
    this.maxHourGroups = 3,
  });

  // ─────────────────────────────────────────────────────────────────────────
  // ▎工具函数
  // ─────────────────────────────────────────────────────────────────────────

  // Token格式化函数 - 添加千位分隔符
  // 例：1000000 -> "1,000,000"
  String _formatTokenCount(int tokens) {
    final formatter = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'); // 匹配每3位数字
    final tokenString = tokens.toString();
    return tokenString.replaceAllMapped(formatter, (Match m) => '${m[1]},');
  }

  // 获取模型颜色 - 根据模型名称返回对应主题色
  // Opus(紫色) > Sonnet(蓝色) > Haiku(绿色) > 其他(灰色)
  Color _getModelColor(String model) {
    final modelLower = model.toLowerCase();
    if (modelLower.contains('opus')) return Colors.purple; // 高端模型
    if (modelLower.contains('sonnet')) return Colors.blue; // 中端模型
    if (modelLower.contains('haiku')) return Colors.green; // 轻量模型
    return Colors.grey; // 未知模型
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎计算今日总计
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _calculateTodayTotal(List<SessionBlock> blocks) {
    double totalCost = 0.0;
    int totalTokens = 0;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day); // 今天00:00:00
    final todayEnd = todayStart.add(const Duration(days: 1)); // 明天00:00:00

    // 遍历所有会话块，累计今日的消耗
    for (final block in blocks) {
      // 过滤条件：非空隙块 && 有模型统计数据
      if (!block.isGap && block.perModelStats.isNotEmpty) {
        final localTime = block.startTime.toLocal(); // 转换为本地时间
        // 时间范围检查：在今天内
        if (localTime.isAfter(todayStart) && localTime.isBefore(todayEnd)) {
          totalCost += block.costUsd;
          totalTokens += block.tokenCounts.usageTokens;
        }
      }
    }

    return {
      'cost': totalCost,
      'tokens': totalTokens,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎构建今日总计显示
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTodayTotal(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final totals = _calculateTodayTotal(sessionBlocks);

    final tokens = totals['tokens'] as int;
    final cost = totals['cost'] as double;

    final textStyle =
        compact ? theme.textTheme.labelSmall : theme.textTheme.bodySmall;

    // UI渲染策略：
    // - 紧凑模式（托盘）：仅显示关键金额，节省空间
    // - 完整模式（主窗）：显示token + 金额，带装饰边框
    if (compact) {
      // 紧凑模式：纯文字显示
      return RichText(
        text: TextSpan(
          style: textStyle,
          children: [
            TextSpan(
              text: '总消耗: ',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
            TextSpan(
              text: '\$${cost.toStringAsFixed(4)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    } else {
      // 完整模式：带边框的标签
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: RichText(
          text: TextSpan(
            style: textStyle,
            children: [
              TextSpan(
                text: '总计: ',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
              TextSpan(
                text: _formatTokenCount(tokens),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              TextSpan(
                text: ' tokens',
                style: TextStyle(
                  color: colorScheme.primary.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
              TextSpan(
                text: ' • ',
                style: TextStyle(
                  color: colorScheme.outline.withValues(alpha: 0.5),
                ),
              ),
              TextSpan(
                text: '\$',
                style: TextStyle(
                  color: Colors.green.shade600,
                  fontSize: 12,
                ),
              ),
              TextSpan(
                text: cost.toStringAsFixed(4),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎构建小时分组卡片
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHourlyGroup(
    BuildContext context, {
    required Map<String, dynamic> activity,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final hour = activity['hour'] as String;
    final hourTotalCost = activity['hourTotalCost'] as double;
    final blocks = activity['blocks'] as List<SessionBlock>;

    // 紧凑模式下的调整 - 移除水平margin让内容与标题对齐
    final margin = compact
        ? const EdgeInsets.only(top: 4, bottom: 4)
        : const EdgeInsets.symmetric(horizontal: 0, vertical: 8);

    final titlePadding = compact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 12);

    return Container(
      margin: margin,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(compact ? 8 : 12),
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // 组标题
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            Container(
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
                  : titlePadding,
              decoration: BoxDecoration(
                color:
                    colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(compact ? 8 : 12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    hour,
                    style: (compact
                            ? theme.textTheme.labelMedium
                            : theme.textTheme.titleSmall)
                        ?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '\$${hourTotalCost.toStringAsFixed(4)}',
                    style: compact
                        ? theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade700,
                          )
                        : theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.green,
                          ),
                  ),
                ],
              ),
            ),

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // 时间段详情
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            if (!compact)
              ...blocks.map((block) => _buildBlockItem(context, block))
            else
              // 紧凑模式只显示汇总信息
              _buildCompactSummary(context, blocks),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎构建紧凑模式汇总
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCompactSummary(BuildContext context, List<SessionBlock> blocks) {
    final theme = Theme.of(context);

    // 汇总各模型的使用情况
    final modelTotals = <String, double>{}; // 键：模型名，值：累计成本

    for (final block in blocks) {
      for (final entry in block.perModelStats.entries) {
        final model = entry.key;
        final stats = entry.value;
        modelTotals[model] = (modelTotals[model] ?? 0) + stats.costUsd;
      }
    }

    // 按成本排序 - 高消费模型优先显示
    final sortedModels = modelTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)); // 降序排列

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        children: sortedModels.map((entry) {
          final model = entry.key;
          final cost = entry.value;
          final color = _getModelColor(model);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                // 模型标签
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    model,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),
                // 该模型的价格
                Text(
                  '\$${cost.toStringAsFixed(4)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎构建块条目（完整模式）
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBlockItem(BuildContext context, SessionBlock block) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final modelStats = block.perModelStats;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: modelStats.entries.map((entry) {
          final modelName = entry.key;
          final stats = entry.value;
          final modelCost = stats.costUsd;
          final color = _getModelColor(modelName);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // 模型tag样式
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    modelName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Spacer(),

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // 模型消费金额
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                Text(
                  '\$${modelCost.toStringAsFixed(4)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎主构建方法
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 过滤今日数据并按小时分组
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day); // 今天00:00:00
    final todayEnd = todayStart.add(const Duration(days: 1)); // 明天00:00:00

    final hourlyGroups = <String, List<SessionBlock>>{};

    // 数据分组策略：按小时聚合会话块
    for (final block in sessionBlocks) {
      if (!block.isGap && block.perModelStats.isNotEmpty) {
        final localTime = block.startTime.toLocal();

        // 只保留今日的数据
        if (localTime.isAfter(todayStart) && localTime.isBefore(todayEnd)) {
          // 生成小时键值，如："09:00", "14:00"
          final hourKey = '${localTime.hour.toString().padLeft(2, '0')}:00';

          if (!hourlyGroups.containsKey(hourKey)) {
            hourlyGroups[hourKey] = [];
          }
          hourlyGroups[hourKey]!.add(block);
        }
      }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 生成今日消耗数据结构
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    final todayActivities = <Map<String, dynamic>>[];

    // 按小时排序（倒序，最新的在前）- 用户更关心最近的活动
    final sortedHours = hourlyGroups.entries.toList()
      ..sort((a, b) {
        final timeA = a.value.first.startTime;
        final timeB = b.value.first.startTime;
        return timeB.compareTo(timeA);
      });

    for (final entry in sortedHours) {
      final hourKey = entry.key;
      final blocks = entry.value;

      // 计算该时段总计
      double hourTotalCost = 0.0;
      int hourTotalTokens = 0;

      for (final block in blocks) {
        hourTotalCost += block.costUsd;
        hourTotalTokens += block.tokenCounts.usageTokens;
      }

      // 按时间排序会话块
      blocks.sort((a, b) => b.startTime.compareTo(a.startTime));

      todayActivities.add({
        'hour': hourKey,
        'hourTotalCost': hourTotalCost,
        'hourTotalTokens': hourTotalTokens,
        'blocks': blocks,
      });
    }

    // 显示策略：紧凑模式只显示最近N个时段，避免托盘UI过长
    final displayActivities = compact && todayActivities.length > maxHourGroups
        ? todayActivities.take(maxHourGroups).toList() // 截取前N个
        : todayActivities; // 完整显示

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // 根据模式调整容器样式
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    final containerMargin =
        compact ? const EdgeInsets.all(0) : const EdgeInsets.all(12);
    final containerPadding =
        compact ? const EdgeInsets.all(12) : const EdgeInsets.all(16);

    return Container(
      margin: containerMargin,
      child: Card(
        elevation: 0,
        color: compact
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 12 : 16),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          padding: containerPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              // 标题行
              // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              Padding(
                padding: compact
                    ? EdgeInsets.zero // 紧凑模式不需要额外padding
                    : EdgeInsets.zero,
                child: Row(
                  children: [
                    Icon(
                      Icons.timeline,
                      color: colorScheme.primary,
                      size: compact ? 16 : 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '今日消耗',
                      style: compact
                          ? theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            )
                          : theme.textTheme.titleMedium,
                    ),
                    const Spacer(),
                    // 今日总计 - 紧凑模式只显示价格，完整模式显示全部
                    _buildTodayTotal(context),
                  ],
                ),
              ),
              SizedBox(height: compact ? 8 : 12),

              // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              // 活动内容
              // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              if (displayActivities.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: compact ? 8 : 16),
                    child: Text(
                      '暂无今日消耗',
                      style: (compact
                              ? theme.textTheme.labelMedium
                              : theme.textTheme.bodySmall)
                          ?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              else ...[
                ...displayActivities.map((activity) => _buildHourlyGroup(
                      context,
                      activity: activity,
                    )),
                // 溢出提示：告知用户还有未显示的历史数据
                if (compact && todayActivities.length > maxHourGroups)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Center(
                      child: Text(
                        '还有 ${todayActivities.length - maxHourGroups} 个时段',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
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
