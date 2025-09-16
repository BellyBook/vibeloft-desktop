/*
 * Purpose: Isolate后台数据处理器，在独立线程中执行繁重计算任务
 * Inputs: 原始JSONL数据、时间范围、计算参数
 * Outputs: 完全处理好的监控指标数据
 */

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../models/session_block.dart';
import '../models/burn_rate.dart';
import '../services/session_analyzer.dart';
import '../services/burn_rate_calculator.dart';
import '../services/p90_calculator.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎Isolate 数据处理结果
// ═══════════════════════════════════════════════════════════════════════════

class ProcessedMetrics {
  final List<SessionBlock> sessionBlocks;
  final List<Map<String, dynamic>> usageEntries;
  final double costUsage;
  final int tokenUsage;
  final int messagesUsage;
  final Duration timeToReset;
  final Map<String, ModelStats> modelDistribution;
  final BurnRate? burnRate;
  final double costRate;
  final DateTime? tokensWillRunOut;
  final DateTime? limitResetsAt;
  final int p90TokenLimit;
  final double p90CostLimit;
  final int p90MessageLimit;

  ProcessedMetrics({
    required this.sessionBlocks,
    required this.usageEntries,
    required this.costUsage,
    required this.tokenUsage,
    required this.messagesUsage,
    required this.timeToReset,
    required this.modelDistribution,
    required this.burnRate,
    required this.costRate,
    required this.tokensWillRunOut,
    required this.limitResetsAt,
    required this.p90TokenLimit,
    required this.p90CostLimit,
    required this.p90MessageLimit,
  });

  // 序列化为Map以便跨Isolate传输
  Map<String, dynamic> toMap() {
    return {
      'sessionBlocks': sessionBlocks.map((b) => b.toJson()).toList(),
      'usageEntries': usageEntries,
      'costUsage': costUsage,
      'tokenUsage': tokenUsage,
      'messagesUsage': messagesUsage,
      'timeToReset': timeToReset.inMilliseconds,
      'modelDistribution': modelDistribution.map((k, v) => MapEntry(k, v.toJson())),
      'burnRate': burnRate?.toJson(),
      'costRate': costRate,
      'tokensWillRunOut': tokensWillRunOut?.toIso8601String(),
      'limitResetsAt': limitResetsAt?.toIso8601String(),
      'p90TokenLimit': p90TokenLimit,
      'p90CostLimit': p90CostLimit,
      'p90MessageLimit': p90MessageLimit,
    };
  }

