/*
 * Purpose: 可复用的成本使用进度条组件
 * Inputs: 成本、Token、消息使用数据和限制值
 * Outputs: Material 3风格的进度条UI
 */

import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎可复用的成本使用进度条组件
// ▎
// ▎显示三个核心指标的实时使用情况：
// ▎  • 成本（美元计价）
// ▎  • Token消耗量
// ▎  • 消息数量
// ▎
// ▎设计原则：
// ▎  • 通过颜色渐变直观展示使用状态
// ▎  • 支持紧凑/标准两种显示模式
// ▎  • 允许使用率超过100%（最多200%）但视觉上限制在100%
// ═══════════════════════════════════════════════════════════════════════════

class CostUsageProgressBar extends StatelessWidget {
  // ─────────────────────────────────────────────────────────────────────────
  // ▎输入参数
  // ─────────────────────────────────────────────────────────────────────────

  final double costUsage;      // 当前成本使用量（美元）
  final int tokenUsage;         // 当前Token使用量
  final int messagesUsage;      // 当前消息使用量
  final double costLimit;       // 成本限制（美元）
  final int tokenLimit;         // Token限制
  final int messageLimit;       // 消息限制
  final Duration timeToReset;   // 距离重置剩余时间
  final bool compact;           // 紧凑模式标志（托盘界面使用）

  const CostUsageProgressBar({
    super.key,
    required this.costUsage,
    required this.tokenUsage,
    required this.messagesUsage,
    required this.costLimit,
    required this.tokenLimit,
    required this.messageLimit,
    required this.timeToReset,
    this.compact = false,
  });

  // ─────────────────────────────────────────────────────────────────────────
  // ▎构建方法
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 计算使用率（允许超过100%，最高200%用于警告）
    // clamp到2.0是为了在极限情况下仍能显示有意义的数据
    final tokenUsageRate = (tokenUsage / tokenLimit).clamp(0.0, 2.0);
    final costUsageRate = (costUsage / costLimit).clamp(0.0, 2.0);
    final messageUsageRate = (messagesUsage / messageLimit).clamp(0.0, 2.0);

    // 主容器：根据模式调整内边距和外观
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        // 紧凑模式使用更深的背景，标准模式使用主色容器
        color: compact
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)
            : colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(compact ? 12 : 16),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏：仅在标准模式显示，提供视觉层次
          if (!compact) ...[
            _buildHeader(context),
            const SizedBox(height: 12),
          ],

          // ═════════════════════════════════════════════════════════════════
          // ▎三大核心指标展示
          // ═════════════════════════════════════════════════════════════════

          // 1. 成本使用指标 - 最重要的财务指标
          _buildUsageMetric(
            context,
            icon: Icons.attach_money,
            label: '成本使用量',
            value: costUsageRate,
            displayValue:
                '\$${costUsage.toStringAsFixed(2)} / \$${costLimit.toStringAsFixed(2)}',
            color: _getUsageColor(costUsageRate),
            compact: compact,
          ),
          SizedBox(height: compact ? 8 : 10),

          // 2. Token使用指标 - 技术层面的资源消耗
          _buildUsageMetric(
            context,
            icon: Icons.token,
            label: 'Token 使用量',
            value: tokenUsageRate,
            displayValue:
                '${_formatTokenCount(tokenUsage)} / ${_formatTokenCount(tokenLimit)}',
            color: _getUsageColor(tokenUsageRate),
            compact: compact,
          ),
          SizedBox(height: compact ? 8 : 10),

          // 3. 消息使用指标 - 交互频次限制
          _buildUsageMetric(
            context,
            icon: Icons.message,
            label: '消息使用量',
            value: messageUsageRate,
            displayValue: '$messagesUsage / $messageLimit',
            color: _getUsageColor(messageUsageRate),
            compact: compact,
          ),
          SizedBox(height: compact ? 10 : 12),

          // 重置倒计时：告诉用户何时刷新配额
          _buildResetTimer(context),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎组件构建方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 构建标题栏：显示组件标题和图标
  /// 仅在标准模式下显示，紧凑模式省略以节省空间
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(Icons.dynamic_feed, color: colorScheme.primary, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '基于会话的动态指标',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 构建单个使用指标的可视化组件
  ///
  /// 特点：
  ///   - 图标+标签+百分比的水平布局
  ///   - 带颜色编码的线性进度条
  ///   - 紧凑模式下合并标签和数值显示
  Widget _buildUsageMetric(
    BuildContext context, {
    required IconData icon,
    required String label,
    required double value,
    required String displayValue,
    required Color color,
    required bool compact,
  }) {
    final theme = Theme.of(context);
    // 百分比显示限制在100%以内，即使实际值可能超过
    final percentage = (value * 100).toInt().clamp(0, 100);

    return Column(
      children: [
        Row(
          children: [
            // 图标：根据使用率动态着色
            Icon(icon, size: compact ? 16 : 20, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                // 紧凑模式：合并标签和数值；标准模式：仅显示标签
                compact ? '$label: $displayValue' : label,
                style: compact
                    ? theme.textTheme.bodySmall
                    : theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // 百分比：醒目显示当前使用率
            Text(
              '$percentage%',
              style: (compact
                      ? theme.textTheme.bodySmall
                      : theme.textTheme.bodyMedium)
                  ?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 进度条：视觉化展示使用程度
        ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 6 : 8),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0), // 视觉上限制在100%
            minHeight: compact ? 6 : 8,
            backgroundColor: color.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        // 标准模式：额外显示详细数值
        if (!compact) ...[
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              displayValue,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }

  /// 构建重置倒计时器
  ///
  /// 显示距离配额重置的剩余时间
  /// 使用绿色主题传达积极的信息：配额即将刷新
  Widget _buildResetTimer(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(compact ? 10 : 12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.timer,
            color: Colors.green,
            size: compact ? 20 : 24,
          ),
          const SizedBox(width: 12),
          Text(
            '重置倒计时：',
            style: compact
                ? theme.textTheme.bodySmall
                : theme.textTheme.bodyMedium,
          ),
          const Spacer(),
          // 突出显示剩余时间
          Text(
            _formatDuration(timeToReset),
            style: (compact
                    ? theme.textTheme.titleSmall
                    : theme.textTheme.titleMedium)
                ?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎辅助方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 格式化Token数量：添加千位分隔符提高可读性
  ///
  /// 例：1234567 -> 1,234,567
  String _formatTokenCount(int tokens) {
    // 正则：每3位数字前添加逗号（从右向左）
    final formatter = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final tokenString = tokens.toString();
    return tokenString.replaceAllMapped(formatter, (Match m) => '${m[1]},');
  }

  /// 格式化时长：将Duration转换为易读的小时分钟格式
  ///
  /// 例：Duration(hours: 2, minutes: 30) -> "2h 30m"
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  /// 根据使用率返回对应的警示颜色
  ///
  /// 颜色策略：
  ///   - 0-50%：绿色（安全）
  ///   - 50-70%：琥珀色（注意）
  ///   - 70-85%：橙色（警告）
  ///   - 85%+：红色（危险/超限）
  ///
  /// 设计理念：渐进式警告，让用户有充分时间响应
  Color _getUsageColor(double usage) {
    if (usage > 0.85) return Colors.red;     // 超限状态：需要立即行动
    if (usage > 0.70) return Colors.orange;  // 警告状态：应当关注
    if (usage > 0.50) return Colors.amber;   // 注意状态：开始留意
    return Colors.green;                     // 正常状态：健康使用
  }
}
