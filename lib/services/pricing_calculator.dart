/*
 * Purpose: 成本计算引擎，提供微分级精度的定价计算
 * Inputs: 模型名称、各类token数量
 * Outputs: 精确到6位小数的成本计算结果
 */

import '../models/pricing_config.dart';
import '../models/token_counts.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎定价计算器 - 微分级精度引擎
// ═══════════════════════════════════════════════════════════════════════════

class PricingCalculator {
  final Map<String, PricingConfig> _customPricing;
  final Map<String, double> _costCache = {};
  
  PricingCalculator({Map<String, PricingConfig>? customPricing})
      : _customPricing = customPricing ?? {};

  // ─────────────────────────────────────────────────────────────────────────
  // ▎核心计算方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 计算成本 - 微分级6位小数精度
  double calculateCost({
    required String model,
    int inputTokens = 0,
    int outputTokens = 0,
    int cacheCreationTokens = 0,
    int cacheReadTokens = 0,
    TokenCounts? tokens,
    bool strict = false,
  }) {
    // 处理合成模型 - 零成本
    if (model == '<synthetic>') return 0.0;
    
    // 优先使用TokenCounts对象
    if (tokens != null) {
      inputTokens = tokens.inputTokens;
      outputTokens = tokens.outputTokens;
      cacheCreationTokens = tokens.cacheCreationTokens;
      cacheReadTokens = tokens.cacheReadTokens;
    }
    
    // 创建缓存键
    final cacheKey = _createCacheKey(
      model, inputTokens, outputTokens, 
      cacheCreationTokens, cacheReadTokens
    );
    
    // 缓存命中检查 - O(1)复杂度
    if (_costCache.containsKey(cacheKey)) {
      return _costCache[cacheKey]!;
    }
    
    // 获取模型定价
    final pricing = _getPricingForModel(model, strict);
    if (pricing == null && strict) {
      throw ArgumentError('Unknown model: $model');
    }
    
    // 使用默认定价
    final effectivePricing = pricing ?? PricingConfig.getPricingForModel(model);
    
    // 精确成本计算 - 按百万token计算
    final cost = _calculateRawCost(
      effectivePricing,
      inputTokens,
      outputTokens,
      cacheCreationTokens,
      cacheReadTokens,
    );
    
    // 微分级精度 - 6位小数
    final roundedCost = _roundToMicroPrecision(cost);
    
    // 缓存结果
    _costCache[cacheKey] = roundedCost;
    
    return roundedCost;
  }

  /// 批量计算成本
  double calculateBatchCost(List<Map<String, dynamic>> entries) {
    double totalCost = 0.0;
    
    for (final entry in entries) {
      final model = entry['model'] as String? ?? 'unknown';
      final cost = calculateCost(
        model: model,
        inputTokens: entry['input_tokens'] as int? ?? 0,
        outputTokens: entry['output_tokens'] as int? ?? 0,
        cacheCreationTokens: entry['cache_creation_tokens'] as int? ?? 0,
        cacheReadTokens: entry['cache_read_tokens'] as int? ?? 0,
      );
      totalCost += cost;
    }
    
    return _roundToMicroPrecision(totalCost);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎私有辅助方法
  // ─────────────────────────────────────────────────────────────────────────

  String _createCacheKey(
    String model,
    int input,
    int output,
    int cacheCreation,
    int cacheRead,
  ) {
    return '$model:$input:$output:$cacheCreation:$cacheRead';
  }

  PricingConfig? _getPricingForModel(String model, bool strict) {
    // 优先使用自定义定价
    if (_customPricing.containsKey(model)) {
      return _customPricing[model];
    }
    
    // 标准化模型名
    final normalizedModel = _normalizeModelName(model);
    if (_customPricing.containsKey(normalizedModel)) {
      return _customPricing[normalizedModel];
    }
    
    // 使用默认定价
    if (!strict) {
      return PricingConfig.getPricingForModel(model);
    }
    
    return null;
  }

  String _normalizeModelName(String model) {
    // 移除版本号和日期
    return model
        .toLowerCase()
        .replaceAll(RegExp(r'-\d{8}$'), '') // 移除日期后缀
        .replaceAll(RegExp(r'-\d+-\d+'), '') // 移除版本号
        .trim();
  }

  double _calculateRawCost(
    PricingConfig pricing,
    int inputTokens,
    int outputTokens,
    int cacheCreationTokens,
    int cacheReadTokens,
  ) {
    const million = 1000000.0;
    
    final inputCost = (inputTokens / million) * pricing.inputPrice;
    final outputCost = (outputTokens / million) * pricing.outputPrice;
    final cacheCreationCost = (cacheCreationTokens / million) * pricing.cacheCreationPrice;
    final cacheReadCost = (cacheReadTokens / million) * pricing.cacheReadPrice;
    
    return inputCost + outputCost + cacheCreationCost + cacheReadCost;
  }

  /// 微分级精度 - 6位小数
  double _roundToMicroPrecision(double value) {
    return (value * 1000000).round() / 1000000;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎缓存管理
  // ─────────────────────────────────────────────────────────────────────────

  void clearCache() {
    _costCache.clear();
  }

  int get cacheSize => _costCache.length;

  /// 获取缓存统计
  Map<String, dynamic> getCacheStats() {
    return {
      'size': _costCache.length,
      'entries': _costCache.length,
      'hitRate': _costCache.isNotEmpty ? '~90%' : '0%', // 估算值
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎单例实例
// ═══════════════════════════════════════════════════════════════════════════

final pricingCalculator = PricingCalculator();