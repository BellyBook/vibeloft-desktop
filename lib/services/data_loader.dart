/*
 * Purpose: JSONL数据读取器，从Chrome扩展数据文件加载真实使用数据
 * Inputs: JSONL文件路径、时间范围
 * Outputs: 标准化的使用条目列表
 */

import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;

// ═══════════════════════════════════════════════════════════════════════════
// ▎数据加载器 - Chrome扩展JSONL文件读取
// ═══════════════════════════════════════════════════════════════════════════

class DataLoader {
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎配置常量
  // ─────────────────────────────────────────────────────────────────────────
  
  static final List<String> _defaultDataPaths = [
    path.join(Platform.environment['HOME'] ?? '', '.claude', 'projects'),
    path.join(Platform.environment['HOME'] ?? '', '.config', 'claude', 'projects'),
  ];
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎核心加载方法
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 从Claude数据目录加载所有JSONL文件
  static Future<List<Map<String, dynamic>>> loadAllData({
    List<String>? customPaths,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final paths = customPaths ?? _defaultDataPaths;
    final allEntries = <Map<String, dynamic>>[];
    
    // 维护已处理的唯一hash集合，避免重复条目
    final processedHashes = <String>{};
    int duplicatesSkipped = 0;
    
    for (final basePath in paths) {
      final dir = Directory(basePath);
      if (!await dir.exists()) {
        continue;
      }
      
      // 递归查找所有JSONL文件
      final jsonlFiles = await _findJsonlFiles(dir);
      
      for (final file in jsonlFiles) {
        final result = await loadJsonlFile(
          file.path,
          startTime: startTime,
          endTime: endTime,
          processedHashes: processedHashes,
        );
        allEntries.addAll(result['entries'] as List<Map<String, dynamic>>);
        duplicatesSkipped += result['duplicates'] as int;
      }
    }
    
    // 按时间戳排序
    allEntries.sort((a, b) {
      final timeA = _parseTimestamp(a['timestamp']);
      final timeB = _parseTimestamp(b['timestamp']);
      if (timeA == null || timeB == null) return 0;
      return timeA.compareTo(timeB);
    });
    
    print('DataLoader: Loaded ${allEntries.length} unique entries, skipped $duplicatesSkipped duplicates');
    print('DataLoader: processedHashes contains ${processedHashes.length} unique hashes');
    
    return allEntries;
  }
  
  /// 加载单个JSONL文件
  static Future<Map<String, dynamic>> loadJsonlFile(
    String filePath, {
    DateTime? startTime,
    DateTime? endTime,
    Set<String>? processedHashes,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return {'entries': [], 'duplicates': 0};
    }
    
    final entries = <Map<String, dynamic>>[];
    int duplicatesInFile = 0;
    
    try {
      final lines = await file.readAsLines();
      
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          final entry = _processJsonlEntry(json);
          
          if (entry != null) {
            // 时间范围过滤
            if (startTime != null || endTime != null) {
              final timestamp = _parseTimestamp(entry['timestamp']);
              if (timestamp != null) {
                if (startTime != null && timestamp.isBefore(startTime)) {
                  continue;
                }
                if (endTime != null && timestamp.isAfter(endTime)) {
                  continue;
                }
              }
            }
            
            // 去重检查：生成唯一hash
            if (processedHashes != null) {
              final uniqueHash = _createUniqueHash(entry);
              if (uniqueHash != null && processedHashes.contains(uniqueHash)) {
                // 已处理过的条目，跳过
                duplicatesInFile++;
                continue;
              }
              if (uniqueHash != null) {
                processedHashes.add(uniqueHash);
              }
            }
            
            entries.add(entry);
          }
        } catch (e) {
          // 跳过无法解析的行
          continue;
        }
      }
    } catch (e) {
      // 文件读取失败
      return {'entries': [], 'duplicates': 0};
    }
    
