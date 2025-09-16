/*
 * Purpose: 在主窗口和 Popover 引擎间同步数据
 * Inputs: 应用使用数据、MethodChannel 事件
 * Outputs: 同步的数据状态、跨引擎通信
 */

import 'package:flutter/services.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎数据同步服务
// ═══════════════════════════════════════════════════════════════════════════

class DataSyncService {
  static final DataSyncService _instance = DataSyncService._internal();
  factory DataSyncService() => _instance;
  DataSyncService._internal();

  // ─────────────────────────────────────────────────────────────────────────
  // ▎Channel 定义
  // ─────────────────────────────────────────────────────────────────────────

  static const _syncChannel = MethodChannel('com.vibeloft.desktop/sync');

  // ─────────────────────────────────────────────────────────────────────────
  // ▎初始化同步服务
  // ─────────────────────────────────────────────────────────────────────────

  void initialize(bool isPopover) {
    _syncChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'syncData':
          // 处理数据同步请求
          _handleDataSync(call.arguments);
          break;
        case 'requestData':
          // 返回当前数据
          return _getCurrentData();
      }
    });

    // 如果是 Popover，请求初始数据
    if (isPopover) {
      _requestInitialData();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎发送数据到另一个引擎
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> sendDataToOtherEngine(Map<String, dynamic> data) async {
    try {
      await _syncChannel.invokeMethod('syncData', data);
    } catch (e) {
      // 忽略错误，另一个引擎可能不存在
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎请求初始数据
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _requestInitialData() async {
    try {
      final data = await _syncChannel.invokeMethod('requestData');
      if (data != null) {
        _handleDataSync(data);
      }
    } catch (e) {
      // 主引擎可能还未准备好
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎处理数据同步
  // ─────────────────────────────────────────────────────────────────────────

  void _handleDataSync(dynamic data) {
    // 更新本地数据状态
    // 这里可以触发应用状态更新
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎获取当前数据
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _getCurrentData() {
    // 返回当前应用使用数据
    return {};
  }
}