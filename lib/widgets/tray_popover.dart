/*
 * Purpose: 托盘下拉界面组件，展示应用使用统计和摸鱼率
 * Inputs: 应用使用数据、用户交互事件
 * Outputs: Material 3风格的毛玻璃效果UI界面
 */

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/usage_monitor_provider.dart';
import 'cost_usage_progress_bar.dart';
import 'today_activity_widget.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎常量定义
// ═══════════════════════════════════════════════════════════════════════════

class _Constants {
  // 动画
  static const animationDuration = Duration(milliseconds: 300);
  static const slideOffset = Offset(0, -0.1);

  // 尺寸
  static const borderRadius = 8.0;
  static const blurSigma = 20.0;
  static const headerHeight = 40.0;
  static const bottomBarHeight = 48.0;
  static const padding = 16.0;
  static const smallPadding = 12.0;
  static const spacing = 16.0;

  // 透明度
  static const surfaceOpacity = 0.8;
  static const outlineOpacity = 0.1;
  static const subtleOpacity = 0.3;
  static const textSecondaryOpacity = 0.7;
  static const textTertiaryOpacity = 0.6;
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎动画模糊卡片组件 - 合并动画和模糊效果，减少嵌套
// ═══════════════════════════════════════════════════════════════════════════

class AnimatedBlurredCard extends StatelessWidget {
  final AnimationController controller;
  final Widget child;