  // 从Map反序列化
  factory ProcessedMetrics.fromMap(Map<String, dynamic> map) {
    return ProcessedMetrics(
      sessionBlocks: (map['sessionBlocks'] as List)
          .map((b) => SessionBlock.fromJson(b))
          .toList(),
      usageEntries: List<Map<String, dynamic>>.from(map['usageEntries']),
      costUsage: map['costUsage'] as double,
      tokenUsage: map['tokenUsage'] as int,
      messagesUsage: map['messagesUsage'] as int,
      timeToReset: Duration(milliseconds: map['timeToReset'] as int),
      modelDistribution: (map['modelDistribution'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, ModelStats.fromJson(v))),
      burnRate: map['burnRate'] != null ? BurnRate.fromJson(map['burnRate']) : null,
      costRate: map['costRate'] as double,
      tokensWillRunOut: map['tokensWillRunOut'] != null 
          ? DateTime.parse(map['tokensWillRunOut']) : null,
      limitResetsAt: map['limitResetsAt'] != null 
          ? DateTime.parse(map['limitResetsAt']) : null,
      p90TokenLimit: map['p90TokenLimit'] as int,
      p90CostLimit: map['p90CostLimit'] as double,
      p90MessageLimit: map['p90MessageLimit'] as int,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎Isolate 处理参数
// ═══════════════════════════════════════════════════════════════════════════

class IsolateProcessParams {
  final DateTime startTime;
  final DateTime endTime;
  final List<String> dataPaths;

  IsolateProcessParams({
    required this.startTime,
    required this.endTime,
    required this.dataPaths,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎Isolate 数据处理器主类
// ═══════════════════════════════════════════════════════════════════════════

class IsolateDataProcessor {
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎使用 compute 函数执行后台处理（推荐方式）
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 在后台线程处理所有数据和计算
  static Future<ProcessedMetrics> processInBackground({
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    final params = IsolateProcessParams(
      startTime: startTime,
      endTime: endTime,
      dataPaths: [
        path.join(Platform.environment['HOME'] ?? '', '.claude', 'projects'),
        path.join(Platform.environment['HOME'] ?? '', '.config', 'claude', 'projects'),
      ],
    );

    // 使用 compute 在后台线程执行
    return await compute(_processDataInIsolate, params);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎Isolate 内部处理函数（静态，无外部依赖）
  // ─────────────────────────────────────────────────────────────────────────
  
  /// Isolate 执行函数 - 必须是顶级函数或静态方法
  static ProcessedMetrics _processDataInIsolate(IsolateProcessParams params) {
    // 1. 加载数据
    final usageEntries = _loadDataInIsolate(
      params.dataPaths,
      params.startTime,
      params.endTime,
    );

    // 2. 转换为会话块
    final analyzer = SessionAnalyzer();
    final sessionBlocks = analyzer.transformToBlocks(usageEntries);
    final activeBlocks = analyzer.getActiveBlocks(sessionBlocks);

    // 3. 计算P90限制（基于7天历史数据）
    // 用于准确的限制值计算，而使用量只取当前5小时活动块
    final p90Metrics = p90Calculator.calculateAllP90Metrics(sessionBlocks);
    final p90TokenLimit = p90Metrics['tokens']?.toInt() ?? 88000;
    final p90CostLimit = p90Metrics['cost'] ?? 5.0;
    final p90MessageLimit = p90Metrics['messages']?.toInt() ?? 100;
    
    // 4. 计算所有指标
    final costUsage = _calculateCostUsage(activeBlocks);
    final tokenUsage = _calculateTokenUsage(activeBlocks);
    final messagesUsage = _calculateMessagesUsage(activeBlocks);
    final timeToReset = _calculateTimeToReset(activeBlocks);
    final modelDistribution = _calculateModelDistribution(activeBlocks);
    final burnRate = burnRateCalculator.calculateHourlyBurnRate(sessionBlocks);
    final costRate = _calculateCostRate(activeBlocks);
    final tokensWillRunOut = _predictCostExhaustion(activeBlocks, p90CostLimit);
    final limitResetsAt = _calculateLimitResetsAt(activeBlocks);

    return ProcessedMetrics(
      sessionBlocks: sessionBlocks,
      usageEntries: usageEntries,
      costUsage: costUsage,
      tokenUsage: tokenUsage,
      messagesUsage: messagesUsage,
      timeToReset: timeToReset,
      modelDistribution: modelDistribution,
      burnRate: burnRate,
      costRate: costRate,
      tokensWillRunOut: tokensWillRunOut,
      limitResetsAt: limitResetsAt,
      p90TokenLimit: p90TokenLimit,
      p90CostLimit: p90CostLimit,
      p90MessageLimit: p90MessageLimit,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎数据加载（Isolate 内部版本）
  // ─────────────────────────────────────────────────────────────────────────
  
  static List<Map<String, dynamic>> _loadDataInIsolate(
    List<String> paths,
    DateTime startTime,
    DateTime endTime,
  ) {
    final allEntries = <Map<String, dynamic>>[];
    final processedHashes = <String>{};
    
    for (final basePath in paths) {
      final dir = Directory(basePath);
      if (!dir.existsSync()) continue;
      
      // 递归查找JSONL文件
      final jsonlFiles = _findJsonlFilesSync(dir);
      
      for (final file in jsonlFiles) {
        final entries = _loadJsonlFileSync(
          file,
          startTime: startTime,
          endTime: endTime,
          processedHashes: processedHashes,
        );
        allEntries.addAll(entries);
      }
    }
    
    // 按时间戳排序
    allEntries.sort((a, b) {
      final timeA = _parseTimestamp(a['timestamp']);
      final timeB = _parseTimestamp(b['timestamp']);
      if (timeA == null || timeB == null) return 0;
      return timeA.compareTo(timeB);
    });
    
    return allEntries;
  }

  static List<File> _findJsonlFilesSync(Directory dir) {
    final files = <File>[];
    try {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.jsonl')) {
          files.add(entity);
        }
      }
    } catch (e) {
      // 忽略错误
    }
    return files;
  }

  static List<Map<String, dynamic>> _loadJsonlFileSync(
    File file,
    {DateTime? startTime, DateTime? endTime, Set<String>? processedHashes}
  ) {
    if (!file.existsSync()) return [];
    
    final entries = <Map<String, dynamic>>[];
    try {
      final lines = file.readAsLinesSync();
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          if (json['type'] != 'assistant') continue;
          
          final message = json['message'] as Map<String, dynamic>?;
          if (message == null) continue;
          
          final usage = message['usage'] as Map<String, dynamic>?;
          if (usage == null) continue;
          
          final entry = _processJsonlEntry(json, message, usage);
          if (entry == null) continue;
          
          // 时间过滤
          final timestamp = _parseTimestamp(entry['timestamp']);
          if (timestamp != null) {
            if (startTime != null && timestamp.isBefore(startTime)) continue;
            if (endTime != null && timestamp.isAfter(endTime)) continue;
          }
          
          // 去重
          if (processedHashes != null) {
            final hash = _createUniqueHash(entry);
            if (hash != null && processedHashes.contains(hash)) continue;
            if (hash != null) processedHashes.add(hash);
          }
          
          entries.add(entry);
        } catch (e) {
          continue;
        }
      }
    } catch (e) {
      // 忽略错误
    }
    
    return entries;
  }

  static Map<String, dynamic>? _processJsonlEntry(
    Map<String, dynamic> json,
    Map<String, dynamic> message,
    Map<String, dynamic> usage,
  ) {
    // ═══════════════════════════════════════════════════════════════════════════
    // ▎Token提取逻辑 - 100%匹配Python参考实现的字段名兼容性
    // ▎参考: data_processors.py TokenExtractor.extract_tokens
    // ═══════════════════════════════════════════════════════════════════════════
    
    // 支持多种数据源优先级（匹配Python逻辑）
    final tokenSources = <Map<String, dynamic>>[
      usage,  // 主要数据源
      message,  // 备用数据源（包含usage字段时）
      json,     // 顶级字段兜底
    ];
    
    int inputTokens = 0;
    int outputTokens = 0;
    int cacheCreationTokens = 0;
    int cacheReadTokens = 0;
    
    // 按优先级查找token数据（匹配Python的多源查找逻辑）
    for (final source in tokenSources) {
      final extractedInputTokens = source['input_tokens'] as int? 
          ?? source['inputTokens'] as int? 
          ?? source['prompt_tokens'] as int? 
          ?? 0;
          
      final extractedOutputTokens = source['output_tokens'] as int? 
          ?? source['outputTokens'] as int? 
          ?? source['completion_tokens'] as int? 
          ?? 0;
          
      final extractedCacheCreation = source['cache_creation_tokens'] as int? 
          ?? source['cache_creation_input_tokens'] as int? 
          ?? source['cacheCreationInputTokens'] as int? 
          ?? 0;
          
      final extractedCacheRead = source['cache_read_input_tokens'] as int? 
          ?? source['cache_read_tokens'] as int? 
          ?? source['cacheReadInputTokens'] as int? 
          ?? 0;
      
      // 如果找到有效的token数据，使用该源（匹配Python break逻辑）
      if (extractedInputTokens > 0 || extractedOutputTokens > 0) {
        inputTokens = extractedInputTokens;
        outputTokens = extractedOutputTokens;
        cacheCreationTokens = extractedCacheCreation;
        cacheReadTokens = extractedCacheRead;
        break; // 找到有效数据源，停止查找
      }
    }
    
    if (inputTokens == 0 && outputTokens == 0 && 
        cacheCreationTokens == 0 && cacheReadTokens == 0) {
      return null;
    }
    
    return {
      'timestamp': json['timestamp'] ?? message['timestamp'] ?? 
                   DateTime.now().toUtc().toIso8601String(),
      'model': message['model'] as String? ?? 'unknown',
      'input_tokens': inputTokens,
      'output_tokens': outputTokens,
      'cache_creation_tokens': cacheCreationTokens,
      'cache_read_tokens': cacheReadTokens,
      'total_tokens': inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens,
      'message_id': message['id'] as String?,
      'request_id': (json['requestId'] ?? json['request_id'] ?? json['uuid']) as String?,
      'type': 'assistant',
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎指标计算方法（Isolate 内部版本）
  // ─────────────────────────────────────────────────────────────────────────
  
  static double _calculateCostUsage(List<SessionBlock> activeBlocks) {
    double totalCost = 0.0;
    for (final block in activeBlocks) {
      if (!block.isGap) {
        totalCost += block.costUsd;
      }
    }
    return (totalCost * 100).round() / 100;
  }

  static int _calculateTokenUsage(List<SessionBlock> activeBlocks) {
    int usageTokens = 0;
    for (final block in activeBlocks) {
      if (!block.isGap) {
        usageTokens += block.tokenCounts.usageTokens; // 使用 usageTokens 而不是 totalTokens
      }
    }
    return usageTokens;
  }

  static int _calculateMessagesUsage(List<SessionBlock> activeBlocks) {
    final uniqueMessages = <String>{};
    for (final block in activeBlocks) {
      if (!block.isGap) {
        uniqueMessages.addAll(block.messageIds);
      }
    }
    return uniqueMessages.length;
  }

  static Duration _calculateTimeToReset(List<SessionBlock> activeBlocks) {
    // 使用与 _calculateLimitResetsAt 相同的重置时间逻辑
    final resetTime = _calculateLimitResetsAt(activeBlocks);
    if (resetTime == null) return Duration.zero;

    final now = DateTime.now().toUtc();
    final remaining = resetTime.difference(now);

    return remaining.isNegative ? Duration.zero : remaining;
  }

  static Map<String, ModelStats> _calculateModelDistribution(
      List<SessionBlock> activeBlocks) {
    final modelStats = <String, ModelStats>{};
    double totalCost = 0.0;
    int totalUsageTokens = 0;

    for (final block in activeBlocks) {
      if (!block.isGap) {
        for (final entry in block.perModelStats.entries) {
          final model = entry.key;
          final stats = entry.value;

          if (!modelStats.containsKey(model)) {
            modelStats[model] = ModelStats(
              inputTokens: 0,
              outputTokens: 0,
              cacheCreationTokens: 0,
              cacheReadTokens: 0,
              costUsd: 0.0,
              entriesCount: 0,
            );
          }

          modelStats[model] = modelStats[model]! + stats;
          totalCost += stats.costUsd;
          totalUsageTokens += stats.usageTokens; // 使用 usageTokens
        }
      }
    }

    // 计算百分比
    final result = <String, ModelStats>{};
    for (final entry in modelStats.entries) {
      final stats = entry.value;
      result[entry.key] = ModelStats(
        inputTokens: stats.inputTokens,
        outputTokens: stats.outputTokens,
        cacheCreationTokens: stats.cacheCreationTokens,
        cacheReadTokens: stats.cacheReadTokens,
        costUsd: stats.costUsd,
        entriesCount: stats.entriesCount,
        percentageByCost: totalCost > 0 ? (stats.costUsd / totalCost) * 100 : 0,
        percentageByTokens:
            totalUsageTokens > 0 ? (stats.usageTokens / totalUsageTokens) * 100 : 0, // 使用 usageTokens
      );
    }

    return result;
  }

  static double _calculateCostRate(List<SessionBlock> activeBlocks) {
    double totalCostRate = 0.0;
    for (final block in activeBlocks) {
      if (block.isActive && !block.isGap && block.actualDurationMinutes >= 1.0) {
        final costPerHour = (block.costUsd / block.actualDurationMinutes) * 60;
        totalCostRate += costPerHour;
      }
    }
    return totalCostRate;
  }


  static DateTime? _predictCostExhaustion(
    List<SessionBlock> activeBlocks,
    double costLimit,
  ) {
    // ═══════════════════════════════════════════════════════════════════════════
    // ▎基于成本的预测算法 - 100%匹配Python实现
    // ═══════════════════════════════════════════════════════════════════════════
    
    // 找到当前活动的会话块
    final activeBlock = activeBlocks.firstWhere(
      (block) => block.isActive && !block.isGap,
      orElse: () => SessionBlock.createNew(timestamp: DateTime.now().toUtc()),
    );
    
    if (!activeBlock.isActive || activeBlock.isGap) {
      debugPrint('No active session - cost will not run out');
      return null; // 无活动会话
    }
    
    // 计算当前会话的成本消耗率（完全匹配Python的cost_per_minute逻辑）
    final elapsedMinutes = activeBlock.actualDurationMinutes;
    if (elapsedMinutes <= 0.0) {
      debugPrint('Session too short - cannot predict cost exhaustion');
      return null; // 会话时间太短，无法预测
    }
    
    final sessionCost = activeBlock.costUsd;
    final costPerMinute = sessionCost / elapsedMinutes; // 成本消耗率 (USD/min)
    
    if (costPerMinute <= 0) {
      debugPrint('No cost consumption detected - cost will not run out');
      return null; // 无成本消耗
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // ▎关键修正：使用当前会话成本而非总成本（与Python完全一致）
    // ═══════════════════════════════════════════════════════════════════════════
    final costRemaining = costLimit - sessionCost;  // Python: cost_limit - session_cost
    
    if (costRemaining <= 0) {
      debugPrint('Current session cost already exceeds limit');
      return DateTime.now().toUtc(); // 当前会话已超限
    }
    
    // ═══════════════════════════════════════════════════════════════════════════
    // ▎预测成本耗尽时间
    // ═══════════════════════════════════════════════════════════════════════════
    
    final minutesToCostDepletion = costRemaining / costPerMinute;
    
    // 防止过于远期的预测（超过24小时视为不可靠）
    if (minutesToCostDepletion > 24 * 60) {
      debugPrint('Cost prediction exceeds 24 hours - treating as never');
      return null;
    }
    
    final predictedEndTime = DateTime.now()
        .toUtc()
        .add(Duration(minutes: minutesToCostDepletion.ceil()));
    
    // ═══════════════════════════════════════════════════════════════════════════
    // ▎关键触发条件：与reset_time比较（匹配Python的run_out_condition逻辑）
    // ═══════════════════════════════════════════════════════════════════════════
    
    final resetTime = _calculateLimitResetsAt(activeBlocks);
    if (resetTime == null) {
      debugPrint('Cannot determine reset time - cost prediction unavailable');
      return null;
    }
    
    // 核心触发条件：predicted_end_time < reset_time（与Python完全一致）
    if (predictedEndTime.isBefore(resetTime)) {
      // ═══════════════════════════════════════════════════════════════════════════
      // ▎调试日志：成本预测计算详情（匹配Python格式）
      // ═══════════════════════════════════════════════════════════════════════════
      debugPrint('Cost-based prediction (matching Python algorithm):');
      debugPrint('  Session cost: \$${sessionCost.toStringAsFixed(4)}');
      debugPrint('  Session elapsed minutes: ${elapsedMinutes.toStringAsFixed(1)}');
      debugPrint('  Cost per minute: \$${costPerMinute.toStringAsFixed(6)}/min');
      debugPrint('  Cost limit: \$${costLimit.toStringAsFixed(2)}');
      debugPrint('  Cost remaining (limit - session): \$${costRemaining.toStringAsFixed(4)}');
      debugPrint('  Minutes until cost depletion: ${minutesToCostDepletion.toStringAsFixed(1)}');
      debugPrint('  Predicted exhaustion time: ${predictedEndTime.toIso8601String()}');
      debugPrint('  Reset time: ${resetTime.toIso8601String()}');
      debugPrint('  Trigger condition: predicted_end_time < reset_time = true');
      
      return predictedEndTime;
    } else {
      debugPrint('Cost will not run out before reset (${predictedEndTime.toIso8601String()} >= ${resetTime.toIso8601String()})');
      return null; // 不会在重置前耗尽，不显示警告
    }
  }

  static DateTime? _calculateLimitResetsAt(List<SessionBlock> activeBlocks) {
    final activeBlock = activeBlocks.firstWhere(
      (b) => b.isActive && !b.isGap,
      orElse: () => SessionBlock.createNew(timestamp: DateTime.now().toUtc()),
    );

    if (activeBlock.isActive) {
      // 有活动会话：直接使用会话块的固定结束时间（endTime）
      return activeBlock.endTime;
    } else {
      // 无活动会话：使用 start_time + 5小时 或 current_time + 5小时
      if (activeBlocks.isNotEmpty) {
        // 如果有会话历史，使用最近会话的开始时间 + 5小时
        final latestBlock = activeBlocks.first;
        return latestBlock.startTime.add(const Duration(hours: 5));
      } else {
        // 没有会话历史，使用当前时间 + 5小时
        return DateTime.now().toUtc().add(const Duration(hours: 5));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎辅助方法
  // ─────────────────────────────────────────────────────────────────────────
  
  static String? _createUniqueHash(Map<String, dynamic> entry) {
    final messageId = entry['message_id'] as String?;
    final requestId = entry['request_id'] as String?;
    
    if (messageId != null && requestId != null) {
      return '$messageId:$requestId';
    }
    return null;
  }

  static DateTime? _parseTimestamp(dynamic timestamp) {
    // ═══════════════════════════════════════════════════════════════════════════
    // ▎增强时间戳解析 - 100%匹配Python参考实现的时间格式支持
    // ▎参考: data_processors.py TimestampProcessor.parse_timestamp
    // ═══════════════════════════════════════════════════════════════════════════
    
    if (timestamp == null) return null;
    
    try {
      if (timestamp is DateTime) {
        return timestamp.toUtc();
      }
      
      if (timestamp is String) {
        // 处理Z结尾的时间格式（匹配Python逻辑）
        String timestampStr = timestamp;
        if (timestampStr.endsWith('Z')) {
          timestampStr = '${timestampStr.substring(0, timestampStr.length - 1)}+00:00';
        }
        
        // 尝试ISO格式解析（主要方法）
        try {
          return DateTime.parse(timestampStr).toUtc();
        } catch (_) {
          // 备用：尝试原始timestamp格式解析
          try {
            return DateTime.parse(timestamp).toUtc();
          } catch (_) {
            // 格式解析失败，继续下一步处理
          }
        }
      }
      
      if (timestamp is int || timestamp is double) {
        final timestampNum = timestamp is int ? timestamp : (timestamp as double).toInt();
        
        // 判断是毫秒还是秒级时间戳（匹配Python逻辑）
        if (timestampNum > 1000000000000) {
          return DateTime.fromMillisecondsSinceEpoch(timestampNum).toUtc();
        } else {
          return DateTime.fromMillisecondsSinceEpoch(timestampNum * 1000).toUtc();
        }
      }
    } catch (e) {
      // 静默处理异常，与Python行为一致
      debugPrint('Failed to parse timestamp "$timestamp": $e');
    }
    
    return null;
  }
}