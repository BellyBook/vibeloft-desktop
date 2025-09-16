/*
 * Purpose: 5小时会话块模型，管理使用数据的时间窗口
 * Inputs: 时间范围、使用条目、统计数据
 * Outputs: 会话块状态、聚合统计、活动状态
 */

import 'token_counts.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎5小时会话块模型
// ═══════════════════════════════════════════════════════════════════════════

class SessionBlock {
  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final DateTime? actualEndTime;
  final TokenCounts tokenCounts;
  final double costUsd;
  final Map<String, ModelStats> perModelStats;
  final List<String> models;
  final int sentMessagesCount;
  final Set<String> messageIds;  // 添加消息ID集合用于去重计算
  final bool isActive;
  final bool isGap;
  final int durationMinutes;

  const SessionBlock({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.actualEndTime,
    required this.tokenCounts,
    required this.costUsd,
    required this.perModelStats,
    required this.models,
    required this.sentMessagesCount,
    required this.messageIds,  // 添加到构造函数
    required this.isActive,
    required this.isGap,
    this.durationMinutes = 0,
  });

  // ─────────────────────────────────────────────────────────────────────────
  // ▎计算属性
  // ─────────────────────────────────────────────────────────────────────────

  /// 使用量token数 - 只包含真实的输入输出token
  int get usageTokens => tokenCounts.usageTokens;

  /// 总token数 - 与Python保持一致，仅返回使用量（input+output）
  /// Python在序列化时重新定义了totalTokens为input_tokens + output_tokens
  int get totalTokens => tokenCounts.usageTokens;

  /// 是否已完成
  bool get isCompleted => !isActive && !isGap;

  /// 实际持续时间（分钟）- 修复为高精度计算
  double get actualDurationMinutes {
    if (actualEndTime != null) {
      return actualEndTime!.difference(startTime).inMilliseconds / (1000 * 60);
    }
    if (isActive) {
      return DateTime.now().difference(startTime).inMilliseconds / (1000 * 60);
    }
    return endTime.difference(startTime).inMilliseconds / (1000 * 60);
  }
  
  /// 兼容性方法：返回整数分钟（向上取整）
  int get actualDurationMinutesInt => actualDurationMinutes.ceil();

  /// 使用率（相对于5小时窗口）
  double get usagePercentage {
    const maxMinutes = 5 * 60; // 5小时
    return (actualDurationMinutes / maxMinutes).clamp(0.0, 1.0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎工厂方法
  // ─────────────────────────────────────────────────────────────────────────

  factory SessionBlock.createGap({
    required DateTime startTime,
    required DateTime endTime,
  }) {
    final gapId = 'gap-${startTime.toIso8601String()}';
    return SessionBlock(
      id: gapId,
      startTime: startTime,
      endTime: endTime,
      actualEndTime: null,
      tokenCounts: const TokenCounts(),
      costUsd: 0.0,
      perModelStats: {},
      models: [],
      sentMessagesCount: 0,
      messageIds: const {},  // 间隙块没有消息
      isActive: false,
      isGap: true,
    );
  }

  factory SessionBlock.createNew({
    required DateTime timestamp,
    Duration sessionDuration = const Duration(hours: 5),
  }) {
    // 圆整到整点
    final startTime = DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
      timestamp.hour,
    ).toUtc();
    
    final endTime = startTime.add(sessionDuration);
    final blockId = startTime.toIso8601String();
    
    return SessionBlock(
      id: blockId,
      startTime: startTime,
      endTime: endTime,
      actualEndTime: null,
      tokenCounts: const TokenCounts(),
      costUsd: 0.0,
      perModelStats: {},
      models: [],
      sentMessagesCount: 0,
      messageIds: const {},  // 新块开始时没有消息
      isActive: false,
      isGap: false,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎序列化方法
  // ─────────────────────────────────────────────────────────────────────────
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'actualEndTime': actualEndTime?.toIso8601String(),
      'tokenCounts': tokenCounts.toJson(),
      'costUsd': costUsd,
      'perModelStats': perModelStats.map((k, v) => MapEntry(k, v.toJson())),
      'models': models,
      'sentMessagesCount': sentMessagesCount,
      'messageIds': messageIds.toList(),
      'isActive': isActive,
      'isGap': isGap,
      'durationMinutes': durationMinutes,
    };
  }

  factory SessionBlock.fromJson(Map<String, dynamic> json) {
    return SessionBlock(
      id: json['id'],
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      actualEndTime: json['actualEndTime'] != null 
          ? DateTime.parse(json['actualEndTime']) : null,
      tokenCounts: TokenCounts.fromJson(json['tokenCounts']),
      costUsd: json['costUsd'],
      perModelStats: (json['perModelStats'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, ModelStats.fromJson(v))),
      models: List<String>.from(json['models']),
      sentMessagesCount: json['sentMessagesCount'],
      messageIds: Set<String>.from(json['messageIds']),
      isActive: json['isActive'],
      isGap: json['isGap'],
      durationMinutes: json['durationMinutes'] ?? 0,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎模型统计数据
// ═══════════════════════════════════════════════════════════════════════════

class ModelStats {
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationTokens;
  final int cacheReadTokens;
  final double costUsd;
  final int entriesCount;
  final double percentageByCost;
  final double percentageByTokens;

  const ModelStats({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheCreationTokens,
    required this.cacheReadTokens,
    required this.costUsd,
    required this.entriesCount,
    this.percentageByCost = 0.0,
    this.percentageByTokens = 0.0,
  });

  /// 使用量token数 - 只包含真实的输入输出token
  int get usageTokens => inputTokens + outputTokens;

  /// 总token数 - 包含所有类型token（用于成本计算）
  int get totalTokens =>
      inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens;

  ModelStats operator +(ModelStats other) {
    return ModelStats(
      inputTokens: inputTokens + other.inputTokens,
      outputTokens: outputTokens + other.outputTokens,
      cacheCreationTokens: cacheCreationTokens + other.cacheCreationTokens,
      cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
      costUsd: costUsd + other.costUsd,
      entriesCount: entriesCount + other.entriesCount,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎序列化方法
  // ─────────────────────────────────────────────────────────────────────────
  
  Map<String, dynamic> toJson() {
    return {
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
      'cacheCreationTokens': cacheCreationTokens,
      'cacheReadTokens': cacheReadTokens,
      'costUsd': costUsd,
      'entriesCount': entriesCount,
      'percentageByCost': percentageByCost,
      'percentageByTokens': percentageByTokens,
    };
  }

  factory ModelStats.fromJson(Map<String, dynamic> json) {
    return ModelStats(
      inputTokens: json['inputTokens'],
      outputTokens: json['outputTokens'],
      cacheCreationTokens: json['cacheCreationTokens'],
      cacheReadTokens: json['cacheReadTokens'],
      costUsd: json['costUsd'],
      entriesCount: json['entriesCount'],
      percentageByCost: json['percentageByCost'] ?? 0.0,
      percentageByTokens: json['percentageByTokens'] ?? 0.0,
    );
  }
}