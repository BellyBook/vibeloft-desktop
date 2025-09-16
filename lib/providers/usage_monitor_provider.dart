/*
 * Purpose: 全局使用监控数据管理器，提供统一的数据源
 * Inputs: JSONL数据文件、时间范围参数
 * Outputs: 9个核心监控指标、自动刷新机制
 */

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/burn_rate.dart';
import '../models/session_block.dart';
import '../services/isolate_data_processor.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎全局使用监控数据提供者
// ═══════════════════════════════════════════════════════════════════════════

class UsageMonitorProvider extends ChangeNotifier {
  // ─────────────────────────────────────────────────────────────────────────
  // ▎配置常量
  // ─────────────────────────────────────────────────────────────────────────

  /// 数据加载范围 - 加载7天数据用于P90计算
  static const Duration dataLoadRange = Duration(days: 7);

  /// 自动刷新间隔
  static const Duration refreshInterval = Duration(seconds: 8);

  // ─────────────────────────────────────────────────────────────────────────
  // ▎核心数据状态
  // ─────────────────────────────────────────────────────────────────────────

  List<SessionBlock> _sessionBlocks = [];
  List<Map<String, dynamic>> _usageEntries = [];

  // 9个核心指标
  double _costUsage = 0.0; // 1. 成本使用量
  int _tokenUsage = 0; // 2. Token使用量
  int _messagesUsage = 0; // 3. 消息使用量
  Duration _timeToReset = Duration.zero; // 4. 重置倒计时
  Map<String, ModelStats> _modelDistribution = {}; // 5. 模型分布
  BurnRate? _burnRate; // 6. 燃烧率
  double _costRate = 0.0; // 7. 成本率
  DateTime? _tokensWillRunOut; // 8. Token耗尽预测
  DateTime? _limitResetsAt; // 9. 会话重置时间

  // P90限制值
  int _p90TokenLimit = 88000;
  double _p90CostLimit = 5.0;
  int _p90MessageLimit = 100;

  // 状态标志
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _refreshTimer;

  // ─────────────────────────────────────────────────────────────────────────
  // ▎公开访问器
  // ─────────────────────────────────────────────────────────────────────────

  // 数据集合
  List<SessionBlock> get sessionBlocks => _sessionBlocks;
  List<Map<String, dynamic>> get usageEntries => _usageEntries;

  // 9个核心指标
  double get costUsage => _costUsage;
  int get tokenUsage => _tokenUsage;
  int get messagesUsage => _messagesUsage;
  Duration get timeToReset => _timeToReset;
  Map<String, ModelStats> get modelDistribution => _modelDistribution;
  BurnRate? get burnRate => _burnRate;
  double get costRate => _costRate;
  DateTime? get tokensWillRunOut => _tokensWillRunOut;
  DateTime? get limitResetsAt => _limitResetsAt;

  // P90限制
  int get p90TokenLimit => _p90TokenLimit;
  double get p90CostLimit => _p90CostLimit;
  int get p90MessageLimit => _p90MessageLimit;

  // 状态
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null && _errorMessage!.isNotEmpty;

