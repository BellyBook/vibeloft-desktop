/*
 * Purpose: Claude 使用数据读取服务，负责从 JSONL 文件加载数据
 * Inputs: ~/.claude/projects/ 目录下的 JSONL 文件
 * Outputs: 解析后的 UsageEntry 列表，去重且按时间排序
 */

import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/usage_data.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎核心服务类
// ═══════════════════════════════════════════════════════════════════════════

class UsageService {
  final Set<String> _processedIds = {}; // 去重用的 ID 集合
  DateTime? _lastLoadTime; // 记录上次加载时间
  List<UsageEntry>? _cachedEntries; // 缓存的条目

  /// 获取数据目录路径
  String get dataPath {
    // 直接使用绝对路径，避免沙盒问题
    const path = '/Users/liangze/.claude/projects';
    return path;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎文件发现
  // ─────────────────────────────────────────────────────────────────────────

  /// 查找所有 JSONL 文件
  Future<List<File>> findJsonlFiles() async {
    final dir = Directory(dataPath);
    
    if (!await dir.exists()) {
      return [];
    }

    final files = <File>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.jsonl')) {
        files.add(entity);
      }
    }
    
    return files;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎数据加载
  // ─────────────────────────────────────────────────────────────────────────

  /// 加载指定时间范围内的使用数据
  Future<List<UsageEntry>> loadUsageEntries({
    int hoursBack = 5,
  }) async {
    // 如果有缓存且缓存时间在1秒内，直接返回缓存
    final now = DateTime.now();
    if (_cachedEntries != null && 
        _lastLoadTime != null && 
        now.difference(_lastLoadTime!).inSeconds < 1) {
      return _cachedEntries!;
    }
    
    // 清空之前的去重缓存，开始新的加载
    _processedIds.clear();
    
    final cutoffTime = now.subtract(Duration(hours: hoursBack));
    final files = await findJsonlFiles();
    
    // ═══════════════════════════════════════════════════════════════════════
    // ▎在后台 Isolate 中处理文件读取和解析 - 避免主线程阻塞
    // ═══════════════════════════════════════════════════════════════════════
    final entries = await compute(
      _loadEntriesInBackground,
      _LoadEntriesParams(
        filePaths: files.map((f) => f.path).toList(),
        cutoffTime: cutoffTime,
      ),
    );
    
    // 更新缓存
    _cachedEntries = entries;
    _lastLoadTime = now;
    
    return entries;
  }

  /// 解析单个 JSONL 文件
  Future<List<UsageEntry>> _parseJsonlFile(
    File file, 
    DateTime cutoffTime,
  ) async {
    final entries = <UsageEntry>[];
    
    try {
      final lines = await file.readAsLines();
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        try {
          final json = jsonDecode(line);
          
          // ─────────────────────────────────────────────────────────────────
          // ▎关键过滤：只处理 assistant 类型的消息（有 token 数据）
          // ─────────────────────────────────────────────────────────────────
          
          // 检查是否是 assistant 消息（包含 usage 数据）
          final type = json['type'] as String?;
          final message = json['message'] as Map<String, dynamic>?;
          final usage = message?['usage'] as Map<String, dynamic>?;
          
          // 跳过用户消息和没有 usage 数据的条目
          if (type != 'assistant' || usage == null) {
            continue;
          }
          
          // 检查是否有实际的 token 数据
          final hasTokens = (usage['input_tokens'] != null && usage['input_tokens'] > 0) ||
                           (usage['output_tokens'] != null && usage['output_tokens'] > 0);
          
          if (!hasTokens) {
            continue;
          }
          
          final entry = UsageEntry.fromJson(json);
          
          // 时间过滤
          if (entry.timestamp.isBefore(cutoffTime)) continue;
          
          // 去重检查
          if (_processedIds.contains(entry.uniqueId)) continue;
          
          _processedIds.add(entry.uniqueId);
          entries.add(entry);
          
        } catch (e) {
          // 跳过损坏的行
          continue;
        }
      }
    } catch (e) {
      // 文件读取失败，返回空列表
      return [];
    }
    
