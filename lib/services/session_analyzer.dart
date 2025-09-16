/*
 * Purpose: 5小时会话块分析器，将连续使用流转换为可管理的时间块
 * Inputs: 使用条目列表、时间范围
 * Outputs: 5小时会话块列表、活动状态、间隙检测
 */

import '../models/session_block.dart';
import '../models/token_counts.dart';
import 'pricing_calculator.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎会话分析器 - 5小时窗口管理
// ═══════════════════════════════════════════════════════════════════════════

class SessionAnalyzer {
  static const Duration sessionDuration = Duration(hours: 5);
  final PricingCalculator _pricingCalculator;

  SessionAnalyzer({PricingCalculator? pricingCalculator})
      : _pricingCalculator = pricingCalculator ?? PricingCalculator();

  // ─────────────────────────────────────────────────────────────────────────
  // ▎核心转换方法
  // ─────────────────────────────────────────────────────────────────────────

  /// 将条目转换为会话块
  List<SessionBlock> transformToBlocks(List<Map<String, dynamic>> entries) {
    if (entries.isEmpty) return [];

    final blocks = <SessionBlock>[];
    _SessionBlockBuilder? currentBlock;

    for (final entry in entries) {
      final timestamp = _parseTimestamp(entry['timestamp']);
      if (timestamp == null) continue;

      // 检查是否需要创建新块
      if (currentBlock == null ||
          _shouldCreateNewBlock(currentBlock, timestamp)) {
        // 完成当前块
        if (currentBlock != null) {
          blocks.add(currentBlock.build());

          // 检查间隙
          final gap = _checkForGap(currentBlock, timestamp);
          if (gap != null) {
            blocks.add(gap);
          }
        }

        // 创建新块
        currentBlock = _SessionBlockBuilder(timestamp);
      }

      // 添加条目到当前块
      _addEntryToBlock(currentBlock, entry);
    }

    // 完成最后一个块
    if (currentBlock != null) {
      blocks.add(currentBlock.build());
    }

    // 标记活动块
    _markActiveBlocks(blocks);

    return blocks;
  }

  /// 获取活动会话块
  List<SessionBlock> getActiveBlocks(List<SessionBlock> blocks) {
    return blocks.where((b) => b.isActive && !b.isGap).toList();
  }

  /// 获取完成的会话块
  List<SessionBlock> getCompletedBlocks(List<SessionBlock> blocks) {
    return blocks.where((b) => !b.isActive && !b.isGap).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎私有辅助方法
  // ─────────────────────────────────────────────────────────────────────────

  bool _shouldCreateNewBlock(_SessionBlockBuilder block, DateTime timestamp) {
    // 条件1：时间戳超出当前块的固定结束时间（圆整到整点的5小时窗口）
    if (timestamp.isAfter(block.endTime) ||
        timestamp.isAtSameMomentAs(block.endTime)) {
      return true;
    }

    // 条件2：与上一条目间隔超过5小时 - 会话中断检测
    // 这是关键的会话连续性判断
    if (block.lastEntryTime != null) {
      final gap = timestamp.difference(block.lastEntryTime!);
      if (gap >= sessionDuration) {
        return true;
      }
    }

    return false;
  }

  SessionBlock? _checkForGap(
      _SessionBlockBuilder lastBlock, DateTime nextTimestamp) {
    final actualEnd = lastBlock.actualEndTime;
    if (actualEnd == null) return null;

    final gapDuration = nextTimestamp.difference(actualEnd);

    // 如果间隙>=5小时，创建间隙块
    if (gapDuration >= sessionDuration) {
      return SessionBlock.createGap(
        startTime: actualEnd,
        endTime: nextTimestamp,
      );
    }

    return null;
  }

  void _addEntryToBlock(
      _SessionBlockBuilder block, Map<String, dynamic> entry) {
    final model = entry['model'] as String? ?? 'unknown';
    final tokens = TokenCounts(
      inputTokens: entry['input_tokens'] as int? ?? 0,
      outputTokens: entry['output_tokens'] as int? ?? 0,
      cacheCreationTokens: entry['cache_creation_tokens'] as int? ?? 0,
      cacheReadTokens: entry['cache_read_tokens'] as int? ?? 0,
    );

    // 计算成本
    final cost = _pricingCalculator.calculateCost(
      model: model,
      tokens: tokens,
    );

    // 提取消息ID
    final messageId = entry['message_id'] as String?;

    block.addEntry(
      model: model,
      tokens: tokens,
      cost: cost,
      timestamp: _parseTimestamp(entry['timestamp']) ?? DateTime.now(),
      messageId: messageId,
    );
  }

  void _markActiveBlocks(List<SessionBlock> blocks) {
    final now = DateTime.now().toUtc();

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (!block.isGap && block.endTime.isAfter(now)) {
        // 创建新的活动块
        blocks[i] = SessionBlock(
          id: block.id,
          startTime: block.startTime,
          endTime: block.endTime,
          actualEndTime: block.actualEndTime,
          tokenCounts: block.tokenCounts,
          costUsd: block.costUsd,
          perModelStats: block.perModelStats,
          models: block.models,
          sentMessagesCount: block.sentMessagesCount,
          messageIds: block.messageIds, // 保留消息ID集合
          isActive: true, // 标记为活动
          isGap: block.isGap,
          durationMinutes: block.durationMinutes,
        );
      }
    }
  }

