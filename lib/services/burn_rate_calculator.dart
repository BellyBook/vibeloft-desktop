/*
 * Purpose: 燃烧率计算器，实现滑动窗口的Token和成本消耗率计算
 * Inputs: 会话块列表、时间范围
 * Outputs: 实时燃烧率、成本率、预测信息
 */

import '../models/session_block.dart';
import '../models/burn_rate.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎燃烧率计算器 - 滑动窗口算法
// ═══════════════════════════════════════════════════════════════════════════

class BurnRateCalculator {
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎核心计算方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 计算小时燃烧率（最近1小时）- 滑动窗口算法
  BurnRate? calculateHourlyBurnRate(List<SessionBlock> blocks, {DateTime? currentTime}) {
    currentTime ??= DateTime.now().toUtc();
    final oneHourAgo = currentTime.subtract(const Duration(hours: 1));
    
    // 使用时间比例分配计算精确的token和成本
    final totalTokens = _calculateTotalTokensInHour(blocks, oneHourAgo, currentTime);
    final totalCost = _calculateTotalCostInHour(blocks, oneHourAgo, currentTime);
    
    if (totalTokens == 0) {
      return null;
    }
    
    return BurnRate(
      tokensPerMinute: totalTokens / 60.0,
      costPerHour: totalCost,
      calculatedAt: currentTime,
    );
  }

  /// 计算会话块的燃烧率
  BurnRate? calculateBlockBurnRate(SessionBlock block) {
    if (!block.isActive || block.isGap) {
      return null;
    }
    
    final durationMinutes = block.actualDurationMinutes;
    if (durationMinutes < 1.0) {
      return null;
    }
    
    final totalTokens = block.totalTokens;
    if (totalTokens == 0) {
      return null;
    }
    
    final tokensPerMinute = totalTokens / durationMinutes;
    final costPerHour = (block.costUsd / durationMinutes) * 60;
    
    return BurnRate(
      tokensPerMinute: tokensPerMinute,
      costPerHour: costPerHour,
      calculatedAt: DateTime.now().toUtc(),
    );
  }

