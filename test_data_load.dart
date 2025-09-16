import 'dart:io';
import 'lib/services/usage_service.dart';
import 'lib/models/usage_data.dart';

void main() async {
  print('Testing data loading...\n');
  
  final service = UsageService();
  
  // Test loading data from last 30 days
  print('Loading entries from last 30 days...');
  final entries = await service.loadUsageEntries(hoursBack: 720);
  
  print('Found ${entries.length} entries\n');
  
  if (entries.isNotEmpty) {
    // Show first few entries
    print('First 5 entries:');
    for (var i = 0; i < 5 && i < entries.length; i++) {
      final entry = entries[i];
      print('  ${i+1}. ${entry.model}');
      print('     Tokens: ${entry.totalTokens} (in: ${entry.inputTokens}, out: ${entry.outputTokens})');
      print('     Cost: \$${entry.costUsd.toStringAsFixed(4)}');
      print('     Time: ${entry.timestamp}');
      print('');
    }
    
    // Calculate stats
    final stats = service.calculateStats(entries);
    print('\nStatistics:');
    print('  Total tokens: ${stats.totalTokens}');
    print('  Total cost: \$${stats.totalCost.toStringAsFixed(4)}');
    print('  Message count: ${stats.messageCount}');
    print('  P90 tokens: ${stats.p90Tokens}');
    print('  P90 cost: \$${stats.p90Cost}');
    print('  P90 messages: ${stats.p90Messages}');
    print('  Model usage: ${stats.modelUsage}');
    
    // Check today's stats
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayEntries = entries.where((e) => e.timestamp.isAfter(todayStart)).toList();
    
    print('\nToday\'s data:');
    print('  Entries: ${todayEntries.length}');
    if (todayEntries.isNotEmpty) {
      final todayStats = service.calculateStats(todayEntries);
      print('  Total tokens: ${todayStats.totalTokens}');
      print('  Total cost: \$${todayStats.totalCost.toStringAsFixed(4)}');
    }
  } else {
    print('No entries found!');
    print('Checking for JSONL files...');
    
    final dataPath = service.dataPath;
    final dir = Directory(dataPath);
    if (await dir.exists()) {
      final files = await service.findJsonlFiles();
      print('Found ${files.length} JSONL files in $dataPath');
      
      if (files.isNotEmpty) {
        print('\nChecking first file: ${files.first.path}');
        final lines = await files.first.readAsLines();
        print('File has ${lines.length} lines');
      }
    } else {
      print('Data directory does not exist: $dataPath');
    }
  }
}