/*
 * Purpose: 弹出窗口管理服务，控制托盘下拉界面的显示和定位
 * Inputs: 托盘位置、窗口管理器事件、焦点变化
 * Outputs: 弹出窗口显示/隐藏、位置调整、动画控制
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ▎弹出窗口管理服务
// ═══════════════════════════════════════════════════════════════════════════

class PopoverWindowService {
  static final PopoverWindowService _instance = PopoverWindowService._internal();
  factory PopoverWindowService() => _instance;
  PopoverWindowService._internal();

  // ─────────────────────────────────────────────────────────────────────────
  // ▎窗口配置常量
  // ─────────────────────────────────────────────────────────────────────────

  static const double windowWidth = 340;
  static const double windowHeight = 500;
  static const double windowPadding = 10; // 距离托盘图标的间距

  bool _isVisible = false;

  // ─────────────────────────────────────────────────────────────────────────
  // ▎显示弹出窗口
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> showPopover({Offset? position}) async {
    if (_isVisible) return;

    // 获取屏幕尺寸
    final screenSize = await _getScreenSize();

    // 计算窗口位置（默认在屏幕顶部居中）
    double x = (screenSize.width - windowWidth) / 2;
    double y = 30; // macOS 菜单栏高度

    // 如果提供了托盘位置，使用托盘位置
    if (position != null) {
      x = position.dx - (windowWidth / 2);
      y = position.dy + windowPadding;

      // 确保窗口不超出屏幕边界
      if (x < 0) x = 10;
      if (x + windowWidth > screenSize.width) {
        x = screenSize.width - windowWidth - 10;
      }
    }

    // 设置窗口属性
    await windowManager.setSize(const Size(windowWidth, windowHeight));
    await windowManager.setPosition(Offset(x, y));

    // 设置窗口样式
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setOpacity(0.0);

    // 显示窗口
    await windowManager.show();
    await windowManager.focus();

    // 淡入动画
    await _animateFadeIn();

    _isVisible = true;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎隐藏弹出窗口
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> hidePopover() async {
    if (!_isVisible) return;

    // 淡出动画
    await _animateFadeOut();

    // 隐藏窗口
    await windowManager.hide();

    _isVisible = false;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎切换弹出窗口显示状态
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> togglePopover({Offset? position}) async {
    if (_isVisible) {
      await hidePopover();
    } else {
      await showPopover(position: position);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎动画效果
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _animateFadeIn() async {
    const steps = 10;
    const duration = 300; // 毫秒
    const stepDuration = duration ~/ steps;

    for (int i = 1; i <= steps; i++) {
      await windowManager.setOpacity(i / steps);
      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  Future<void> _animateFadeOut() async {
    const steps = 10;
    const duration = 200; // 毫秒
    const stepDuration = duration ~/ steps;

    for (int i = steps; i >= 0; i--) {
      await windowManager.setOpacity(i / steps);
      await Future.delayed(Duration(milliseconds: stepDuration));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎获取屏幕尺寸
  // ─────────────────────────────────────────────────────────────────────────

  Future<Size> _getScreenSize() async {
    // 获取主显示器的工作区域
    final bounds = await windowManager.getBounds();

    // macOS 特定处理
    if (Platform.isMacOS) {
      // 使用 Display 类获取屏幕尺寸
      // 这里简化处理，实际项目中可能需要更精确的屏幕信息
      return const Size(1920, 1080); // 默认值，实际应该动态获取
    }

    return Size(bounds.width, bounds.height);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ▎获取当前显示状态
  // ─────────────────────────────────────────────────────────────────────────

  bool get isVisible => _isVisible;
}