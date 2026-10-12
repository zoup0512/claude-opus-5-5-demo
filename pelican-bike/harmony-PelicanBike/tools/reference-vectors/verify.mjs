import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { buildGolden, GOLDEN_PATH, serializeGolden } from './generate.mjs';

const sha256 = (data) => createHash('sha256').update(data).digest('hex');

function firstMismatch(expected, actual, path = '$') {
  if (expected === actual) return null;
  if (typeof expected !== typeof actual) return { path, expected, actual };
  if (expected === null || actual === null) return { path, expected, actual };
  if (typeof expected !== 'object') return { path, expected, actual };
  if (Array.isArray(expected) !== Array.isArray(actual)) return { path, expected, actual };

  const expectedKeys = Object.keys(expected);
  const actualKeys = Object.keys(actual);
  if (expectedKeys.length !== actualKeys.length || expectedKeys.some((key, index) => key !== actualKeys[index])) {
    return { path, expectedKeys, actualKeys };
  }
  for (const key of expectedKeys) {
    const mismatch = firstMismatch(expected[key], actual[key], Array.isArray(expected) ? `${path}[${key}]` : `${path}.${key}`);
    if (mismatch) return mismatch;
  }
  return null;
}

async function main() {
  const storedText = await readFile(GOLDEN_PATH, 'utf8');
  const stored = JSON.parse(storedText);
  const rebuilt = await buildGolden();
  const rebuiltText = serializeGolden(rebuilt);
  const mismatch = firstMismatch(stored, rebuilt);
  if (mismatch || storedText !== rebuiltText) {
    console.error('reference vectors do not match regenerated source results');
    console.error(JSON.stringify(mismatch || { path: '$', reason: 'serialization mismatch' }, null, 2));
    process.exitCode = 1;
    return;
  }
  console.log(`verified ${GOLDEN_PATH}`);
  console.log(`sha256 ${sha256(storedText)}`);
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : '';
if (invokedPath === import.meta.url) {
  main().catch((error) => {
    console.error(error.stack || error);
    process.exitCode = 1;
  });
}