  /// 计算总燃烧率（所有活动块）
  BurnRate? calculateTotalBurnRate(List<SessionBlock> blocks) {
    final activeBlocks = blocks.where((b) => b.isActive && !b.isGap).toList();
    if (activeBlocks.isEmpty) return null;
    
    double totalTokensPerMinute = 0.0;
    double totalCostPerHour = 0.0;
    
    for (final block in activeBlocks) {
      final blockBurnRate = calculateBlockBurnRate(block);
      if (blockBurnRate != null) {
        totalTokensPerMinute += blockBurnRate.tokensPerMinute;
        totalCostPerHour += blockBurnRate.costPerHour;
      }
    }
    
    if (totalTokensPerMinute == 0) return null;
    
    return BurnRate(
      tokensPerMinute: totalTokensPerMinute,
      costPerHour: totalCostPerHour,
      calculatedAt: DateTime.now().toUtc(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎预测方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 预测Token耗尽时间
  DateTime? predictTokenExhaustion({
    required int currentTokens,
    required int tokenLimit,
    required BurnRate burnRate,
  }) {
    if (burnRate.tokensPerMinute <= 0) return null;
    
    final remainingTokens = tokenLimit - currentTokens;
    if (remainingTokens <= 0) return DateTime.now().toUtc();
    
    final minutesUntilExhaustion = remainingTokens / burnRate.tokensPerMinute;
    
    return DateTime.now()
        .toUtc()
        .add(Duration(minutes: minutesUntilExhaustion.ceil()));
  }

  /// 预测成本限制到达时间
  DateTime? predictCostLimit({
    required double currentCost,
    required double costLimit,
    required BurnRate burnRate,
  }) {
    if (burnRate.costPerHour <= 0) return null;
    
    final remainingCost = costLimit - currentCost;
    if (remainingCost <= 0) return DateTime.now().toUtc();
    
    final hoursUntilLimit = remainingCost / burnRate.costPerHour;
    final minutes = (hoursUntilLimit * 60).ceil();
    
    return DateTime.now()
        .toUtc()
        .add(Duration(minutes: minutes));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎私有辅助方法
  // ─────────────────────────────────────────────────────────────────────────

  double _calculateTotalTokensInHour(
    List<SessionBlock> blocks,
    DateTime oneHourAgo,
    DateTime currentTime,
  ) {
    double totalTokens = 0.0;
    
    for (final block in blocks) {
      if (block.isGap) continue;
      
      final tokens = _processBlockForBurnRate(
        block,
        oneHourAgo,
        currentTime,
        (b) => b.totalTokens.toDouble(),
      );
      
      totalTokens += tokens;
    }
    
    return totalTokens;
  }

  double _calculateTotalCostInHour(
    List<SessionBlock> blocks,
    DateTime oneHourAgo,
    DateTime currentTime,
  ) {
    double totalCost = 0.0;
    
    for (final block in blocks) {
      if (block.isGap) continue;
      
      final cost = _processBlockForBurnRate(
        block,
        oneHourAgo,
        currentTime,
        (b) => b.costUsd,
      );
      
      totalCost += cost;
    }
    
    return totalCost;
  }

  double _processBlockForBurnRate(
    SessionBlock block,
    DateTime oneHourAgo,
    DateTime currentTime,
    double Function(SessionBlock) getValue,
  ) {
    // 确定会话实际结束时间
    final sessionActualEnd = block.isActive 
        ? currentTime 
        : (block.actualEndTime ?? block.endTime);
    
    // 如果会话完全在1小时前结束，不计入
    if (sessionActualEnd.isBefore(oneHourAgo) || 
        sessionActualEnd.isAtSameMomentAs(oneHourAgo)) {
      return 0.0;
    }
    
    // 如果会话完全在1小时窗口后开始，不计入
    if (block.startTime.isAfter(currentTime) || 
        block.startTime.isAtSameMomentAs(currentTime)) {
      return 0.0;
    }
    
    // 计算会话在最近1小时内的时间段
    final sessionStartInHour = _maxDateTime(block.startTime, oneHourAgo);
    final sessionEndInHour = _minDateTime(sessionActualEnd, currentTime);
    
    if (sessionEndInHour.isBefore(sessionStartInHour) || 
        sessionEndInHour.isAtSameMomentAs(sessionStartInHour)) {
      return 0.0;
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // ▎修复时间精度：使用毫秒级精度（与Python实现的秒级精度对齐）
    // ═══════════════════════════════════════════════════════════════════════════
    final totalSessionDuration = sessionActualEnd
        .difference(block.startTime)
        .inMilliseconds
        .toDouble() / (1000 * 60); // 转换为精确分钟
    final hourDuration = sessionEndInHour
        .difference(sessionStartInHour)
        .inMilliseconds
        .toDouble() / (1000 * 60); // 转换为精确分钟
    
    if (totalSessionDuration <= 0) return 0.0;
    
    final value = getValue(block);
    return value * (hourDuration / totalSessionDuration);
  }

  DateTime _maxDateTime(DateTime a, DateTime b) {
    return a.isAfter(b) ? a : b;
  }

  DateTime _minDateTime(DateTime a, DateTime b) {
    return a.isBefore(b) ? a : b;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎格式化辅助
  // ─────────────────────────────────────────────────────────────────────────

  /// 格式化预测时间
  String formatPrediction(DateTime? prediction) {
    if (prediction == null) {
      return 'Never (no active usage)';
    }
    
    final now = DateTime.now().toUtc();
    if (prediction.isBefore(now) || prediction.isAtSameMomentAs(now)) {
      return 'Already exceeded';
    }
    
    final duration = prediction.difference(now);
    
    if (duration.inDays > 0) {
      final days = duration.inDays;
      final hours = duration.inHours % 24;
      return '${days}d ${hours}h';
    } else if (duration.inHours > 0) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      return '${hours}h ${minutes}m';
    } else {
      return '${duration.inMinutes}m';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎单例实例
// ═══════════════════════════════════════════════════════════════════════════

final burnRateCalculator = BurnRateCalculator();