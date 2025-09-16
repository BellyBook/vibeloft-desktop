/*
 * Purpose: 简化的使用监控状态管理，提供固定值8的数据
 * Inputs: 无外部依赖，所有数据使用固定值
 * Outputs: 固定的状态数据，触发 UI 重绘
 */

import 'dart:async';
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎简化数据类型定义
// ═══════════════════════════════════════════════════════════════════════════

class UsageEntry {
  final String model;
  final int totalTokens;
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationTokens;
  final int cacheReadTokens;
  final double costUsd;
  final DateTime timestamp;

  const UsageEntry({
    required this.model,
    required this.totalTokens,
    required this.inputTokens,
    required this.outputTokens,
    this.cacheCreationTokens = 0,
    this.cacheReadTokens = 0,
    required this.costUsd,
    required this.timestamp,
  });

  bool get hasTokenBreakdown => 
      inputTokens > 0 || outputTokens > 0 || cacheCreationTokens > 0 || cacheReadTokens > 0;
}

class UsageSession {
  final DateTime startTime;
  final DateTime endTime;
  final int totalTokens;
  final double totalCost;
  final int messageCount;

  const UsageSession({
    required this.startTime,
    required this.endTime,
    required this.totalTokens,
    required this.totalCost,
    required this.messageCount,
  });
}

class UsageStats {
  final int totalTokens;
  final double totalCost;
  final int messageCount;
  final double p90Tokens;
  final double p90Cost;
  final double p90Messages;
  final Map<String, int> modelUsage;

  const UsageStats({
    required this.totalTokens,
    required this.totalCost,
    required this.messageCount,
    required this.p90Tokens,
    required this.p90Cost,
    required this.p90Messages,
    required this.modelUsage,
  });

  static UsageStats empty() => const UsageStats(
    totalTokens: 0,
    totalCost: 0.0,
    messageCount: 0,
    p90Tokens: 0.0,
    p90Cost: 0.0,
    p90Messages: 0.0,
    modelUsage: {},
  );
}

class EnhancedSessionBlock {
  final DateTime startTime;
  final DateTime endTime;
  final int totalTokens;
  final double totalCost;
  final int messageCount;
  final bool isActive;
  final bool isGap;

