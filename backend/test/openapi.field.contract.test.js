import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import test from 'node:test';

const specification = await fs.readFile(new URL('../openapi.yaml', import.meta.url), 'utf8');
const fieldRoutes = [
  '/v1/field/bootstrap',
  '/v1/field/heartbeat',
  '/v1/field/commands',
  '/v1/field/commands/{commandId}/ack',
  '/v1/field/files/presign',
  '/v1/field/files/{fileId}/content',
  '/v1/field/queue/transition',
  '/v1/field/sessions',
  '/v1/field/sessions/{sessionId}/events',
  '/v1/field/sessions/{sessionId}/complete',
  '/v1/field/sync/batches'
];

test('OpenAPI documents every direct field-device endpoint with signed device authentication', () => {
  for (const route of fieldRoutes) {
    const section = specification.split(`  ${route}:\n`)[1]?.split('\n  /')[0] || '';
    assert.notEqual(section, '', `${route} must be documented`);
    assert.match(section, /fieldDeviceId: \[\], fieldDeviceTimestamp: \[\], fieldDeviceNonce: \[\], fieldDeviceBodyHash: \[\], fieldDeviceSignature: \[\]/, `${route} must require signed device headers and body hash`);
  }
});
