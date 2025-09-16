/*
 * Purpose: P90自适应限制算法，基于历史数据动态计算限制阈值
 * Inputs: 会话块历史数据、配置参数
 * Outputs: P90限制值、自适应阈值
 */

import 'dart:math' as math;
import '../models/session_block.dart';
import '../models/pricing_config.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎P90计算器 - 统计学习引擎
// ═══════════════════════════════════════════════════════════════════════════

class P90Calculator {
  final P90Config _config;
  final Map<String, double> _cache = {};
  DateTime? _lastCacheTime;
  
  P90Calculator({P90Config? config})
      : _config = config ?? const P90Config();

  // ─────────────────────────────────────────────────────────────────────────
  // ▎核心P90计算
  // ─────────────────────────────────────────────────────────────────────────

  /// 计算P90限制值
  int calculateP90Limit(List<SessionBlock> blocks, {bool useCache = true}) {
    if (blocks.isEmpty) {
      return _config.defaultMinLimit;
    }
    
    // 缓存检查
    if (useCache && _isCacheValid()) {
      final cached = _cache['p90_limit'];
      if (cached != null) {
        return cached.toInt();
      }
    }
    
    // 执行计算
    final p90 = _calculateP90FromBlocks(blocks);
    
    // 更新缓存
    if (useCache) {
      _updateCache('p90_limit', p90.toDouble());
    }
    
    return p90;
  }

  /// 计算所有指标的P90值
  Map<String, double> calculateAllP90Metrics(List<SessionBlock> blocks) {
    if (blocks.isEmpty) {
      return {
        'tokens': _config.defaultMinLimit.toDouble(),
        'cost': 5.0, // 默认成本限制
        'messages': 100.0, // 默认消息限制
      };
    }
    
    // 缓存检查
    if (_isCacheValid()) {
      final cachedTokens = _cache['p90_tokens'];
      final cachedCost = _cache['p90_cost'];
      final cachedMessages = _cache['p90_messages'];
      
      if (cachedTokens != null && cachedCost != null && cachedMessages != null) {
        return {
          'tokens': cachedTokens,
          'cost': cachedCost,
          'messages': cachedMessages,
        };
      }
    }
    
    // 提取数据
    final tokensList = <int>[];
    final costList = <double>[];
    final messagesList = <int>[];
    
    for (final block in blocks) {
      if (!block.isGap && !block.isActive) {
        tokensList.add(block.totalTokens);
        costList.add(block.costUsd);
        messagesList.add(block.sentMessagesCount);
      }
    }
    
    // 计算P90
    final p90Tokens = _calculateP90(tokensList.map((t) => t.toDouble()).toList());
    final p90Cost = _calculateP90(costList);
    final p90Messages = _calculateP90(messagesList.map((m) => m.toDouble()).toList());
    
    // 更新缓存
    _updateCache('p90_tokens', p90Tokens);
    _updateCache('p90_cost', p90Cost);
    _updateCache('p90_messages', p90Messages);
    
    return {
      'tokens': p90Tokens,
      'cost': p90Cost,
      'messages': p90Messages,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎私有计算方法
  // ─────────────────────────────────────────────────────────────────────────

  int _calculateP90FromBlocks(List<SessionBlock> blocks) {
    // 第一优先级：提取达到限制阈值的完成会话
    var hits = _extractSessions(blocks, (block) {
      return !block.isGap &&
             !block.isActive &&
             _config.didHitLimit(block.totalTokens);
    });
    
    // 第二优先级：如果没有达到限制的会话，使用所有完成的会话
    if (hits.isEmpty) {
      hits = _extractSessions(blocks, (block) {
        return !block.isGap && !block.isActive;
      });
    }
    
    // 安全后备：如果仍无数据，返回默认最小限制
    if (hits.isEmpty) {
      return _config.defaultMinLimit;
    }
    
    // 计算第90百分位数
    final p90 = _calculateP90(hits.map((h) => h.toDouble()).toList());
    
    // 确保结果不低于配置的最小限制
    return math.max(p90.toInt(), _config.defaultMinLimit);
  }

  List<int> _extractSessions(List<SessionBlock> blocks, bool Function(SessionBlock) filter) {
    final sessions = <int>[];
    
    for (final block in blocks) {
      if (filter(block) && block.totalTokens > 0) {
        sessions.add(block.totalTokens);
      }
    }
    
    return sessions;
  }

  double _calculateP90(List<double> values) {
    if (values.isEmpty) {
      return _config.defaultMinLimit.toDouble();
    }
    
    if (values.length == 1) {
      return values.first;
    }
    
    // 排序
    final sorted = List<double>.from(values)..sort();
    
    // 计算P90位置
    final index = (sorted.length * 0.9).floor();
    
    // 如果恰好在某个位置
    if (index == sorted.length * 0.9) {
      return sorted[index.clamp(0, sorted.length - 1)];
    }
    
    // 线性插值
    final lowerIndex = index.clamp(0, sorted.length - 1);
    final upperIndex = (index + 1).clamp(0, sorted.length - 1);
    
    if (lowerIndex == upperIndex) {
      return sorted[lowerIndex];
    }
    
    final lowerValue = sorted[lowerIndex];
    final upperValue = sorted[upperIndex];
    final fraction = (sorted.length * 0.9) - index;
    
    return lowerValue + (upperValue - lowerValue) * fraction;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎缓存管理
  // ─────────────────────────────────────────────────────────────────────────

  bool _isCacheValid() {
    if (_lastCacheTime == null) return false;
    
    final now = DateTime.now().toUtc();
    final elapsed = now.difference(_lastCacheTime!);
    
    return elapsed.inSeconds < _config.cacheTtlSeconds;
  }

  void _updateCache(String key, double value) {
    _cache[key] = value;
    _lastCacheTime = DateTime.now().toUtc();
  }

  void clearCache() {
    _cache.clear();
    _lastCacheTime = null;
  }

  Map<String, dynamic> getCacheStats() {
    return {
      'size': _cache.length,
      'isValid': _isCacheValid(),
      'lastUpdate': _lastCacheTime?.toIso8601String(),
      'ttlSeconds': _config.cacheTtlSeconds,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎动态限制调整
  // ─────────────────────────────────────────────────────────────────────────

  /// 基于当前使用情况获取建议限制
  int getSuggestedLimit(int currentUsage, List<SessionBlock> blocks) {
    final p90 = calculateP90Limit(blocks);
    
    // 如果当前使用已超过P90的80%，建议提高限制
    if (currentUsage > p90 * 0.8) {
      // 寻找下一个常用限制值
      for (final limit in _config.commonLimits) {
        if (limit > p90) {
          return limit;
        }
      }
      // 如果没有更高的常用限制，返回当前P90的120%
      return (p90 * 1.2).toInt();
    }
    
    return p90;
  }

  /// 检查是否接近限制
  bool isApproachingLimit(int currentUsage, int limit) {
    return currentUsage >= limit * 0.8;
  }

  /// 获取限制状态
  String getLimitStatus(int currentUsage, int limit) {
    final percentage = (currentUsage / limit) * 100;
    
    if (percentage >= 100) {
      return 'exceeded';
    } else if (percentage >= 90) {
      return 'critical';
    } else if (percentage >= 80) {
      return 'warning';
    } else if (percentage >= 60) {
      return 'moderate';
    } else {
      return 'normal';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎单例实例
// ═══════════════════════════════════════════════════════════════════════════

final p90Calculator = P90Calculator();