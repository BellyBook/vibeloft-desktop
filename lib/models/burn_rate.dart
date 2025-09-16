/*
 * Purpose: 燃烧率模型，追踪Token和成本的消耗速率
 * Inputs: Token消耗速率、成本消耗速率
 * Outputs: 实时燃烧率指标
 */

// ═══════════════════════════════════════════════════════════════════════════
// ▎燃烧率模型
// ═══════════════════════════════════════════════════════════════════════════

class BurnRate {
  final double tokensPerMinute; // Token每分钟消耗
  final double costPerHour; // 成本每小时消耗（美元）
  final DateTime calculatedAt; // 计算时间

  const BurnRate({
    required this.tokensPerMinute,
    required this.costPerHour,
    required this.calculatedAt,
  });

  // ─────────────────────────────────────────────────────────────────────────
  // ▎衍生指标
  // ─────────────────────────────────────────────────────────────────────────

  /// Token每小时消耗
  double get tokensPerHour => tokensPerMinute * 60;

  /// 成本每分钟消耗
  double get costPerMinute => costPerHour / 60;

  /// 是否高燃烧率（超过1000 tokens/分钟）
  bool get isHighBurnRate => tokensPerMinute > 1000;

  /// 是否极高燃烧率（超过5000 tokens/分钟）
  bool get isCriticalBurnRate => tokensPerMinute > 5000;

  // ─────────────────────────────────────────────────────────────────────────
  // ▎预测方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 预测到达指定Token数的时间
  Duration? timeToReachTokens(int currentTokens, int targetTokens) {
    if (tokensPerMinute <= 0) return null;
    if (currentTokens >= targetTokens) return Duration.zero;

    final remainingTokens = targetTokens - currentTokens;
    final minutes = remainingTokens / tokensPerMinute;

    return Duration(minutes: minutes.ceil());
  }

  /// 预测到达指定成本的时间
  Duration? timeToReachCost(double currentCost, double targetCost) {
    if (costPerHour <= 0) return null;
    if (currentCost >= targetCost) return Duration.zero;

    final remainingCost = targetCost - currentCost;
    final hours = remainingCost / costPerHour;

    return Duration(hours: hours.floor(), minutes: ((hours % 1) * 60).round());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎格式化显示
  // ─────────────────────────────────────────────────────────────────────────

  /// 格式化燃烧率显示
  String formatBurnRate() {
    if (tokensPerMinute < 1) {
      return '< 1 token/分钟';
    } else if (tokensPerMinute >= 1000000) {
      // 百万级别，显示为 M
      return '${(tokensPerMinute / 1000000).toStringAsFixed(1)}M tokens/分钟';
    } else if (tokensPerMinute >= 1000) {
      // 千级别，显示为 k
      return '${(tokensPerMinute / 1000).toStringAsFixed(1)}k tokens/分钟';
    } else if (tokensPerMinute < 100) {
      return '${tokensPerMinute.toStringAsFixed(1)} tokens/分钟';
    } else {
      return '${tokensPerMinute.round()} tokens/分钟';
    }
  }

  /// 格式化成本率显示
  String formatCostRate() {
    if (costPerHour < 0.01) {
      return '< \$0.01/分钟';
    } else if (costPerHour < 1) {
      return '\$${costPerHour.toStringAsFixed(3)}/hr';
    } else {
      return '\$${costPerHour.toStringAsFixed(2)}/hr';
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎序列化方法
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() {
    return {
      'tokensPerMinute': tokensPerMinute,
      'costPerHour': costPerHour,
      'calculatedAt': calculatedAt.toIso8601String(),
    };
  }

  factory BurnRate.fromJson(Map<String, dynamic> json) {
    return BurnRate(
      tokensPerMinute: json['tokensPerMinute'],
      costPerHour: json['costPerHour'],
      calculatedAt: DateTime.parse(json['calculatedAt']),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎限制信息
// ═══════════════════════════════════════════════════════════════════════════

class LimitInfo {
  final String type; // 限制类型：opus_limit, system_limit, general_limit
  final DateTime timestamp; // 触发时间
  final String content; // 限制消息内容
  final DateTime? resetTime; // 重置时间
  final int? waitMinutes; // 等待分钟数

  const LimitInfo({
    required this.type,
    required this.timestamp,
    required this.content,
    this.resetTime,
    this.waitMinutes,
  });

  bool get isOpusLimit => type == 'opus_limit';
  bool get isSystemLimit => type == 'system_limit';
  bool get isGeneralLimit => type == 'general_limit';
}