  const EnhancedSessionBlock({
    required this.startTime,
    required this.endTime,
    required this.totalTokens,
    required this.totalCost,
    required this.messageCount,
    required this.isActive,
    required this.isGap,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎简化状态管理类（使用固定值8）
// ═══════════════════════════════════════════════════════════════════════════

class UsageState extends ChangeNotifier {
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎固定数据
  // ─────────────────────────────────────────────────────────────────────────
  
  static final List<UsageEntry> _fixedEntries = [
    UsageEntry(
      model: 'Sonnet 4',
      totalTokens: 8,
      inputTokens: 8,
      outputTokens: 8,
      costUsd: 8.0,
      timestamp: DateTime.now().subtract(const Duration(minutes: 8)),
    ),
    UsageEntry(
      model: 'Haiku 3.5',
      totalTokens: 8,
      inputTokens: 8,
      outputTokens: 8,
      costUsd: 8.0,
      timestamp: DateTime.now().subtract(const Duration(minutes: 16)),
    ),
    UsageEntry(
      model: 'Opus 3',
      totalTokens: 8,
      inputTokens: 8,
      outputTokens: 8,
      costUsd: 8.0,
      timestamp: DateTime.now().subtract(const Duration(minutes: 24)),
    ),
  ];

  static final List<UsageSession> _fixedSessions = [
    UsageSession(
      startTime: DateTime.now().subtract(const Duration(hours: 8)),
      endTime: DateTime.now(),
      totalTokens: 8,
      totalCost: 8.0,
      messageCount: 8,
    ),
  ];

  static const UsageStats _fixedStats = UsageStats(
    totalTokens: 8,
    totalCost: 8.0,
    messageCount: 8,
    p90Tokens: 8.0,
    p90Cost: 8.0,
    p90Messages: 8.0,
    modelUsage: {
      'Sonnet 4': 8,
      'Haiku 3.5': 8,
      'Opus 3': 8,
    },
  );

  static final List<EnhancedSessionBlock> _fixedBlocks = [
    EnhancedSessionBlock(
      startTime: DateTime.now().subtract(const Duration(hours: 8)),
      endTime: DateTime.now(),
      totalTokens: 8,
      totalCost: 8.0,
      messageCount: 8,
      isActive: true,
      isGap: false,
    ),
  ];
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎状态属性
  // ─────────────────────────────────────────────────────────────────────────
  
  bool _isLoading = false;
  String _errorMessage = '';
  Timer? _refreshTimer;
  
  // 配置
  int _refreshSeconds = 10; // 刷新间隔（秒）
  int _hoursBack = 24; // 查看最近几小时的数据（默认24小时）
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎公开访问器（返回固定值）
  // ─────────────────────────────────────────────────────────────────────────
  
  List<UsageEntry> get entries => _fixedEntries;
  List<UsageSession> get sessions => _fixedSessions;
  UsageStats get stats => _fixedStats;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  int get refreshSeconds => _refreshSeconds;
  int get hoursBack => _hoursBack;
  
  /// 当前会话（固定返回第一个）
  UsageSession? get currentSession => _fixedSessions.isNotEmpty ? _fixedSessions.first : null;

  /// 当前计划类型
  String? get currentPlan => 'custom';

  /// 根据计划类型获取成本限制（固定值）
  double getCostLimit(String plan) {
    switch (plan.toLowerCase()) {
      case 'pro':
        return 88.0;
      case 'max5':
        return 88.0;
      case 'max20':
        return 88.0;
      case 'custom':
      default:
        return 88.0;
    }
  }

  /// 获取活跃会话块列表（固定返回）
  List<EnhancedSessionBlock> getActiveSessionBlocks() {
    return _fixedBlocks;
  }

  /// 获取所有会话块（固定返回）
  List<EnhancedSessionBlock> getAllSessionBlocks() {
    return _fixedBlocks;
  }

  /// 获取完成的会话块（固定返回空列表）
  List<EnhancedSessionBlock> getCompletedSessionBlocks() {
    return [];
  }
  
  /// 今日使用（固定返回）
  UsageStats get todayStats => _fixedStats;
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎数据加载（简化版）
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 初始化并开始监控
  Future<void> initialize() async {
    await loadData();
    startAutoRefresh();
  }
  
  /// 加载数据（模拟加载）
  Future<void> loadData() async {
    if (_isLoading) return;
    
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();
    
    // 模拟加载延时
    await Future.delayed(const Duration(milliseconds: 500));
    
    _isLoading = false;
    notifyListeners();
  }
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎自动刷新
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 开始自动刷新
  void startAutoRefresh() {
    stopAutoRefresh();
    
    _refreshTimer = Timer.periodic(
      Duration(seconds: _refreshSeconds),
      (_) => loadData(),
    );
  }
  
  /// 停止自动刷新
  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎配置更新
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 设置刷新间隔
  void setRefreshSeconds(int seconds) {
    if (seconds < 5 || seconds > 120) return;
    
    _refreshSeconds = seconds;
    notifyListeners();
    
    if (_refreshTimer != null) {
      startAutoRefresh();
    }
  }
  
  /// 设置时间范围
  void setHoursBack(int hours) {
    if (hours < 1 || hours > 720) return;
    
    _hoursBack = hours;
    notifyListeners();
    
    loadData();
  }
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎历史分析（固定返回）
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 计算时间重置（固定返回8小时8分钟后）
  DateTime calculateResetTime() {
    final now = DateTime.now();
    return now.add(const Duration(hours: 8, minutes: 8));
  }

  /// 获取历史 P90 数据（固定返回）
  Future<Map<String, double>> calculateHistoricalP90() async {
    return {
      'tokens': 8.0,
      'messages': 8.0,
      'cost': 8.0,
    };
  }
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎生命周期
  // ─────────────────────────────────────────────────────────────────────────
  
  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }
}