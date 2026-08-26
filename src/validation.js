export function validationError(code, message) {
  return Object.assign(new Error(message), { status: 400, code });
}

export function requiredString(value, field, { max = 200 } = {}) {
  // Do not coerce arrays/objects into strings such as "[object Object]".
  // Request fields are JSON scalar contracts; accepting non-strings makes
  // malformed payloads look valid and can bypass downstream validation.
  if (typeof value !== 'string') throw validationError('INVALID_ARGUMENT', `${field}必须是文本`);
  const normalized = value.trim();
  if (!normalized) throw validationError('INVALID_ARGUMENT', `${field}不能为空`);
  if (normalized.length > max) throw validationError('INVALID_ARGUMENT', `${field}长度不能超过${max}个字符`);
  return normalized;
}

export function assertPhone(value) {
  const phone = requiredString(value, '手机号', { max: 20 });
  if (!/^1\d{10}$/.test(phone)) throw validationError('PHONE_INVALID', '手机号格式不正确');
  return phone;
}

export function assertPassword(value, field = '密码') {
  if (typeof value !== 'string') throw validationError('PASSWORD_INVALID', `${field}必须是文本`);
  const password = value;
  if (password.length < 8 || password.length > 128) throw validationError('PASSWORD_INVALID', `${field}长度必须在 8 到 128 位之间`);
  return password;
}

export function assertEnum(value, allowed, field) {
  if (!allowed.includes(value)) throw validationError('INVALID_ARGUMENT', `${field}不合法`);
  return value;
}
