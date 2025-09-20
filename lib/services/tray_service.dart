/*
 * Purpose: 系统托盘管理服务，跨平台实现
 * Inputs: 托盘事件、Flutter 方法调用
 * Outputs: 托盘图标、弹窗显示、主窗口控制
 */

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎托盘服务类 - 跨平台实现
// ═══════════════════════════════════════════════════════════════════════════

class TrayService with TrayListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  // ─────────────────────────────────────────────────────────────────────────
  // ▎Method Channel 定义
  // ─────────────────────────────────────────────────────────────────────────

  static const _channel = MethodChannel('com.vibeloft.desktop/tray');

  // 保存回调引用
  VoidCallback? _onPopoverShown;
  VoidCallback? _onPopoverClosed;
  VoidCallback? _onShowMainWindow;

  // ─────────────────────────────────────────────────────────────────────────
  // ▎初始化托盘（跨平台）
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> initSystemTray() async {
    if (Platform.isMacOS) {
      // macOS：使用原生 NSPopover
      await _initMacOSTray();
    } else if (Platform.isWindows) {
      // Windows：使用 tray_manager
      await _initWindowsTray();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎macOS 托盘初始化
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initMacOSTray() async {
    // 设置方法调用处理器
    _channel.setMethodCallHandler(_handleMethodCall);

    // 设置工具提示
    await _channel.invokeMethod('setToolTip', {
      'tooltip': 'VibeLoft Desktop',
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎Windows 托盘初始化
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initWindowsTray() async {
    // 设置托盘监听器
    trayManager.addListener(this);

    // 设置托盘图标（使用 PNG，tray_manager 会自动处理）
    await trayManager.setIcon('assets/app_icon.png');

    // 设置工具提示
    await trayManager.setToolTip('VibeLoft Desktop');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎处理原生端回调
  // ─────────────────────────────────────────────────────────────────────────

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPopoverShown':
        _onPopoverShown?.call();
        break;
      case 'onPopoverClosed':
        _onPopoverClosed?.call();
        break;
      case 'showMainWindow':
        _onShowMainWindow?.call();
        await _showMainWindow();
        break;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎显示原生 Popover
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> showPopover() async {
    try {
      await _channel.invokeMethod('showPopover');
    } on PlatformException catch (e) {
      debugPrint('Failed to show popover: ${e.message}');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎关闭原生 Popover
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> closePopover() async {
    try {
      await _channel.invokeMethod('closePopover');
    } on PlatformException catch (e) {
      debugPrint('Failed to close popover: ${e.message}');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎获取托盘图标位置
  // ─────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getTrayPosition() async {
    try {
      final result = await _channel.invokeMethod('getTrayPosition');
      return result != null ? Map<String, dynamic>.from(result) : null;
    } on PlatformException catch (e) {
      debugPrint('Failed to get tray position: ${e.message}');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎更新托盘图标
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> updateTrayIcon(String imageName) async {
    try {
      await _channel.invokeMethod('updateTrayIcon', {
        'imageName': imageName,
      });
    } on PlatformException catch (e) {
      debugPrint('Failed to update tray icon: ${e.message}');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎显示主窗口
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showMainWindow() async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAlwaysOnTop(false);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎设置 Popover 显示回调
  // ─────────────────────────────────────────────────────────────────────────

  void setOnPopoverShown(VoidCallback callback) {
    _onPopoverShown = callback;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎设置 Popover 关闭回调
  // ─────────────────────────────────────────────────────────────────────────

  void setOnPopoverClosed(VoidCallback callback) {
    _onPopoverClosed = callback;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎设置显示主窗口回调
  // ─────────────────────────────────────────────────────────────────────────

  void setOnShowMainWindow(VoidCallback callback) {
    _onShowMainWindow = callback;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎销毁托盘
  // ─────────────────────────────────────────────────────────────────────────

  void destroy() {
    _onPopoverShown = null;
    _onPopoverClosed = null;
    _onShowMainWindow = null;

    if (Platform.isWindows) {
      trayManager.removeListener(this);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎Windows 托盘事件处理（TrayListener 接口）
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void onTrayIconMouseDown() {
    // Windows：左键点击显示托盘窗口
    if (Platform.isWindows) {
      _showWindowsTrayWindow();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    // Windows：右键不处理（根据需求已移除右键菜单）
  }

  @override
  void onTrayIconMouseUp() {
    // 不需要处理
  }

  @override
  void onTrayIconRightMouseUp() {
    // 不需要处理
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    // 不需要处理（没有菜单）
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎Windows 托盘窗口显示
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showWindowsTrayWindow() async {
    // Windows 平台简化实现：直接显示/隐藏主窗口
    // 未来可以实现独立的托盘弹窗
    final isVisible = await windowManager.isVisible();

    if (isVisible) {
      // 如果已显示，则隐藏
      await windowManager.hide();
    } else {
      // 如果隐藏，则显示
      await windowManager.show();
      await windowManager.focus();
    }
  }
}