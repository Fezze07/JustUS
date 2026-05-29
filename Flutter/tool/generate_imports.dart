import 'dart:io';

void main(List<String> args) async {
  final watch = args.contains('--watch');

  try {
    await _generate();
  } catch (e) {
    print(e);
    if (!watch) exit(1);
  }

  if (watch) {
    print('\nWatching for file changes in lib/ ...');
    final libDir = Directory('lib');
    libDir.watch(recursive: true).listen((event) async {
      final path = event.path.replaceAll('\\', '/');
      if (path.endsWith('.dart') && !path.endsWith('/all_imports.dart') && path != 'lib/all_imports.dart') {
        print('Change detected: $path');
        try {
          await _generate();
        } catch (e) {
          print(e);
        }
      }
    });
  }
}

Future<void> _generate() async {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    throw Exception('lib directory not found. Please run this script from the project root.');
  }

  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) {
        final path = f.path.replaceAll('\\', '/');
        return path.endsWith('.dart') && path != 'lib/all_imports.dart';
      });

  final Map<String, List<String>> nameMap = {};

  for (final file in files) {
    final path = file.path.replaceAll('\\', '/');
    final name = path.split('/').last;
    nameMap.putIfAbsent(name, () => []).add(path);
  }

  bool hasDuplicates = false;
  for (final entry in nameMap.entries) {
    if (entry.value.length > 1) {
      if (!hasDuplicates) {
        print('\n=== DUPLICATE FILENAMES DETECTED ===');
      }
      print('File: ${entry.key}');
      for (final path in entry.value) {
        print('  - $path');
      }
      print('');
      hasDuplicates = true;
    }
  }

  if (hasDuplicates) {
    throw Exception('Generation blocked due to duplicate filenames. Please rename the conflicting files and try again.');
  }

  final sortedEntries = nameMap.entries.toList()..sort((a, b) => a.key.compareTo(b.key));

  // --- GENERATE lib/all_imports.dart ---
  final exportCode = StringBuffer();
  exportCode.writeln('// GENERATED CODE - DO NOT MODIFY BY HAND');
  exportCode.writeln('// This file allows you to import everything from a single point.');
  exportCode.writeln('// Usage: import \'package:justus/all_imports.dart\';');
  exportCode.writeln();

  for (final entry in sortedEntries) {
    final fullPath = entry.value.first;
    final relativePath = fullPath.substring(fullPath.indexOf('lib/') + 4);
    
    // Skip main.dart and the generated file itself
    if (relativePath == 'main.dart' || relativePath == 'all_imports.dart') {
      continue;
    }
    
    exportCode.writeln("export 'package:justus/$relativePath';");
  }

  final exportFile = File('lib/all_imports.dart');
  await exportFile.writeAsString(exportCode.toString());
  print('Successfully generated lib/all_imports.dart with ${nameMap.length} entries.');
}
