'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {inspectEntry} = require('../../tools/verify-functions-build.cjs');

test('production discovery exposes only schedule callables without AI parameters or loaded AI code', () => {
  const manifest = inspectEntry();
  assert.deepEqual(Object.keys(manifest.endpoints).sort(), ['confirmSchedule', 'setStaffAbsence']);
  assert.deepEqual(manifest.params, []);
  assert.equal(manifest.aiLoaded, false);
  for (const endpoint of Object.values(manifest.endpoints)) {
    assert.deepEqual(endpoint.region, ['asia-northeast3']);
    assert.equal((endpoint.secretEnvironmentVariables || []).length, 0);
  }
});

test('demo Emulator discovery preserves AI callable and server Secret binding', () => {
  const manifest = inspectEntry(true, 'demo-senior-transport');
  assert.deepEqual(Object.keys(manifest.endpoints).sort(), ['confirmSchedule', 'setStaffAbsence', 'suggestSchedule']);
  assert.equal(manifest.aiLoaded, true);
  assert.ok(manifest.params.some(p => p.name === 'GEMINI_API_KEY' && p.type === 'secret'));
  assert.ok(manifest.params.some(p => p.name === 'GEMINI_MODEL'));
  const ai = manifest.endpoints.suggestSchedule;
  assert.equal(ai.timeoutSeconds, 90);
  assert.equal(ai.maxInstances, 1);
  assert.ok(ai.secretEnvironmentVariables.some(s => s.key === 'GEMINI_API_KEY'));
});

test('demo project without Emulator, and real project with Emulator flag, do not discover AI', () => {
  for (const manifest of [inspectEntry(false, 'demo-senior-transport'), inspectEntry(true)]) {
    assert.equal(manifest.endpoints.suggestSchedule, undefined);
    assert.deepEqual(manifest.params, []);
    assert.equal(manifest.aiLoaded, false);
  }
});