  DateTime? _parseTimestamp(dynamic timestamp) {
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
      return DateTime.fromMillisecondsSinceEpoch(timestamp).toUtc();
    }

    return null;
  }

  /// 圆整到整点 - UTC时间对齐
  static DateTime roundToHour(DateTime timestamp) {
    // 确保UTC时区
    final utcTime = timestamp.isUtc ? timestamp : timestamp.toUtc();

    // 圆整到整点 - 移除分钟、秒、微秒
    return DateTime.utc(
      utcTime.year,
      utcTime.month,
      utcTime.day,
      utcTime.hour,
      0, // minute
      0, // second
      0, // millisecond
      0, // microsecond
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ▎会话块构建器 - 内部辅助类
// ═══════════════════════════════════════════════════════════════════════════

class _SessionBlockBuilder {
  final DateTime startTime;
  final DateTime endTime;
  DateTime? actualEndTime;
  DateTime? lastEntryTime;

  TokenCounts tokenCounts = const TokenCounts();
  double costUsd = 0.0;
  final Map<String, ModelStats> perModelStats = {};
  final Set<String> models = {};
  final Set<String> messageIds = {}; // 收集唯一的消息ID
  int sentMessagesCount = 0;

  _SessionBlockBuilder(DateTime timestamp)
      : startTime = SessionAnalyzer.roundToHour(timestamp),
        endTime = SessionAnalyzer.roundToHour(timestamp)
            .add(SessionAnalyzer.sessionDuration);

  void addEntry({
    required String model,
    required TokenCounts tokens,
    required double cost,
    required DateTime timestamp,
    String? messageId,
  }) {
    // 更新token统计
    tokenCounts = tokenCounts + tokens;
    costUsd += cost;

    // 收集消息ID用于去重
    if (messageId != null && messageId.isNotEmpty) {
      messageIds.add(messageId);
    }

    // 更新模型统计
    if (!perModelStats.containsKey(model)) {
      perModelStats[model] = const ModelStats(
        inputTokens: 0,
        outputTokens: 0,
        cacheCreationTokens: 0,
        cacheReadTokens: 0,
        costUsd: 0.0,
        entriesCount: 0,
      );
    }

    final current = perModelStats[model]!;
    perModelStats[model] = ModelStats(
      inputTokens: current.inputTokens + tokens.inputTokens,
      outputTokens: current.outputTokens + tokens.outputTokens,
      cacheCreationTokens:
          current.cacheCreationTokens + tokens.cacheCreationTokens,
      cacheReadTokens: current.cacheReadTokens + tokens.cacheReadTokens,
      costUsd: current.costUsd + cost,
      entriesCount: current.entriesCount + 1,
    );

    models.add(model);
    sentMessagesCount++;
    lastEntryTime = timestamp;
    actualEndTime = timestamp;
  }

  SessionBlock build() {
    // 计算百分比分布
    final totalCost = costUsd;
    final totalUsageTokens = tokenCounts.usageTokens;

    final statsWithPercentage = <String, ModelStats>{};
    for (final entry in perModelStats.entries) {
      final stats = entry.value;
      statsWithPercentage[entry.key] = ModelStats(
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

    return SessionBlock(
      id: startTime.toIso8601String(),
      startTime: startTime,
      endTime: endTime,
      actualEndTime: actualEndTime,
      tokenCounts: tokenCounts,
      costUsd: costUsd,
      perModelStats: statsWithPercentage,
      models: models.toList(),
      sentMessagesCount: sentMessagesCount,
      messageIds: messageIds, // 传递收集的消息ID集合
      isActive: false,
      isGap: false,
      durationMinutes: actualEndTime != null
          ? actualEndTime!.difference(startTime).inMinutes
          : 0,
    );
  }
}