  const AnimatedBlurredCard({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 滑动偏移动画
        // • 从上方 10% 位置滑入到原位
        // • 使用 easeOutCubic 曲线实现自然减速效果
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        final slideOffset = Tween<Offset>(
          begin: _Constants.slideOffset,
          end: Offset.zero,
        )
            .animate(CurvedAnimation(
              parent: controller,
              curve: Curves.easeOutCubic,
            ))
            .value;

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // 透明度动画
        // • 从完全透明渐变到完全不透明
        // • 配合滑动动画实现淡入效果
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        final opacity = CurvedAnimation(
          parent: controller,
          curve: Curves.easeInOut,
        ).value;

        return Transform.translate(
          // 将偏移量放大 100 倍转换为像素位移
          offset: Offset(slideOffset.dx * 100, slideOffset.dy * 100),
          child: Opacity(
            opacity: opacity,
            child: Container(
              // ┌─────────────────────────────────────────────────────────┐
              // │ 容器装饰                                                 │
              // │ • 半透明背景色 (80% 不透明度)                             │
              // │ • 圆角边框 (8px)                                         │
              // └─────────────────────────────────────────────────────────┘
              decoration: BoxDecoration(
                color: colorScheme.surface
                    .withValues(alpha: _Constants.surfaceOpacity),
                borderRadius: BorderRadius.circular(_Constants.borderRadius),
              ),
              clipBehavior: Clip.antiAlias, // 裁剪超出圆角的内容
              child: BackdropFilter(
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // 毛玻璃模糊效果
                // • sigmaX/Y = 20: 中等强度模糊
                // • 营造 macOS 风格的景深效果
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                filter: ImageFilter.blur(
                  sigmaX: _Constants.blurSigma,
                  sigmaY: _Constants.blurSigma,
                ),
                child: child, // 传入的实际内容组件
              ),
            ),
          ),
        );
      },
      child: child, // AnimatedBuilder 的子组件缓存，避免重建
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎托盘下拉界面主组件
// ═══════════════════════════════════════════════════════════════════════════

class TrayPopover extends StatefulWidget {
  const TrayPopover({super.key});

  @override
  State<TrayPopover> createState() => _TrayPopoverState();
}

class _TrayPopoverState extends State<TrayPopover>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  // Popover 专用 MethodChannel
  static const _popoverChannel = MethodChannel('com.vibeloft.desktop/popover');

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: _Constants.animationDuration,
      vsync: this,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBlurredCard(
      controller: _animationController,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            // ═══════════════════════════════════════════════════════════════
            // ▎顶部标题栏
            // • 显示应用名称 "Claude Code 监控"
            // • 提供显示主窗口快捷按钮
            // ═══════════════════════════════════════════════════════════════
            PopoverHeader(popoverChannel: _popoverChannel),

            // ═══════════════════════════════════════════════════════════════
            // ▎可滚动内容区域
            // ═══════════════════════════════════════════════════════════════
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(_Constants.padding),
                child: Column(
                  // ┌─────────────────────────────────────────────────────────┐
                  // │ 中间内容区域 - 核心数据展示                                │
                  // └─────────────────────────────────────────────────────────┘
                  children: [
                    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    // Claude 成本使用监控卡片
                    // • 成本使用量
                    // • Token使用量
                    // • 消息使用量
                    // • 重置倒计时
                    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    const CostUsageCard(),
                    const SizedBox(height: 8),

                    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    // 会话时间预测卡片
                    // • 本轮会话耗尽时间
                    // • 会话重置时间
                    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    const SessionPredictionCard(),
                    const SizedBox(height: 8),

                    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    // 今日消耗时间线（紧凑模式）
                    // • 显示最近3个时段
                    // • 汇总模型使用情况
                    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    Consumer<UsageMonitorProvider>(
                      builder: (context, provider, _) {
                        return TodayActivityWidget(
                          sessionBlocks: provider.sessionBlocks,
                          compact: true,
                          maxHourGroups: 3,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ═══════════════════════════════════════════════════════════════
            // ▎底部操作栏
            // • 退出按钮 - 关闭应用程序
            // • 访问官网 - 打开 VibeLoft 网站
            // ═══════════════════════════════════════════════════════════════
            const PopoverBottomBar(),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎顶部标题栏组件
// ═══════════════════════════════════════════════════════════════════════════
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ 功能说明：                                                               │
// │ • 显示应用标题 "VibeLoft Desktop"                                        │
// │ • 提供快捷打开主窗口按钮                                                   │
// │ • 底部带分割线与内容区域区分                                               │
// └─────────────────────────────────────────────────────────────────────────┘

class PopoverHeader extends StatelessWidget {
  final MethodChannel popoverChannel;

  const PopoverHeader({
    super.key,
    required this.popoverChannel,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: _Constants.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: _Constants.padding),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline
                .withValues(alpha: _Constants.outlineOpacity),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          // 应用标题
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          Text(
            'Claude Code 监控',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          // 显示主窗口按钮
          // • 点击后通过 MethodChannel 调用原生方法
          // • 将主窗口从最小化状态恢复并置于前台
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          IconButton(
            icon: const Icon(Icons.desktop_windows),
            iconSize: 18,
            tooltip: '显示主窗口',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            onPressed: () async {
              await popoverChannel.invokeMethod('showMainWindow');
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎Claude 成本使用监控卡片
// ═══════════════════════════════════════════════════════════════════════════

class CostUsageCard extends StatelessWidget {
  const CostUsageCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UsageMonitorProvider>(
      builder: (context, provider, _) {
        // 加载中状态
        if (provider.isLoading && provider.sessionBlocks.isEmpty) {
          return Container(
            height: 200,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(strokeWidth: 2),
          );
        }

        // 错误状态
        if (provider.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                  size: 32,
                ),
                const SizedBox(height: 8),
                Text(
                  '加载失败',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => provider.refresh(),
                  child: const Text('重试'),
                ),
              ],
            ),
          );
        }

        // 显示成本使用进度条
        return CostUsageProgressBar(
          costUsage: provider.costUsage,
          tokenUsage: provider.tokenUsage,
          messagesUsage: provider.messagesUsage,
          costLimit: provider.p90CostLimit,
          tokenLimit: provider.p90TokenLimit,
          messageLimit: provider.p90MessageLimit,
          timeToReset: provider.timeToReset,
          compact: true, // 使用紧凑模式
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎会话时间预测卡片
// ═══════════════════════════════════════════════════════════════════════════

class SessionPredictionCard extends StatelessWidget {
  const SessionPredictionCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<UsageMonitorProvider>(
      builder: (context, provider, _) {
        // 使用与 CostUsageProgressBar 相同的卡片样式
        return Container(
          padding: const EdgeInsets.all(12), // 紧凑模式padding
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─────────────────────────────────────────────────────────────────────────
              // ▎标题行
              // ─────────────────────────────────────────────────────────────────────────
              Row(
                children: [
                  Icon(
                    Icons.insights,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '会话预测',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // ─────────────────────────────────────────────────────────────────────────
              // ▎本轮会话耗尽时间
              // ─────────────────────────────────────────────────────────────────────────
              _buildPredictionRow(
                context,
                icon: Icons.timer_off,
                label: '耗尽时间',
                value: provider.formatTokensWillRunOut(),
                color: provider.getPredictionColor(),
              ),
              const SizedBox(height: 8),

              // ─────────────────────────────────────────────────────────────────────────
              // ▎会话重置时间
              // ─────────────────────────────────────────────────────────────────────────
              _buildPredictionRow(
                context,
                icon: Icons.refresh,
                label: '重置时间',
                value: provider.formatLimitResetsAt(),
                color: Colors.blue,
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎构建预测行
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPredictionRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎底部操作栏组件
// ═══════════════════════════════════════════════════════════════════════════
// ┌─────────────────────────────────────────────────────────────────────────┐
// │ 功能说明：                                                               │
// │ • 提供快捷操作按钮组                                                      │
// │ • 顶部带分割线与内容区域区分                                               │
// │ • 两个按钮：退出应用（左）、打开网页（右）                                 │
// └─────────────────────────────────────────────────────────────────────────┘

class PopoverBottomBar extends StatelessWidget {
  const PopoverBottomBar({super.key});

  // Popover 专用 MethodChannel
  static const _popoverChannel = MethodChannel('com.vibeloft.desktop/popover');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: _Constants.bottomBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: _Constants.padding),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outline
                .withValues(alpha: _Constants.outlineOpacity),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          // 退出按钮（左侧）
          // • 关闭应用程序
          // • 通过 MethodChannel 调用原生退出方法
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            iconSize: 18,
            tooltip: '退出应用',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            color: colorScheme.error,
            onPressed: () async {
              await _popoverChannel.invokeMethod('exitApp');
            },
          ),

          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          // 打开网页按钮（右侧）
          // • 在默认浏览器中打开 VibeLoft 官网
          // • URL: https://vibeloft.ai/
          // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
          IconButton(
            icon: const Icon(Icons.language),
            iconSize: 18,
            tooltip: '访问官网',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            onPressed: () async {
              await _popoverChannel.invokeMethod('openURL', {
                'url': 'https://vibeloft.ai/',
              });
            },
          ),
        ],
      ),
    );
  }
}
