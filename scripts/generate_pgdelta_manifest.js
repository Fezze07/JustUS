#!/usr/bin/env node
// =============================================================================
// generate_pgdelta_manifest.js — keep supabase/schemas/.pgdelta-export.json in
// sync with the SQL files under supabase/schemas.
//
// Usage:
//   node scripts/generate_pgdelta_manifest.js          # rewrite the manifest
//   node scripts/generate_pgdelta_manifest.js --check  # fail on drift, no write
//
// `files` is rebuilt alphabetically from the directory. `loadOrder` keeps the
// existing order for files that still exist and appends new files to the end of
// their group, so a rename or a new schema file cannot silently fall out of the
// manifest.
// =============================================================================

const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..');
const SCHEMA_DIR = path.join(REPO_ROOT, 'supabase', 'schemas');
const MANIFEST_PATH = path.join(SCHEMA_DIR, '.pgdelta-export.json');
const CHECK_ONLY = process.argv.includes('--check');

// Load order groups, matching the order the existing manifest was built with.
// Anything unrecognised goes just before publications so a new folder still
// loads; publications always stays last.
const GROUP_RULES = [
  [/^public\/default_privileges\.sql$/, 0],
  [/\/schema\.sql$/, 1],
  [/^_cluster\/extensions\//, 2],
  [/\/sequences\//, 3],
  [/^auth\/tables\//, 4],
  [/\/tables\//, 5],
  [/\/views\//, 6],
  [/\/functions\//, 7],
];
const UNKNOWN_GROUP = 8;
const PUBLICATIONS_GROUP = 9;

function groupOf(file) {
  for (const [pattern, group] of GROUP_RULES) {
    if (pattern.test(file)) return group;
  }
  return file === '_cluster/publications.sql' ? PUBLICATIONS_GROUP : UNKNOWN_GROUP;
}

function walk(dir, prefix = '') {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (entry.isDirectory()) {
      files.push(...walk(path.join(dir, entry.name), relative));
    } else if (entry.name.endsWith('.sql')) {
      files.push(relative);
    }
  }
  return files;
}

function buildLoadOrder(existing, files) {
  const present = new Set(files);
  const seen = new Set();
  const groups = Array.from({ length: PUBLICATIONS_GROUP + 1 }, () => []);

  for (const file of existing) {
    if (!present.has(file) || seen.has(file)) continue;
    seen.add(file);
    groups[groupOf(file)].push(file);
  }
  for (const file of files) {
    if (seen.has(file)) continue;
    seen.add(file);
    groups[groupOf(file)].push(file);
  }

  return groups.flat();
}

function main() {
  const manifest = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
  const files = walk(SCHEMA_DIR).sort();
  const loadOrder = buildLoadOrder(manifest.loadOrder, files);

  const declared = new Set([...manifest.files, ...manifest.loadOrder]);
  const missing = files.filter((file) => !declared.has(file));
  const stale = [...declared].filter((file) => !files.includes(file));

  const before = JSON.stringify(manifest);
  manifest.loadOrder = loadOrder;
  manifest.files = files;
  const after = JSON.stringify(manifest);

  if (before === after) {
    if (CHECK_ONLY) console.log('pgdelta manifest is up to date');
    return;
  }

  if (CHECK_ONLY) {
    console.error('pgdelta manifest is stale:');
    if (missing.length) console.error(`  missing: ${missing.join(', ')}`);
    if (stale.length) console.error(`  stale: ${stale.join(', ')}`);
    console.error('Run: node scripts/generate_pgdelta_manifest.js');
    process.exit(1);
  }

  fs.writeFileSync(MANIFEST_PATH, `${JSON.stringify(manifest, null, 2)}\n`);
  console.log(
    `pgdelta manifest updated (${files.length} files, ${missing.length} added, ${stale.length} removed)`
  );
}

main();
