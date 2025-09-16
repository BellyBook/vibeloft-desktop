/*
 * Purpose: Token计数模型，支持input/output/cache的精确统计
 * Inputs: 各类token计数值
 * Outputs: 聚合的token统计数据
 */

// ═══════════════════════════════════════════════════════════════════════════
// ▎Token计数模型 - 多维度统计
// ═══════════════════════════════════════════════════════════════════════════

class TokenCounts {
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationTokens;
  final int cacheReadTokens;

  const TokenCounts({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheCreationTokens = 0,
    this.cacheReadTokens = 0,
  });

  // ─────────────────────────────────────────────────────────────────────────
  // ▎计算属性
  // ─────────────────────────────────────────────────────────────────────────

  /// 使用量token数 - 只包含真实的输入输出token
  int get usageTokens => inputTokens + outputTokens;

  /// 总token数 - 包含所有类型token（用于成本计算）
  int get totalTokens =>
      inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens;

  /// 是否有有效数据
  bool get hasData => usageTokens > 0;

  /// 是否有缓存使用
  bool get hasCacheUsage => cacheCreationTokens > 0 || cacheReadTokens > 0;

  // ─────────────────────────────────────────────────────────────────────────
  // ▎运算符重载
  // ─────────────────────────────────────────────────────────────────────────

  TokenCounts operator +(TokenCounts other) {
    return TokenCounts(
      inputTokens: inputTokens + other.inputTokens,
      outputTokens: outputTokens + other.outputTokens,
      cacheCreationTokens: cacheCreationTokens + other.cacheCreationTokens,
      cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎工厂方法
  // ─────────────────────────────────────────────────────────────────────────

  factory TokenCounts.fromMap(Map<String, dynamic> map) {
    return TokenCounts(
      inputTokens: map['input_tokens'] ?? 0,
      outputTokens: map['output_tokens'] ?? 0,
      cacheCreationTokens: map['cache_creation_tokens'] ?? 0,
      cacheReadTokens: map['cache_read_tokens'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'cache_creation_tokens': cacheCreationTokens,
      'cache_read_tokens': cacheReadTokens,
      'total_tokens': totalTokens,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎序列化方法（兼容Isolate传输）
  // ─────────────────────────────────────────────────────────────────────────
  
  Map<String, dynamic> toJson() {
    return {
      'inputTokens': inputTokens,
      'outputTokens': outputTokens,
      'cacheCreationTokens': cacheCreationTokens,
      'cacheReadTokens': cacheReadTokens,
    };
  }

  factory TokenCounts.fromJson(Map<String, dynamic> json) {
    return TokenCounts(
      inputTokens: json['inputTokens'] ?? 0,
      outputTokens: json['outputTokens'] ?? 0,
      cacheCreationTokens: json['cacheCreationTokens'] ?? 0,
      cacheReadTokens: json['cacheReadTokens'] ?? 0,
    );
  }
}