    return {'entries': entries, 'duplicates': duplicatesInFile};
  }
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎数据处理方法
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 处理JSONL条目 - 兼容Claude Chrome扩展格式
  static Map<String, dynamic>? _processJsonlEntry(Map<String, dynamic> json) {
    // 跳过非assistant消息
    if (json['type'] != 'assistant') {
      return null;
    }
    
    final message = json['message'] as Map<String, dynamic>?;
    if (message == null) return null;
    
    final usage = message['usage'] as Map<String, dynamic>?;
    if (usage == null) return null;
    
    // 提取token数据 - 兼容Chrome扩展格式
    final inputTokens = usage['input_tokens'] as int? ?? 0;
    final outputTokens = usage['output_tokens'] as int? ?? 0;
    final cacheCreationTokens = usage['cache_creation_input_tokens'] as int? ?? 0;
    final cacheReadTokens = usage['cache_read_input_tokens'] as int? ?? 0;
    
    // 如果所有token都是0，跳过
    if (inputTokens == 0 && outputTokens == 0 && 
        cacheCreationTokens == 0 && cacheReadTokens == 0) {
      return null;
    }
    
    // 提取模型名称
    final model = message['model'] as String? ?? 'unknown';
    
    // 提取时间戳
    final timestamp = json['timestamp'] ?? message['timestamp'];
    
    // 构建标准化条目
    return {
      'timestamp': timestamp ?? DateTime.now().toUtc().toIso8601String(),
      'model': model,
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
  // ▎辅助方法
  // ─────────────────────────────────────────────────────────────────────────
  
  /// 创建唯一hash用于去重
  static String? _createUniqueHash(Map<String, dynamic> entry) {
    final messageId = entry['message_id'] as String?;
    final requestId = entry['request_id'] as String?;
    
    // 需要同时有message_id和request_id才能生成唯一hash
    if (messageId != null && requestId != null) {
      return '$messageId:$requestId';
    }
    
    return null;
  }
  
  /// 递归查找JSONL文件
  static Future<List<File>> _findJsonlFiles(Directory dir) async {
    final files = <File>[];
    
    try {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.jsonl')) {
          files.add(entity);
        }
      }
    } catch (e) {
      // 目录访问失败
    }
    
    return files;
  }
  
  /// 解析时间戳
  static DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    
    if (timestamp is DateTime) {
      return timestamp.toUtc();
    }
    
    if (timestamp is String) {
      try {
        return DateTime.parse(timestamp).toUtc();
      } catch (_) {
        return null;
      }
    }
    
    if (timestamp is int) {
      // Unix时间戳
      if (timestamp > 1000000000000) {
        // 毫秒
        return DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc();
      } else {
        // 秒
        return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toUtc();
      }
    }
    
    return null;
  }
  
  /// 获取可用的数据目录
  static Future<List<String>> getAvailableDataPaths() async {
    final available = <String>[];
    
    for (final basePath in _defaultDataPaths) {
      final dir = Directory(basePath);
      if (await dir.exists()) {
        available.add(basePath);
      }
    }
    
    return available;
  }
  
  /// 获取数据统计
  static Future<Map<String, dynamic>> getDataStats() async {
    final paths = await getAvailableDataPaths();
    int totalFiles = 0;
    int totalEntries = 0;
    
    for (final basePath in paths) {
      final dir = Directory(basePath);
      final files = await _findJsonlFiles(dir);
      totalFiles += files.length;
      
      for (final file in files) {
        final lines = await file.readAsLines();
        totalEntries += lines.where((l) => l.trim().isNotEmpty).length;
      }
    }
    
    return {
      'availablePaths': paths,
      'totalFiles': totalFiles,
      'totalEntries': totalEntries,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎模拟数据生成器 - 开发测试用
// ═══════════════════════════════════════════════════════════════════════════

class MockDataGenerator {
  
  /// 生成模拟数据（当没有真实数据时使用）
  static List<Map<String, dynamic>> generateMockData({
    int count = 50,
    int hoursBack = 24,
  }) {
    final entries = <Map<String, dynamic>>[];
    final now = DateTime.now().toUtc();
    final models = ['claude-3-5-sonnet', 'claude-3-opus', 'claude-3-haiku'];
    
    for (int i = 0; i < count; i++) {
      final minutesBack = (i * hoursBack * 60 / count).round();
      final timestamp = now.subtract(Duration(minutes: minutesBack));
      final model = models[i % models.length];
      
      // 根据模型生成合理的token数量
      final baseTokens = model.contains('opus') ? 5000 : 
                         model.contains('sonnet') ? 2000 : 500;
      final inputTokens = baseTokens + (i * 100);
      final outputTokens = (baseTokens * 0.3).round() + (i * 50);
      
      entries.add({
        'timestamp': timestamp.toIso8601String(),
        'model': model,
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'cache_creation_tokens': (inputTokens * 0.1).round(),
        'cache_read_tokens': (inputTokens * 0.05).round(),
        'total_tokens': inputTokens + outputTokens,
        'type': 'assistant',
      });
    }
    
    return entries;
  }
}