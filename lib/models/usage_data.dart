/*
 * Purpose: Claude 使用数据模型定义
 * Inputs: JSON 数据从 JSONL 文件
 * Outputs: 结构化的使用数据对象
 */

// ═══════════════════════════════════════════════════════════════════════════
// ▎核心数据模型
// ═══════════════════════════════════════════════════════════════════════════

/// 单条使用记录
class UsageEntry {
  final String messageId;
  final String requestId; 
  final DateTime timestamp;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationTokens;
  final int cacheReadTokens;
  final double costUsd;

  UsageEntry({
    required this.messageId,
    required this.requestId,
    required this.timestamp,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    this.cacheCreationTokens = 0,
    this.cacheReadTokens = 0,
    required this.costUsd,
  });

  /// 总 token 数
  int get totalTokens =>
      inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens;

  /// 唯一标识符
  String get uniqueId => '$messageId:$requestId';

  /// 从 JSON 创建实例
  factory UsageEntry.fromJson(Map<String, dynamic> json) {
    // 处理实际的 Claude JSONL 格式
    // token 数据在 message.usage 字段中
    final message = json['message'] as Map<String, dynamic>?;
    final usage = message?['usage'] as Map<String, dynamic>?;
    
    if (usage == null) {
      // 如果没有 usage 数据，返回空记录
      return UsageEntry(
        messageId: message?['id'] ?? json['uuid'] ?? '',
        requestId: json['requestId'] ?? '',
        timestamp: DateTime.parse(json['timestamp']),
        model: message?['model'] ?? json['model'] ?? '',
        inputTokens: 0,
        outputTokens: 0,
        cacheCreationTokens: 0,
        cacheReadTokens: 0,
        costUsd: 0.0,
      );
    }
    
    // 提取 token 数据
    final inputTokens = usage['input_tokens'] ?? 0;
    final outputTokens = usage['output_tokens'] ?? 0;
    final cacheCreationTokens = usage['cache_creation_input_tokens'] ?? 0;
    final cacheReadTokens = usage['cache_read_input_tokens'] ?? 0;
    
    // 计算成本（基于模型定价）
    final model = message?['model'] ?? '';
    final costUsd = _calculateCost(
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cacheCreationTokens: cacheCreationTokens,
      cacheReadTokens: cacheReadTokens,
    );
    
    return UsageEntry(
      messageId: message?['id'] ?? json['uuid'] ?? '',
      requestId: json['requestId'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      model: model,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      cacheCreationTokens: cacheCreationTokens,
      cacheReadTokens: cacheReadTokens,
      costUsd: costUsd,
    );
  }
  
  /// 计算成本（基于 2024 年定价）
  static double _calculateCost({
    required String model,
    required int inputTokens,
    required int outputTokens,
    required int cacheCreationTokens,
    required int cacheReadTokens,
  }) {
    // 定价表（每百万 token 的价格）
    const pricing = {
      'claude-3-opus': {
        'input': 15.00,
        'output': 75.00,
        'cache_creation': 18.75,  // 与参考实现一致
        'cache_read': 1.50,       // 与参考实现一致
      },
      'claude-3-sonnet': {
        'input': 3.00,
        'output': 15.00,
        'cache_creation': 3.75,   // 与参考实现一致
        'cache_read': 0.30,       // 与参考实现一致
      },
      'claude-3-haiku': {
        'input': 0.25,
        'output': 1.25,
        'cache_creation': 0.30,   // 与参考实现一致
        'cache_read': 0.03,       // 与参考实现一致
      },
    };
    
    // 根据模型名称确定定价
    Map<String, double> modelPricing;
    if (model.contains('opus')) {
      modelPricing = pricing['claude-3-opus']!;
    } else if (model.contains('sonnet')) {
      modelPricing = pricing['claude-3-sonnet']!;
    } else if (model.contains('haiku')) {
      modelPricing = pricing['claude-3-haiku']!;
    } else {
      // 默认使用 Sonnet 定价
      modelPricing = pricing['claude-3-sonnet']!;
    }
    
    // 计算总成本
    final cost = (inputTokens * modelPricing['input']! +
            outputTokens * modelPricing['output']! +
            cacheCreationTokens * modelPricing['cache_creation']! +
            cacheReadTokens * modelPricing['cache_read']!) /
        1000000; // 转换为美元
    
    return cost;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎会话数据模型
// ═══════════════════════════════════════════════════════════════════════════

/// 5小时会话块
class UsageSession {
  final DateTime startTime;
  final DateTime endTime;
  final List<UsageEntry> entries;

  UsageSession({
    required this.startTime,
    required this.endTime,
    required this.entries,
  });

  /// 会话总 token 数
  int get totalTokens => entries.fold(0, (sum, e) => sum + e.totalTokens);

  /// 会话总成本
  double get totalCost => entries.fold(0.0, (sum, e) => sum + e.costUsd);

  /// 消息数量
  int get messageCount => entries.length;

  /// 会话持续时间（小时）
  double get durationHours => endTime.difference(startTime).inMinutes / 60.0;
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎统计数据模型
// ═══════════════════════════════════════════════════════════════════════════

/// 使用统计
class UsageStats {
  final int totalTokens;
  final double totalCost;
  final int messageCount;
  final Map<String, int> modelUsage;
  final double p90Tokens;
  final double p90Cost;
  final double p90Messages;

  UsageStats({
    required this.totalTokens,
    required this.totalCost,
    required this.messageCount,
    required this.modelUsage,
    required this.p90Tokens,
    required this.p90Cost,
    required this.p90Messages,
  });

  /// 空统计对象
  factory UsageStats.empty() {
    return UsageStats(
      totalTokens: 0,
      totalCost: 0.0,
      messageCount: 0,
      modelUsage: {},
      p90Tokens: 0.0,
      p90Cost: 0.0,
      p90Messages: 0.0,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎定价配置
// ═══════════════════════════════════════════════════════════════════════════

/// 模型定价（每百万 token）
class ModelPricing {
  static const Map<String, Map<String, double>> pricing = {
    'claude-3-opus': {
      'input': 15.00,
      'output': 75.00,
      'cache_creation': 18.75,  // 与参考实现一致
      'cache_read': 1.50,       // 与参考实现一致
    },
    'claude-3-sonnet': {
      'input': 3.00,
      'output': 15.00,
      'cache_creation': 3.75,   // 与参考实现一致
      'cache_read': 0.30,       // 与参考实现一致
    },
    'claude-3-haiku': {
      'input': 0.25,
      'output': 1.25,
      'cache_creation': 0.30,   // 与参考实现一致
      'cache_read': 0.03,       // 与参考实现一致
    },
  };

  /// 计算成本
  static double calculateCost(String model, UsageEntry entry) {
    final modelPricing = pricing[model] ?? pricing['claude-3-sonnet']!;
    
    return (entry.inputTokens * modelPricing['input']! +
            entry.outputTokens * modelPricing['output']! +
            entry.cacheCreationTokens * modelPricing['cache_creation']! +
            entry.cacheReadTokens * modelPricing['cache_read']!) /
        1000000;
  }
}