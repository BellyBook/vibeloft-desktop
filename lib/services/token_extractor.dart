/*
 * Purpose: Token提取器和数据处理器，从多源数据中智能提取Token信息
 * Inputs: 原始数据映射、消息类型
 * Outputs: 标准化的Token数据、模型信息
 */

import '../models/token_counts.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎Token提取器 - 多层级智能提取
// ═══════════════════════════════════════════════════════════════════════════

class TokenExtractor {
  
  // ─────────────────────────────────────────────────────────────────────────
  // ▎核心提取方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 提取Token数据 - 多源多层级提取
  static TokenCounts extractTokens(Map<String, dynamic> data) {
    // 初始化零值安全结构
    var tokens = const TokenCounts();
    
    // 构建优先级Token源列表
    final tokenSources = _buildTokenSources(data);
    
    // 按优先级顺序提取第一个有效源
    for (final source in tokenSources) {
      if (source == null || source is! Map<String, dynamic>) {
        continue;
      }
      
      final extracted = _extractFromSource(source);
      if (extracted.hasData) {
        return extracted;
      }
    }
    
    return tokens;
  }

  /// 批量提取Token数据
  static List<TokenCounts> extractBatch(List<Map<String, dynamic>> entries) {
    return entries.map(extractTokens).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎模型信息提取
  // ─────────────────────────────────────────────────────────────────────────

  /// 提取模型名称 - 多源优先级策略
  static String extractModelName(Map<String, dynamic> data, {String defaultModel = 'claude-3-5-sonnet'}) {
    // 定义查找优先级
    final modelCandidates = [
      data['message']?['model'],           // 嵌套消息中的模型
      data['model'],                        // 顶级模型字段
      data['Model'],                        // 大写Model字段
      data['usage']?['model'],             // usage中的模型
      data['request']?['model'],           // request中的模型
    ];
    
    // 返回第一个非空字符串候选
    for (final candidate in modelCandidates) {
      if (candidate != null && candidate is String && candidate.isNotEmpty) {
        return _normalizeModelName(candidate);
      }
    }
    
    return defaultModel;
  }

  /// 提取消息ID
  static String? extractMessageId(Map<String, dynamic> data) {
    // 直接消息ID
    var messageId = data['message_id'] as String?;
    
    // 嵌套消息ID
    if (messageId == null && data['message'] is Map) {
      messageId = data['message']['id'] as String?;
    }
    
    return messageId;
  }

  /// 提取请求ID
  static String? extractRequestId(Map<String, dynamic> data) {
    return data['request_id'] as String? ?? 
           data['requestId'] as String?;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎私有辅助方法
  // ─────────────────────────────────────────────────────────────────────────

  static List<dynamic> _buildTokenSources(Map<String, dynamic> data) {
    final sources = <dynamic>[];
    final isAssistant = data['type'] == 'assistant';
    
    if (isAssistant) {
      // Assistant消息优先级：message.usage -> usage -> data
      if (data['message'] is Map && data['message']['usage'] != null) {
        sources.add(data['message']['usage']);
      }
      if (data['usage'] != null) {
        sources.add(data['usage']);
      }
      sources.add(data);
    } else {
      // 非Assistant消息优先级：usage -> message.usage -> data
      if (data['usage'] != null) {
        sources.add(data['usage']);
      }
      if (data['message'] is Map && data['message']['usage'] != null) {
        sources.add(data['message']['usage']);
      }
      sources.add(data);
    }
    
    return sources;
  }

  static TokenCounts _extractFromSource(Map<String, dynamic> source) {
    // 多键名兼容提取
    final inputTokens = _extractTokenValue(source, [
      'input_tokens',
      'inputTokens',
      'prompt_tokens',
    ]);
    
    final outputTokens = _extractTokenValue(source, [
      'output_tokens',
      'outputTokens',
      'completion_tokens',
    ]);
    
    final cacheCreation = _extractTokenValue(source, [
      'cache_creation_tokens',
      'cache_creation_input_tokens',
      'cacheCreationInputTokens',
    ]);
    
    final cacheRead = _extractTokenValue(source, [
      'cache_read_input_tokens',
      'cache_read_tokens',
      'cacheReadInputTokens',
    ]);
    
    // 有效性检查 - 至少有input或output token
    if (inputTokens > 0 || outputTokens > 0) {
      return TokenCounts(
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        cacheCreationTokens: cacheCreation,
        cacheReadTokens: cacheRead,
      );
    }
    
    return const TokenCounts();
  }

  static int _extractTokenValue(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value != null) {
        if (value is int) return value;
        if (value is double) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null) return parsed;
        }
      }
    }
    return 0;
  }

  static String _normalizeModelName(String model) {
    return model
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎数据验证
  // ─────────────────────────────────────────────────────────────────────────

  /// 验证Token数据完整性
  static bool validateTokenData(TokenCounts tokens) {
    // 基本验证：非负数
    if (tokens.inputTokens < 0 || 
        tokens.outputTokens < 0 ||
        tokens.cacheCreationTokens < 0 ||
        tokens.cacheReadTokens < 0) {
      return false;
    }
    
    // 合理性验证：总数不超过最大限制
    const maxTokensPerRequest = 1000000; // 100万token上限
    if (tokens.totalTokens > maxTokensPerRequest) {
      return false;
    }
    
    return true;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎数据转换器 - 标准化处理
// ═══════════════════════════════════════════════════════════════════════════

class DataConverter {
  
  /// 扁平化嵌套字典
  static Map<String, dynamic> flattenNestedDict(
    Map<String, dynamic> data, {
    String prefix = '',
  }) {
    final result = <String, dynamic>{};
    
    data.forEach((key, value) {
      final newKey = prefix.isEmpty ? key : '$prefix.$key';
      
      if (value is Map<String, dynamic>) {
        // 递归扁平化嵌套结构
        result.addAll(flattenNestedDict(value, prefix: newKey));
      } else {
        result[newKey] = value;
      }
    });
    
    return result;
  }

  /// 创建唯一哈希
  static String? createUniqueHash(Map<String, dynamic> data) {
    final messageId = TokenExtractor.extractMessageId(data);
    final requestId = TokenExtractor.extractRequestId(data);
    
    if (messageId != null && requestId != null) {
      return '$messageId:$requestId';
    }
    
    return null;
  }

  /// 标准化时间戳
  static DateTime? parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    
    try {
      if (timestamp is DateTime) {
        return timestamp.toUtc();
      }
      
      if (timestamp is String) {
        // 处理Z结尾的ISO格式
        String processedTimestamp = timestamp;
        if (processedTimestamp.endsWith('Z')) {
          processedTimestamp = '${processedTimestamp.substring(0, processedTimestamp.length - 1)}+00:00';
        }
        return DateTime.parse(processedTimestamp).toUtc();
      }
      
      if (timestamp is int) {
        // Unix时间戳（秒或毫秒）
        if (timestamp > 1000000000000) {
          // 毫秒
          return DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc();
        } else {
          // 秒
          return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000).toUtc();
        }
      }
      
      if (timestamp is double) {
        return parseTimestamp(timestamp.toInt());
      }
    } catch (_) {
      // 解析失败
    }
    
    return null;
  }

  /// 转换为可序列化格式
  static Map<String, dynamic> toSerializable(dynamic obj) {
    if (obj == null) return {};
    
    if (obj is Map<String, dynamic>) {
      final result = <String, dynamic>{};
      obj.forEach((key, value) {
        if (value is DateTime) {
          result[key] = value.toIso8601String();
        } else if (value is Map) {
          result[key] = toSerializable(value);
        } else if (value is List) {
          result[key] = value.map(toSerializable).toList();
        } else {
          result[key] = value;
        }
      });
      return result;
    }
    
    return {'value': obj};
  }
}