  // ─────────────────────────────────────────────────────────────────────────
  // ▎生命周期方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 初始化Provider
  Future<void> initialize() async {
    await loadData();
    startAutoRefresh();
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎数据加载和刷新
  // ─────────────────────────────────────────────────────────────────────────

  /// 加载数据 - 使用Isolate后台处理
  Future<void> loadData() async {
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // 使用Isolate在后台线程处理所有数据
      final cutoffTime = DateTime.now().toUtc().subtract(dataLoadRange);
      final endTime = DateTime.now().toUtc();

      // 在后台线程执行所有繁重计算
      final metrics = await IsolateDataProcessor.processInBackground(
        startTime: cutoffTime,
        endTime: endTime,
      );

      // 更新状态
      _sessionBlocks = metrics.sessionBlocks;
      _usageEntries = metrics.usageEntries;
      _costUsage = metrics.costUsage;
      _tokenUsage = metrics.tokenUsage;
      _messagesUsage = metrics.messagesUsage;
      _timeToReset = metrics.timeToReset;
      _modelDistribution = metrics.modelDistribution;
      _burnRate = metrics.burnRate;
      _costRate = metrics.costRate;
      _tokensWillRunOut = metrics.tokensWillRunOut;
      _limitResetsAt = metrics.limitResetsAt;
      _p90TokenLimit = metrics.p90TokenLimit;
      _p90CostLimit = metrics.p90CostLimit;
      _p90MessageLimit = metrics.p90MessageLimit;

      _errorMessage = null;
      debugPrint('UsageMonitorProvider: 数据加载完成，${_usageEntries.length} entries');
    } catch (e) {
      _errorMessage = '加载数据失败: ${e.toString()}';
      debugPrint('UsageMonitorProvider 错误: $_errorMessage');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 开始自动刷新
  void startAutoRefresh() {
    stopAutoRefresh();
    _refreshTimer = Timer.periodic(refreshInterval, (_) => loadData());
  }

  /// 停止自动刷新
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// 手动刷新
  Future<void> refresh() async {
    await loadData();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎便捷方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 获取成本使用率
  double get costUsageRate => (_costUsage / _p90CostLimit).clamp(0.0, 2.0);

  /// 获取Token使用率
  double get tokenUsageRate => (_tokenUsage / _p90TokenLimit).clamp(0.0, 2.0);

  /// 获取消息使用率
  double get messageUsageRate => (_messagesUsage / _p90MessageLimit).clamp(0.0, 2.0);

  /// 格式化重置时间
  String formatTimeToReset() {
    final hours = _timeToReset.inHours;
    final minutes = _timeToReset.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  /// 获取使用状态颜色
  Color getUsageColor(double usage) {
    if (usage > 0.85) return const Color(0xFFFF5252); // 红色 - 超限
    if (usage > 0.70) return const Color(0xFFFF9800); // 橙色 - 警告
    if (usage > 0.50) return const Color(0xFFFFC107); // 琥珀色 - 注意
    return const Color(0xFF4CAF50); // 绿色 - 正常
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎时间预测格式化方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 格式化本轮会话耗尽时间
  String formatTokensWillRunOut() {
    if (_tokensWillRunOut == null) return '重置前不会耗尽';

    // 转换到本地时区并使用12小时制格式
    final localTime = _tokensWillRunOut!.toLocal();
    final hour = localTime.hour;
    final minute = localTime.minute.toString().padLeft(2, '0');

    if (hour == 0) {
      return '12:$minute AM';
    } else if (hour < 12) {
      return '$hour:$minute AM';
    } else if (hour == 12) {
      return '12:$minute PM';
    } else {
      return '${hour - 12}:$minute PM';
    }
  }

  /// 格式化会话重置时间
  String formatLimitResetsAt() {
    if (_limitResetsAt == null) return '未知';

    // 转换到本地时区并使用12小时制格式
    final localTime = _limitResetsAt!.toLocal();
    final hour = localTime.hour;
    final minute = localTime.minute.toString().padLeft(2, '0');

    if (hour == 0) {
      return '12:$minute AM';
    } else if (hour < 12) {
      return '$hour:$minute AM';
    } else if (hour == 12) {
      return '12:$minute PM';
    } else {
      return '${hour - 12}:$minute PM';
    }
  }

  /// 获取预测状态颜色
  Color getPredictionColor() {
    if (_tokensWillRunOut == null) return Colors.grey;

    final now = DateTime.now();
    if (_tokensWillRunOut!.isBefore(now)) return Colors.red;

    final diff = _tokensWillRunOut!.difference(now);
    if (diff.inHours < 1) return Colors.orange;
    if (diff.inHours < 3) return Colors.amber;

    return Colors.green;
  }
}