/**
 * Authoritative matching rules for a phone + lens + resolution calibration
 * profile. Recognition itself remains on-device; this prevents arbitrary
 * client metadata from becoming a "PnP calibrated" server result.
 *
 * Operations provide approved profiles through
 * MOBILE_CAPTURE_CALIBRATION_PROFILES_JSON. It must be a versioned object
 * with a `profiles` list. Invalid/absent configuration fails closed, so no
 * child result can claim physical calibration accidentally.
 */
export const MOBILE_CAPTURE_PROFILE_SCHEMA_VERSION = 'UY-MOBILE-CAPTURE-PROFILE-1.0';

const text = (value) => typeof value === 'string' && value.trim() ? value.trim() : null;
const finiteArray = (value, minimumLength) => Array.isArray(value) && value.length >= minimumLength && value.every((entry) => Number.isFinite(Number(entry)));

export function calibrationProfilesFromJson(source = process.env.MOBILE_CAPTURE_CALIBRATION_PROFILES_JSON) {
  if (!source) return [];
  try {
    const parsed = typeof source === 'string' ? JSON.parse(source) : source;
    if (!parsed || parsed.schemaVersion !== MOBILE_CAPTURE_PROFILE_SCHEMA_VERSION) return [];
    const profiles = parsed.profiles;
    return Array.isArray(profiles) ? profiles.filter((profile) => profile && typeof profile === 'object') : [];
  } catch {
    return [];
  }
}

/** Pure validation shared by the request boundary and regression tests. */
export function validateMarkerPnpProfile(calibration, profiles = calibrationProfilesFromJson()) {
  const profileId = text(calibration?.profileId);
  if (!profileId) return { valid: false, code: 'CAPTURE_CALIBRATION_PROFILE_REQUIRED', message: '物理标定采集缺少已批准的设备标定配置编号' };
  const profile = profiles.find((item) => text(item.profileId) === profileId);
  if (!profile || profile.status !== 'active') return { valid: false, code: 'CAPTURE_CALIBRATION_PROFILE_UNREGISTERED', message: '该手机、镜头和分辨率未配置有效的物理标定参数' };
  for (const [field, label] of [['boardId', '标定板'], ['intrinsicsId', '相机内参'], ['lensId', '镜头'], ['resolution', '分辨率']]) {
    if (!text(calibration?.[field]) || text(calibration[field]) !== text(profile[field])) {
      return { valid: false, code: 'CAPTURE_CALIBRATION_PROFILE_MISMATCH', message: `${label}与已批准的设备标定配置不一致` };
    }
  }
  const expiresAt = profile.expiresAt ? Date.parse(profile.expiresAt) : null;
  if (expiresAt != null && (!Number.isFinite(expiresAt) || expiresAt <= Date.now())) return { valid: false, code: 'CAPTURE_CALIBRATION_PROFILE_EXPIRED', message: '该设备标定配置已过期，需要重新完成标定' };
  return { valid: true, profileId, profile };
}

/** Deployment-time validation. It never reads child evidence. */
export function validateCalibrationProfileRegistry(registry) {
  if (!registry || registry.schemaVersion !== MOBILE_CAPTURE_PROFILE_SCHEMA_VERSION || !Array.isArray(registry.profiles)) {
    return { valid: false, errors: ['标定配置缺少正确的 schemaVersion 或 profiles 列表'] };
  }
  const errors = [];
  const seen = new Set();
  for (const [index, profile] of registry.profiles.entries()) {
    const label = `profiles[${index}]`;
    const profileId = text(profile?.profileId);
    if (!profileId || seen.has(profileId)) errors.push(`${label} profileId 缺失或重复`);
    if (profileId) seen.add(profileId);
    for (const field of ['boardId', 'intrinsicsId', 'lensId', 'resolution', 'deviceModel', 'boardFamily', 'boardLayoutHash']) {
      if (!text(profile?.[field]) || text(profile[field]).includes('REPLACE_WITH')) errors.push(`${label}.${field} 缺失或仍为占位值`);
    }
    if (!['charuco', 'aruco', 'apriltag'].includes(profile?.boardFamily)) errors.push(`${label}.boardFamily 必须为 charuco、aruco 或 apriltag`);
    if (!finiteArray(profile?.intrinsicMatrix, 9) || Number(profile.intrinsicMatrix?.[0]) <= 0 || Number(profile.intrinsicMatrix?.[4]) <= 0) errors.push(`${label}.intrinsicMatrix 必须包含经批准的 3×3 相机内参，fx/fy 必须大于 0`);
    if (!finiteArray(profile?.distortionCoefficients, 4)) errors.push(`${label}.distortionCoefficients 必须包含至少 4 个畸变系数`);
    if (!Number.isFinite(Number(profile?.boardWidthMm)) || Number(profile.boardWidthMm) <= 0 || !Number.isFinite(Number(profile?.boardHeightMm)) || Number(profile.boardHeightMm) <= 0) errors.push(`${label}.boardWidthMm/boardHeightMm 必须为实测的正数`);
    if (!Number.isFinite(Number(profile?.markerSizeMm)) || Number(profile.markerSizeMm) <= 0) errors.push(`${label}.markerSizeMm 必须为实测的正数`);
    if (profile?.status !== 'active' && profile?.status !== 'retired') errors.push(`${label}.status 必须为 active 或 retired`);
    if (profile?.status === 'active' && (!Number.isFinite(Date.parse(profile?.approvedAt)) || !Number.isFinite(Date.parse(profile?.expiresAt)))) errors.push(`${label} 激活配置必须有可审计的 approvedAt 与 expiresAt`);
  }
  return { valid: errors.length === 0, errors };
}
