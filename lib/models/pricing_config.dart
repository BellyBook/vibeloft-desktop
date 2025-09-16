/*
 * Purpose: 定价配置模型，支持Claude系列模型的精确成本计算
 * Inputs: 模型定价参数
 * Outputs: 标准化的定价配置
 */

// ═══════════════════════════════════════════════════════════════════════════
// ▎定价配置
// ═══════════════════════════════════════════════════════════════════════════

class PricingConfig {
  final double inputPrice;       // 每百万token的输入价格
  final double outputPrice;      // 每百万token的输出价格
  final double cacheCreationPrice; // 缓存创建价格（通常是input的1.25倍）
  final double cacheReadPrice;    // 缓存读取价格（通常是input的0.1倍）

  const PricingConfig({
    required this.inputPrice,
    required this.outputPrice,
    double? cacheCreationPrice,
    double? cacheReadPrice,
  })  : cacheCreationPrice = cacheCreationPrice ?? (inputPrice * 1.25),
        cacheReadPrice = cacheReadPrice ?? (inputPrice * 0.1);

  // ─────────────────────────────────────────────────────────────────────────
  // ▎默认定价表 - Claude系列
  // ─────────────────────────────────────────────────────────────────────────

  static const Map<String, PricingConfig> defaultPricing = {
    'opus': PricingConfig(
      inputPrice: 15.0,   // $15 per 1M tokens
      outputPrice: 75.0,  // $75 per 1M tokens
    ),
    'sonnet': PricingConfig(
      inputPrice: 3.0,    // $3 per 1M tokens
      outputPrice: 15.0,  // $15 per 1M tokens
    ),
    'haiku': PricingConfig(
      inputPrice: 0.25,   // $0.25 per 1M tokens
      outputPrice: 1.25,  // $1.25 per 1M tokens
    ),
  };

  // ─────────────────────────────────────────────────────────────────────────
  // ▎模型映射
  // ─────────────────────────────────────────────────────────────────────────

  static const Map<String, String> modelMapping = {
    'claude-3-opus': 'opus',
    'claude-3-sonnet': 'sonnet',
    'claude-3-haiku': 'haiku',
    'claude-3-5-sonnet': 'sonnet',
    'claude-3-5-haiku': 'haiku',
    'claude-sonnet-4-20250514': 'sonnet',
    'claude-opus-4-20250514': 'opus',
    'claude-opus-4-1-20250805': 'opus',
  };

  // ─────────────────────────────────────────────────────────────────────────
  // ▎获取模型定价
  // ─────────────────────────────────────────────────────────────────────────

  static PricingConfig getPricingForModel(String model) {
    // 标准化模型名
    final modelLower = model.toLowerCase();
    
    // 尝试直接映射
    if (modelMapping.containsKey(modelLower)) {
      final category = modelMapping[modelLower]!;
      return defaultPricing[category]!;
    }
    
    // 启发式匹配
    if (modelLower.contains('opus')) {
      return defaultPricing['opus']!;
    } else if (modelLower.contains('haiku')) {
      return defaultPricing['haiku']!;
    }
    
    // 默认返回Sonnet定价
    return defaultPricing['sonnet']!;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎P90配置
// ═══════════════════════════════════════════════════════════════════════════

class P90Config {
  final List<int> commonLimits;      // 常用限制值 [44000, 88000, 220000]
  final double limitThreshold;       // 限制检测阈值 (0.9 = 90%)
  final int defaultMinLimit;         // 默认最小限制值
  final int cacheTtlSeconds;         // 缓存TTL秒数

  const P90Config({
    this.commonLimits = const [44000, 88000, 220000],
    this.limitThreshold = 0.9,
    this.defaultMinLimit = 44000,
    this.cacheTtlSeconds = 3600, // 1小时
  });

  /// 检查是否达到限制阈值
  bool didHitLimit(int tokens) {
    for (final limit in commonLimits) {
      if (tokens >= limit * limitThreshold) {
        return true;
      }
    }
    return false;
  }
}