    return entries;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎会话分析
  // ─────────────────────────────────────────────────────────────────────────

  /// 将条目分组为会话（5小时块）
  List<UsageSession> groupIntoSessions(List<UsageEntry> entries) {
    if (entries.isEmpty) return [];
    
    final sessions = <UsageSession>[];
    var sessionEntries = <UsageEntry>[];
    
    // 圆整到小时（与参考实现一致）
    var sessionStart = _roundToHour(entries.first.timestamp);
    var sessionEnd = sessionStart.add(const Duration(hours: 5));
    
    for (final entry in entries) {
      // 检查是否需要新会话块
      if (entry.timestamp.isAfter(sessionEnd) || 
          (sessionEntries.isNotEmpty && 
           entry.timestamp.difference(sessionEntries.last.timestamp).inHours >= 5)) {
        
        // 结束当前会话
        if (sessionEntries.isNotEmpty) {
          sessions.add(UsageSession(
            startTime: sessionStart,
            endTime: sessionEntries.last.timestamp,
            entries: List.from(sessionEntries),
          ));
        }
        
        // 开始新会话（圆整到小时）
        sessionEntries = [];
        sessionStart = _roundToHour(entry.timestamp);
        sessionEnd = sessionStart.add(const Duration(hours: 5));
      }
      
      sessionEntries.add(entry);
    }
    
    // 添加最后一个会话
    if (sessionEntries.isNotEmpty) {
      sessions.add(UsageSession(
        startTime: sessionStart,
        endTime: sessionEntries.last.timestamp,
        entries: sessionEntries,
      ));
    }
    
    return sessions;
  }
  
