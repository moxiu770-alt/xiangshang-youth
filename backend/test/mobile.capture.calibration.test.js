import assert from 'node:assert/strict';
import { test } from 'node:test';
import { calibrationProfilesFromJson, validateCalibrationProfileRegistry, validateMarkerPnpProfile } from '../src/mobileCaptureCalibration.js';

const profile = { profileId: 'ios-15-rear1x-v1', status: 'active', boardId: 'uy-charuco-v1', intrinsicsId: 'ios-15-rear1x-1080-v1', lensId: 'rear-1x', resolution: '1920x1080', expiresAt: '2099-01-01T00:00:00Z' };
const evidence = { profileId: profile.profileId, boardId: profile.boardId, intrinsicsId: profile.intrinsicsId, lensId: profile.lensId, resolution: profile.resolution };

test('physical PnP evidence must match an active approved phone calibration profile', () => {
  assert.equal(validateMarkerPnpProfile(evidence, [profile]).valid, true);
  assert.equal(validateMarkerPnpProfile({ ...evidence, resolution: '1280x720' }, [profile]).code, 'CAPTURE_CALIBRATION_PROFILE_MISMATCH');
  assert.equal(validateMarkerPnpProfile({ ...evidence, profileId: 'unknown' }, [profile]).code, 'CAPTURE_CALIBRATION_PROFILE_UNREGISTERED');
  assert.equal(validateMarkerPnpProfile({ ...evidence, profileId: '' }, [profile]).code, 'CAPTURE_CALIBRATION_PROFILE_REQUIRED');
});

test('empty or malformed operational registry fails closed', () => {
  assert.deepEqual(calibrationProfilesFromJson('not-json'), []);
  assert.equal(validateMarkerPnpProfile(evidence, []).code, 'CAPTURE_CALIBRATION_PROFILE_UNREGISTERED');
});

test('registry requires an approved versioned physical calibration record', () => {
  const registry = { schemaVersion: 'UY-MOBILE-CAPTURE-PROFILE-1.0', profiles: [{ ...profile, deviceModel: 'iPhone15,4', boardFamily: 'charuco', boardLayoutHash: 'a'.repeat(64), markerSizeMm: 30, boardWidthMm: 420, boardHeightMm: 594, intrinsicMatrix: [1200, 0, 960, 0, 1200, 540, 0, 0, 1], distortionCoefficients: [0.1, -0.2, 0, 0], approvedAt: '2026-08-28T00:00:00Z' }] };
  assert.equal(validateCalibrationProfileRegistry(registry).valid, true);
  assert.deepEqual(calibrationProfilesFromJson(registry), registry.profiles);
  assert.equal(validateCalibrationProfileRegistry({ ...registry, schemaVersion: 'old' }).valid, false);
  assert.equal(validateCalibrationProfileRegistry({ ...registry, profiles: [{ ...registry.profiles[0], boardLayoutHash: 'REPLACE_WITH_LAYOUT' }] }).valid, false);
  assert.equal(validateCalibrationProfileRegistry({ ...registry, profiles: [{ ...registry.profiles[0], intrinsicMatrix: [] }] }).valid, false);
});
