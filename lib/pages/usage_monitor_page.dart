/*
 * Purpose: Claude使用监控主页面，实现9个核心指标的精确计算和显示
 * Inputs: 会话块数据、使用条目
 * Outputs: 响应式Material 3风格UI界面，显示实时监控指标
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/burn_rate.dart';
import '../models/session_block.dart';
import '../providers/usage_monitor_provider.dart';
import '../widgets/today_activity_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎监控主页面 - 9个核心指标实现
// ═══════════════════════════════════════════════════════════════════════════

class UsageMonitorPage extends StatefulWidget {
  const UsageMonitorPage({super.key});

  @override
  State<UsageMonitorPage> createState() => _UsageMonitorPageState();
}

class _UsageMonitorPageState extends State<UsageMonitorPage>
    with TickerProviderStateMixin {
  // ─────────────────────────────────────────────────────────────────────────
  // ▎动画控制器
  // ─────────────────────────────────────────────────────────────────────────

  late AnimationController _fadeController;
  late AnimationController _slideController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // 启动动画
    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: _buildMainContent(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎主内容视图
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMainContent() {
    return Consumer<UsageMonitorProvider>(
      builder: (context, provider, _) {
        // 加载中状态
        if (provider.isLoading && provider.sessionBlocks.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        // 错误状态
        if (provider.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  '加载数据失败',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  provider.errorMessage ?? '',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => provider.refresh(),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // 动态限制卡片 - 使用Provider数据
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeController,
                child: _DynamicLimitsCard(
                  timeToReset: provider.timeToReset,
                  costUsage: provider.costUsage,
                  tokenUsage: provider.tokenUsage,
                  messagesUsage: provider.messagesUsage,
                  costLimit: provider.p90CostLimit,
                  tokenLimit: provider.p90TokenLimit,
                  messageLimit: provider.p90MessageLimit,
                ),
              ),
            ),

            // 预测分析卡片 - 使用Provider数据
            SliverToBoxAdapter(
              child: _PredictionCard(
                timeToReset: provider.timeToReset,
                tokensWillRunOut: provider.tokensWillRunOut,
                limitResetsAt: provider.limitResetsAt,
              ),
            ),

            // 实时监控仪表板 - 使用Provider数据
            SliverToBoxAdapter(
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: _slideController,
                  curve: Curves.easeOutCubic,
                )),
                child: _MonitorDashboard(
                  modelDistribution: provider.modelDistribution,
                  burnRate: provider.burnRate,
                  costRate: provider.costRate,
                ),
              ),
            ),

            // 最近活动时间线 - 使用新的共享组件
            SliverToBoxAdapter(
              child: TodayActivityWidget(
                sessionBlocks: provider.sessionBlocks,
                compact: false, // 使用完整模式
              ),
            ),

            // 底部间距
            const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎工具函数
// ═══════════════════════════════════════════════════════════════════════════

// Token格式化函数 - 添加千位分隔符
String _formatTokenCount(int tokens) {
  // 使用正则表达式添加千位分隔符
  final formatter = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
  final tokenString = tokens.toString();
  return tokenString.replaceAllMapped(formatter, (Match m) => '${m[1]},');
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎动态限制卡片 - 显示9个核心指标中的前4个
// ═══════════════════════════════════════════════════════════════════════════

class _DynamicLimitsCard extends StatelessWidget {
  final Duration timeToReset;
  final double costUsage;
  final int tokenUsage;
  final int messagesUsage;
  final double costLimit;
  final int tokenLimit;
  final int messageLimit;

  const _DynamicLimitsCard({
    required this.timeToReset,
    required this.costUsage,
    required this.tokenUsage,
    required this.messagesUsage,
    required this.costLimit,
    required this.tokenLimit,
    required this.messageLimit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 计算使用率
    final tokenUsageRate = (tokenUsage / tokenLimit).clamp(0.0, 2.0);
    final costUsageRate = (costUsage / costLimit).clamp(0.0, 2.0);
    final messageUsageRate = (messagesUsage / messageLimit).clamp(0.0, 2.0);

    return Container(
      margin: const EdgeInsets.all(12),
      child: Card(
        elevation: 0,
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题
              Row(
                children: [
                  Icon(Icons.dynamic_feed,
                      color: colorScheme.primary, size: 28),
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
              ),
              const SizedBox(height: 12),

              // 成本使用指标（指标1）
              _buildUsageMetric(
                context,
                icon: Icons.attach_money,
                label: '成本使用量',
                value: costUsageRate,
                displayValue:
                    '\$${costUsage.toStringAsFixed(2)} / \$${costLimit.toStringAsFixed(2)}',
                color: _getUsageColor(costUsageRate),
              ),
              const SizedBox(height: 10),

              // Token使用指标（指标2）
              _buildUsageMetric(
                context,
                icon: Icons.token,
                label: 'Token 使用量',
                value: tokenUsageRate,
                displayValue: () {
                  final formatted =
                      '${_formatTokenCount(tokenUsage)} / ${_formatTokenCount(tokenLimit)}';
                  print(
                      'Token 使用量显示: $formatted (原始: $tokenUsage / $tokenLimit)');
                  return formatted;
                }(),
                color: _getUsageColor(tokenUsageRate),
              ),
              const SizedBox(height: 10),

              // 消息使用指标（指标3）
              _buildUsageMetric(
                context,
                icon: Icons.message,
                label: '消息使用量',
                value: messageUsageRate,
                displayValue: '$messagesUsage / $messageLimit',
                color: _getUsageColor(messageUsageRate),
              ),
              const SizedBox(height: 12),

              // 重置时间
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.timer, color: Colors.green, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      '重置倒计时：',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const Spacer(),
                    Text(
                      _formatDuration(timeToReset),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
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

  Widget _buildUsageMetric(
    BuildContext context, {
    required IconData icon,
    required String label,
    required double value,
    required String displayValue,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final percentage = (value * 100).toInt().clamp(0, 100);

    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(label, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              '$percentage%',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            displayValue,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  // 基于使用率返回颜色
  Color _getUsageColor(double usage) {
    if (usage > 0.85) return Colors.red; // 超限状态
    if (usage > 0.70) return Colors.orange; // 警告状态
    if (usage > 0.50) return Colors.amber; // 注意状态
    return Colors.green; // 正常状态
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎监控仪表板 - 显示指标5、6、7（模型分布、燃烧率、成本率）
// ═══════════════════════════════════════════════════════════════════════════

class _MonitorDashboard extends StatelessWidget {
  final Map<String, ModelStats> modelDistribution;
  final BurnRate? burnRate;
  final double costRate;

  const _MonitorDashboard({
    required this.modelDistribution,
    required this.burnRate,
    required this.costRate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // 模型分布
          Card(
            elevation: 0,
            color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.secondary.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.pie_chart, color: colorScheme.secondary),
                      const SizedBox(width: 8),
                      Text(
                        '模型分布',
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildModelDistribution(context),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 燃烧率统计（指标6和7）
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  context,
                  icon: Icons.local_fire_department,
                  label: '燃烧率',
                  value: burnRate?.formatBurnRate() ?? '0',
                  unit: '',
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricCard(
                  context,
                  icon: Icons.monetization_on,
                  label: '成本率',
                  value: '\$${costRate.toStringAsFixed(2)}/小时',
                  unit: '',
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModelDistribution(BuildContext context) {
    if (modelDistribution.isEmpty) {
      return Center(
        child: Text(
          '暂无数据',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Column(
      children: modelDistribution.entries.map((entry) {
        final model = entry.key;
        final stats = entry.value;
        final percentage = stats.percentageByCost;

        final modelInfo = _getModelInfo(model);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: modelInfo['color'] as Color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model),
                    Text(
                      '${stats.totalTokens} tokens • \$${stats.costUsd.toStringAsFixed(4)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // 获取模型信息
  Map<String, dynamic> _getModelInfo(String model) {
    final modelLower = model.toLowerCase();

    if (modelLower.contains('opus')) {
      return {
        'color': Colors.purple,
        'pricing': '输入: \$15 | 输出: \$75',
      };
    } else if (modelLower.contains('sonnet')) {
      return {
        'color': Colors.blue,
        'pricing': '输入: \$3 | 输出: \$15',
      };
    } else if (modelLower.contains('haiku')) {
      return {
        'color': Colors.green,
        'pricing': '输入: \$0.25 | 输出: \$1.25',
      };
    } else {
      return {
        'color': Colors.grey,
        'pricing': '输入: \$3 | 输出: \$15 (估计)',
      };
    }
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String unit,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.1),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: color),
                const SizedBox(width: 8),
                Text(label, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              unit,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎预测卡片 - 显示指标8和9（Token耗尽预测、会话重置时间）
// ═══════════════════════════════════════════════════════════════════════════

class _PredictionCard extends StatelessWidget {
  final Duration timeToReset;
  final DateTime? tokensWillRunOut;
  final DateTime? limitResetsAt;

  const _PredictionCard({
    required this.timeToReset,
    required this.tokensWillRunOut,
    required this.limitResetsAt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.all(12),
      child: Card(
        elevation: 0,
        color: colorScheme.errorContainer.withValues(alpha: 0.2),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.error.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.insights, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Text(
                    '预测分析',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 指标8：Token耗尽预测
              _buildPredictionItem(
                context,
                label: '本轮会话耗尽时间',
                provider: Provider.of<UsageMonitorProvider>(context, listen: false),
                isExhaustion: true,
              ),
              const SizedBox(height: 8),
              // 指标9：会话重置时间
              _buildPredictionItem(
                context,
                label: '会话重置时间',
                provider: Provider.of<UsageMonitorProvider>(context, listen: false),
                isExhaustion: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPredictionItem(
    BuildContext context, {
    required String label,
    required UsageMonitorProvider provider,
    required bool isExhaustion,
  }) {
    final theme = Theme.of(context);
    final time = isExhaustion ? provider.formatTokensWillRunOut() : provider.formatLimitResetsAt();
    final color = isExhaustion ? provider.getPredictionColor() : Colors.blue;

    return Row(
      children: [
        Icon(Icons.schedule, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: theme.textTheme.bodyMedium),
        const Spacer(),
        Text(
          time,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

}

// _ActivityTimeline 类已经被移除，使用新的 TodayActivityWidget 组件替代
