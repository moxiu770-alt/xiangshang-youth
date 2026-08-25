export const taskStatusTransitions = Object.freeze({
  '未签到': ['已签到', '缺席'],
  '已签到': ['未签到', '候测', '缺席'],
  '候测': ['测试中', '待补测', '缺席'],
  '测试中': ['已完成', '待复核', '待补测', '缺席'],
  '已完成': ['待复核', '待补测'],
  '待复核': ['已完成', '待补测'],
  '待补测': ['已签到', '缺席'],
  '缺席': ['已签到']
});

export const taskStatusAllowed = (from, to) => from === to || Boolean(taskStatusTransitions[from]?.includes(to));
export const hasRole = (user, ...roles) => user?.roles.some((item) => roles.includes(item.code));
export const schoolAllowed = (user, schoolId) => hasRole(user, 'admin') || user?.roles.some((item) => item.school_id === schoolId);
export const teacherClassIds = (user, schoolId) => user?.roles.filter((item) => item.code === 'teacher' && item.school_id === schoolId && item.class_id).map((item) => item.class_id) || [];
export const schoolStaffAllowed = (user, schoolId) => hasRole(user, 'admin', 'principal', 'teacher') && schoolAllowed(user, schoolId);
export const parentOnly = (user) => hasRole(user, 'parent') && !hasRole(user, 'admin', 'principal', 'teacher');
export const teacherOnly = (user) => hasRole(user, 'teacher') && !hasRole(user, 'admin', 'principal');