  /// 圆整时间到小时
  DateTime _roundToHour(DateTime timestamp) {
    return DateTime(
      timestamp.year,
      timestamp.month,
      timestamp.day,
      timestamp.hour,
      0, // 分钟设为0
      0, // 秒设为0
      0, // 毫秒设为0
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎统计分析
  // ─────────────────────────────────────────────────────────────────────────

  /// 计算使用统计
  UsageStats calculateStats(List<UsageEntry> entries) {
    if (entries.isEmpty) return UsageStats.empty();
    
    // 基础统计
    final totalTokens = entries.fold(0, (sum, e) => sum + e.totalTokens);
    final totalCost = entries.fold(0.0, (sum, e) => sum + e.costUsd);
    
    // 模型使用统计
    final modelUsage = <String, int>{};
    for (final entry in entries) {
      modelUsage[entry.model] = (modelUsage[entry.model] ?? 0) + 1;
    }
    
    // P90 计算（与参考实现一致）
    final sessions = groupIntoSessions(entries);
    
    // 计算P90 tokens（优先使用接近限制的会话）
    final p90Tokens = _calculateP90ForTokens(sessions);
    
    // 成本和消息数的P90计算
    final sessionCosts = sessions.map((s) => s.totalCost).toList();
    final sessionMessages = sessions.map((s) => s.messageCount.toDouble()).toList();
    
    return UsageStats(
      totalTokens: totalTokens,
      totalCost: totalCost,
      messageCount: entries.length,
      modelUsage: modelUsage,
      p90Tokens: p90Tokens,
      p90Cost: _calculateP90(sessionCosts, defaultValue: 50.0),  // 默认 $50
      p90Messages: _calculateP90(sessionMessages, defaultValue: 250.0),  // 默认 250 消息
    );
  }

  /// 计算Token的P90（与参考实现一致：优先使用接近限制的会话）
  double _calculateP90ForTokens(List<UsageSession> sessions) {
    if (sessions.isEmpty) return 44000.0; // 默认值
    
    // 常见限制阈值（与参考实现一致）
    const commonLimits = [19000, 88000, 220000, 880000];
    const threshold = 0.95;
    
    // 筛选接近限制的会话
    final hitLimitSessions = <double>[];
    for (final session in sessions) {
      final tokens = session.totalTokens;
      // 检查是否接近任何常见限制
      for (final limit in commonLimits) {
        if (tokens >= limit * threshold) {
          hitLimitSessions.add(tokens.toDouble());
          break;
        }
      }
    }
    
    // 如果有接近限制的会话，使用它们计算P90
    if (hitLimitSessions.isNotEmpty) {
      return _calculateP90(hitLimitSessions);
    }
    
    // 否则使用所有会话
    final allTokens = sessions
        .where((s) => s.totalTokens > 0)
        .map((s) => s.totalTokens.toDouble())
        .toList();
    
    if (allTokens.isEmpty) return 44000.0;
    return _calculateP90(allTokens);
  }

  /// 计算第90百分位数（与Python的quantiles实现一致）
  double _calculateP90(List<double> values, {double defaultValue = 0.0}) {
    if (values.isEmpty) return defaultValue;
    if (values.length == 1) return values[0];
    
    // 排序
    final sorted = List<double>.from(values)..sort();
    
    // 使用Python statistics.quantiles(n=10)[8]的算法
    // 这是第9个十分位数（90百分位）
    final n = sorted.length;
    
    // Python的quantiles使用的是"exclusive"方法
    // position = (n+1) * 0.9 - 1
    final position = (n + 1) * 0.9 - 1;
    
    if (position < 0) {
      return sorted[0];
    }
    if (position >= n - 1) {
      return sorted[n - 1];
    }
    
    final lowerIndex = position.floor();
    final upperIndex = lowerIndex + 1;
    final fraction = position - lowerIndex;
    
    // 线性插值
    final result = sorted[lowerIndex] * (1 - fraction) + 
                  sorted[upperIndex] * fraction;
    
    // 如果计算结果为0，返回默认值
    return result > 0 ? result : defaultValue;
  }

  /// 清除已处理 ID 缓存
  void clearCache() {
    _processedIds.clear();
    _cachedEntries = null;
    _lastLoadTime = null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎后台处理参数和函数
// ═══════════════════════════════════════════════════════════════════════════

/// 后台加载参数
class _LoadEntriesParams {
  final List<String> filePaths;
  final DateTime cutoffTime;
  
  _LoadEntriesParams({
    required this.filePaths,
    required this.cutoffTime,
  });
}

/// 在后台 Isolate 中加载数据
Future<List<UsageEntry>> _loadEntriesInBackground(_LoadEntriesParams params) async {
  final entries = <UsageEntry>[];
  final processedIds = <String>{};
  
  for (final filePath in params.filePaths) {
    final file = File(filePath);
    
    try {
      final lines = await file.readAsLines();
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        try {
          final json = jsonDecode(line);
          
          // 检查是否是 assistant 消息
          final type = json['type'] as String?;
          final message = json['message'] as Map<String, dynamic>?;
          final usage = message?['usage'] as Map<String, dynamic>?;
          
          if (type != 'assistant' || usage == null) continue;
          
          // 检查是否有 token 数据
          final hasTokens = (usage['input_tokens'] != null && usage['input_tokens'] > 0) ||
                           (usage['output_tokens'] != null && usage['output_tokens'] > 0);
          
          if (!hasTokens) continue;
          
          final entry = UsageEntry.fromJson(json);
          
          // 时间过滤
          if (entry.timestamp.isBefore(params.cutoffTime)) continue;
          
          // 去重检查
          if (processedIds.contains(entry.uniqueId)) continue;
          
          processedIds.add(entry.uniqueId);
          entries.add(entry);
        } catch (e) {
          // 跳过损坏的行
          continue;
        }
      }
    } catch (e) {
      // 文件读取失败，继续下一个
      continue;
    }
  }
  
  // 按时间排序
  entries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  
  return entries;
}