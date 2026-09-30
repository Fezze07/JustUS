#!/usr/bin/env node
// =============================================================================
// analyze_report.js — summarise a jscpd duplication report.
//
// Usage:
//   node scripts/analyze_report.js [path/to/jscpd-report.json]
//
// The previous version read the hardcoded relative path
// 'jscpd-report/jscpd-report.json', which only resolved when the process was
// started from the repo root, and it threw a raw ENOENT stack trace when the
// report did not exist (e.g. before jscpd had ever run).
//
// It now:
//   * accepts the report path as an argument, defaulting to <repoRoot>/jscpd-report;
//   * discovers the report by walking up from the script location, so it works
//     from any working directory;
//   * fails with an actionable message and exit code instead of a stack trace.
// =============================================================================

const fs = require('fs');
const path = require('path');

const SCRIPT_DIR = __dirname;
const REPO_ROOT = path.resolve(SCRIPT_DIR, '..');

const DEFAULT_REPORT_DIR = path.join(REPO_ROOT, 'jscpd-report');
const REPORT_FILENAME = 'jscpd-report.json';

const TOP_N = 10;

function usage() {
  console.log('Usage: node scripts/analyze_report.js [path/to/jscpd-report.json]');
}

/**
 * Resolve the report file.
 * Prefers an explicit argument, then the conventional location under the repo
 * root, then any jscpd-report.json found while walking up from the script.
 * @returns {string|null} absolute path, or null when nothing was found
 */
function resolveReportPath() {
  const explicit = process.argv[2];

  if (explicit && explicit !== '--help' && explicit !== '-h') {
    const abs = path.resolve(process.cwd(), explicit);
    if (!fs.existsSync(abs)) {
      console.error(`ERROR: report not found: ${abs}`);
      console.error('       Run the duplication scan first (npm run scan:duplicates).');
      process.exit(1);
    }
    return abs;
  }

  if (process.argv.length > 2) {
    usage();
    process.exit(process.argv[2] === '--help' || process.argv[2] === '-h' ? 0 : 1);
  }

  const conventional = path.join(DEFAULT_REPORT_DIR, REPORT_FILENAME);
  if (fs.existsSync(conventional)) {
    return conventional;
  }

  let dir = SCRIPT_DIR;
  for (let i = 0; i < 5; i += 1) {
    const candidate = path.join(dir, 'jscpd-report', REPORT_FILENAME);
    if (fs.existsSync(candidate)) {
      return candidate;
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }

  return null;
}

function loadReport(reportPath) {
  let raw;
  try {
    raw = fs.readFileSync(reportPath, 'utf8');
  } catch (error) {
    console.error(`ERROR: could not read report at ${reportPath}`);
    console.error(`       ${error.message}`);
    process.exit(1);
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    // A truncated report (killed mid-write) used to surface as a bare
    // "Unexpected token ... in JSON" with no indication of which file.
    console.error(`ERROR: report at ${reportPath} is not valid JSON.`);
    console.error(`       ${error.message}`);
    process.exit(1);
  }

  if (!parsed || !Array.isArray(parsed.duplicates)) {
    console.error(`ERROR: report at ${reportPath} has no "duplicates" array.`);
    process.exit(1);
  }

  return parsed;
}

function main() {
  const reportPath = resolveReportPath();

  if (reportPath === null) {
    console.error(`ERROR: no ${REPORT_FILENAME} found.`);
    console.error(`       Looked in: ${DEFAULT_REPORT_DIR}`);
    console.error('       Run the duplication scan first (npm run scan:duplicates).');
    process.exit(1);
  }

  const { duplicates } = loadReport(reportPath);

  console.log(`Report: ${reportPath}`);
  console.log(`Total duplicates: ${duplicates.length}`);

  if (duplicates.length === 0) {
    console.log('\nNo duplicated blocks found.');
    return;
  }

  const fileDuplicates = new Map();
  for (const dup of duplicates) {
    const f1 = `${dup.format}:${dup.firstFile.name}`;
    const f2 = `${dup.format}:${dup.secondFile.name}`;
    fileDuplicates.set(f1, (fileDuplicates.get(f1) ?? 0) + 1);
    fileDuplicates.set(f2, (fileDuplicates.get(f2) ?? 0) + 1);
  }

  const sortedFiles = [...fileDuplicates.entries()].sort((a, b) => b[1] - a[1]);

  console.log(`\nTop ${TOP_N} files with most duplicates:`);
  sortedFiles.slice(0, TOP_N).forEach(([file, count]) => {
    console.log(`${count} duplicates in ${file}`);
  });

  console.log(`\nTop ${TOP_N} largest duplicates:`);
  [...duplicates]
    .sort((a, b) => b.lines - a.lines)
    .slice(0, TOP_N)
    .forEach((dup) => {
      console.log(`${dup.lines} lines duplicated between:`);
      console.log(
        `  A: ${dup.firstFile.name} (lines ${dup.firstFile.start}-${dup.firstFile.end})`,
      );
      console.log(
        `  B: ${dup.secondFile.name} (lines ${dup.secondFile.start}-${dup.secondFile.end})`,
      );
    });
}

main();