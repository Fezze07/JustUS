const fs = require('fs');
const path = require('path');

const TARGET_DIRS = ['core', 'config', 'controllers', 'middleware', 'services', 'utils', 'features'];
const EXCLUDE_FILES = ['all_imports.js', 'app.js', 'index.js'];
const OUTPUT_FILE = 'all_imports.js';

function walkDir(dir) {
  let results = [];
  const list = fs.readdirSync(dir);
  list.forEach(file => {
    const fullPath = path.join(dir, file);
    const stat = fs.statSync(fullPath);
    if (stat && stat.isDirectory()) {
      results = results.concat(walkDir(fullPath));
    } else if (file.endsWith('.js')) {
      results.push(fullPath);
    }
  });
  return results;
}

function cleanComments(code) {
  return code
    .replace(/\/\*[\s\S]*?\*\//g, '') // remove multi-line comments
    .replace(/\/\/.*/g, '');          // remove single-line comments
}

function parseExports(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const cleanCode = cleanComments(content).trim();

  // Skip stubs (e.g. module.exports = require(...))
  if (/module\.exports\s*=\s*require\(/i.test(cleanCode)) {
    return null;
  }

  // 1. Destructured exports: module.exports = { keys }
  const destructuredMatch = cleanCode.match(/module\.exports\s*=\s*\{([\s\S]*?)\}/);
  if (destructuredMatch) {
    const rawKeys = destructuredMatch[1];
    const keys = rawKeys
      .split(',')
      .map(k => k.trim())
      .filter(k => k && !k.startsWith('...') && /^[a-zA-Z0-9_$]+$/.test(k));
    if (keys.length > 0) {
      return { type: 'destructured', keys };
    }
  }

  // 2. Single export: module.exports = identifier
  const singleMatch = cleanCode.match(/module\.exports\s*=\s*([a-zA-Z0-9_$]+)/);
  if (singleMatch) {
    const key = singleMatch[1];
    // Skip routers or internal exports
    if (key !== 'router' && key !== 'exports' && key !== 'module') {
      return { type: 'single', key };
    }
  }

  return null;
}

function collectFiles(rootDir) {
  const allFiles = [];
  TARGET_DIRS.forEach(dir => {
    const dirPath = path.join(rootDir, dir);
    if (fs.existsSync(dirPath)) {
      allFiles.push(...walkDir(dirPath));
    }
  });
  return allFiles;
}

function buildExportEntries(allFiles, rootDir) {
  const exportEntries = [];
  const duplicateCheck = new Map();

  allFiles.forEach(file => {
    const relativePath = path.relative(rootDir, file).replace(/\\/g, '/');
    if (EXCLUDE_FILES.includes(path.basename(file))) return;

    const parseResult = parseExports(file);
    if (!parseResult) return;

    const importPath = `./${relativePath.replace(/\.js$/, '')}`;

    if (parseResult.type === 'destructured') {
      parseResult.keys.forEach(key => {
        if (duplicateCheck.has(key)) {
          console.warn(`⚠️ Warning: Duplicate export key "${key}" detected in:`);
          console.warn(`  - ${duplicateCheck.get(key)}`);
          console.warn(`  - ${relativePath}`);
          return;
        }
        duplicateCheck.set(key, relativePath);
        exportEntries.push({
          key,
          code: `  get ${key}() { return require('${importPath}').${key}; }`
        });
      });
    } else if (parseResult.type === 'single') {
      const key = parseResult.key;
      if (duplicateCheck.has(key)) {
        console.warn(`⚠️ Warning: Duplicate export key "${key}" detected in:`);
        console.warn(`  - ${duplicateCheck.get(key)}`);
        console.warn(`  - ${relativePath}`);
        return;
      }
      duplicateCheck.set(key, relativePath);
      exportEntries.push({
        key,
        code: `  get ${key}() { return require('${importPath}'); }`
      });
    }
  });

  exportEntries.sort((a, b) => a.key.localeCompare(b.key));
  return exportEntries;
}

function writeOutput(exportEntries, rootDir) {
  const code = [];
  code.push('// GENERATED CODE - DO NOT MODIFY BY HAND');
  code.push('// This file allows you to import everything from a single point.');
  code.push("// Usage: const { AppError, logger } = require('./all_imports');");
  code.push('');
  code.push('module.exports = {');
  code.push(exportEntries.map(e => e.code).join(',\n'));
  code.push('};');
  code.push('');

  fs.writeFileSync(path.join(rootDir, OUTPUT_FILE), code.join('\n'));
  console.log(`Successfully generated ${OUTPUT_FILE} with ${exportEntries.length} entries.`);
}

function generate() {
  console.log('Scanning directories for exports...');
  const rootDir = path.resolve(__dirname, '..');
  const allFiles = collectFiles(rootDir);
  const exportEntries = buildExportEntries(allFiles, rootDir);
  writeOutput(exportEntries, rootDir);
}

generate();
