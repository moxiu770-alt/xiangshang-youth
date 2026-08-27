/** Authoritative mobile role, scope, and capability projection. */
export function createAuthClaimsService({ query, hasRole }) {
  const mobileEntryAllowedForRole = (roleCode) => ['parent', 'teacher'].includes(roleCode);

  async function authClaimsForUser(user) {
    const scopedRoles = await query(`SELECT ur.id AS "userRoleId", ur.role_id AS "roleId", r.code, r.name,
        ur.school_id AS "schoolId", ur.class_id AS "classId"
      FROM user_roles ur JOIN roles r ON r.id=ur.role_id
      LEFT JOIN schools scoped_school ON scoped_school.id=ur.school_id
      WHERE ur.user_id=$1 AND (ur.school_id IS NULL OR scoped_school.status='active')
      ORDER BY CASE r.code WHEN 'parent' THEN 1 WHEN 'teacher' THEN 2 WHEN 'principal' THEN 3 ELSE 4 END, ur.created_at, ur.id`, [user.id]);
    const roleRows = scopedRoles.rows;
    const roleIds = [...new Set(roleRows.map((row) => row.roleId))];
    const roleCapabilities = roleIds.length
      ? await query(`SELECT role_id AS "roleId", capability_code AS "capabilityCode" FROM role_capabilities WHERE role_id = ANY($1::text[])`, [roleIds])
      : { rows: [] };
    const overrides = await query(`SELECT capability_code AS "capabilityCode",allowed,
        school_id AS "schoolId",class_id AS "classId"
      FROM user_capability_overrides
      WHERE user_id=$1 AND (expires_at IS NULL OR expires_at>now())`, [user.id]);
    const capsByRole = new Map();
    for (const row of roleCapabilities.rows) {
      const current = capsByRole.get(row.roleId) || new Set();
      current.add(row.capabilityCode);
      capsByRole.set(row.roleId, current);
    }
    const groups = new Map();
    for (const row of roleRows) {
      const key = `${row.code}|${row.schoolId || ''}`;
      const current = groups.get(key) || {
        roleCode: row.code,
        name: row.name,
        schoolId: row.schoolId || null,
        campusIds: [],
        authorizedGradeIds: [],
        authorizedClassIds: [],
        capabilities: new Set()
      };
      if (row.classId && !current.authorizedClassIds.includes(row.classId)) current.authorizedClassIds.push(row.classId);
      for (const capability of capsByRole.get(row.roleId) || []) current.capabilities.add(capability);
      groups.set(key, current);
    }
    for (const group of groups.values()) {
      for (const override of overrides.rows) {
        if (override.schoolId && override.schoolId !== group.schoolId) continue;
        if (override.classId && !group.authorizedClassIds.includes(override.classId)) continue;
        if (override.allowed) group.capabilities.add(override.capabilityCode);
        else group.capabilities.delete(override.capabilityCode);
      }
    }
    const classIds = [...new Set([...groups.values()].flatMap((group) => group.authorizedClassIds))];
    const gradeRows = classIds.length
      ? await query('SELECT DISTINCT grade_id AS "gradeId" FROM classes WHERE id = ANY($1::text[])', [classIds])
      : { rows: [] };
    const gradeIds = gradeRows.rows.map((row) => row.gradeId);
    const accountRoles = [...groups.values()].map((group) => ({
      roleCode: group.roleCode,
      name: group.name,
      schoolId: group.schoolId,
      campusIds: group.campusIds,
      authorizedGradeIds: group.authorizedClassIds.length ? gradeIds : [],
      authorizedClassIds: group.authorizedClassIds,
      capabilities: [...group.capabilities].sort(),
      mobileEntryAllowed: mobileEntryAllowedForRole(group.roleCode)
    }));
    const primary = accountRoles[0] || { roleCode: 'parent', schoolId: null, capabilities: [], authorizedClassIds: [] };
    const schoolName = primary.schoolId ? (await query('SELECT name FROM schools WHERE id=$1', [primary.schoolId])).rows[0]?.name || '' : '';
    const roleLabels = { parent: '家长', teacher: '教师', principal: '校长', admin: '管理员' };
    return {
      claimsVersion: 1,
      activeRole: primary.roleCode,
      accountRoles,
      user: {
        id: user.id,
        name: user.name,
        phone: user.phone || '未绑定手机号',
        role: roleLabels[primary.roleCode] || primary.roleCode,
        roleCode: primary.roleCode,
        schoolId: primary.schoolId,
        schoolName,
        avatarInitials: String(user.name).slice(0, 1),
        authorizedGradeIds: primary.authorizedGradeIds || gradeIds,
        authorizedClassIds: primary.authorizedClassIds || [],
        capabilities: primary.capabilities || [],
        mobileEntryAllowed: mobileEntryAllowedForRole(primary.roleCode)
      },
      roles: accountRoles.map((role) => ({ code: role.roleCode, name: role.name, schoolId: role.schoolId, classIds: role.authorizedClassIds, capabilities: role.capabilities }))
    };
  }

  async function userHasCapability(user, capability, schoolId = null, classId = null) {
    if (hasRole(user, 'admin', 'principal')) return true;
    const claims = await authClaimsForUser(user);
    return claims.accountRoles.some((role) => {
      if (role.roleCode !== 'teacher' || !role.capabilities.includes(capability)) return false;
      if (schoolId && role.schoolId && role.schoolId !== schoolId) return false;
      if (classId && !role.authorizedClassIds.includes(classId)) return false;
      return true;
    });
  }

  return { authClaimsForUser, userHasCapability };
}
