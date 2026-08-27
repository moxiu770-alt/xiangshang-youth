import ExcelJS from 'exceljs';

const csvCell = (value) => String(value ?? '').trim();
const parseCsv = (source) => {
  const text = String(source || '').replace(/^\uFEFF/, '');
  const rows = [];
  let row = [];
  let cell = '';
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1];
    if (char === '"' && quoted && next === '"') { cell += '"'; index += 1; continue; }
    if (char === '"') { quoted = !quoted; continue; }
    if (char === ',' && !quoted) { row.push(cell); cell = ''; continue; }
    if ((char === '\n' || char === '\r') && !quoted) {
      if (char === '\r' && next === '\n') index += 1;
      row.push(cell); cell = '';
      if (row.some((value) => csvCell(value))) rows.push(row);
      row = [];
      continue;
    }
    cell += char;
  }
  if (cell || row.length) { row.push(cell); if (row.some((value) => csvCell(value))) rows.push(row); }
  if (rows.length < 2) return [];
  const headers = rows.shift().map((value) => csvCell(value).replace(/^\uFEFF/, ''));
  return rows.map((values) => Object.fromEntries(headers.map((header, index) => [header, csvCell(values[index])])))
    .filter((value) => Object.values(value).some(Boolean));
};

const importField = (row, ...names) => {
  for (const name of names) {
    if (row[name] !== undefined && csvCell(row[name])) return csvCell(row[name]);
  }
  return '';
};

const booleanCell = (value) => ['1', 'true', 'yes', '是', '重点帮扶', '重点'].includes(String(value || '').trim().toLowerCase());

const parseSpreadsheetRows = async (input) => {
  if (!input.fileBase64) return [];
  let bytes;
  try { bytes = Buffer.from(String(input.fileBase64), 'base64'); } catch { throw Object.assign(new Error('Excel 文件编码无效'), { status: 400, code: 'IMPORT_FILE_INVALID' }); }
  if (!bytes.length || bytes.length > 8 * 1024 * 1024) throw Object.assign(new Error('Excel 文件为空或超过 8MB'), { status: 400, code: 'IMPORT_FILE_TOO_LARGE' });
  try {
    const workbook = new ExcelJS.Workbook();
    await workbook.xlsx.load(bytes);
    const sheet = workbook.worksheets[0];
    if (!sheet || sheet.rowCount < 2) return [];
    const headers = sheet.getRow(1).values.slice(1).map((value) => String(value ?? '').trim());
    const rows = [];
    sheet.eachRow((row, rowNumber) => {
      if (rowNumber === 1) return;
      const values = row.values.slice(1);
      const item = Object.fromEntries(headers.map((header, index) => [header, values[index] == null ? '' : String(values[index])]))
      if (Object.values(item).some(Boolean)) rows.push(item);
    });
    return rows;
  } catch {
    throw Object.assign(new Error('Excel 文件无法解析，请使用 .xlsx 格式'), { status: 400, code: 'IMPORT_FILE_INVALID' });
  }
};

export async function normalizeStudentImportRows(user, input, { query, schoolAllowed }) {
  const rawRows = Array.isArray(input.rows) ? input.rows : (input.fileBase64 ? await parseSpreadsheetRows(input) : parseCsv(input.csvText || input.csv || ''));
  if (!rawRows.length) throw Object.assign(new Error('导入文件没有有效数据行'), { status: 400, code: 'IMPORT_EMPTY' });
  if (rawRows.length > 5000) throw Object.assign(new Error('单次最多导入 5000 名学生'), { status: 400, code: 'IMPORT_TOO_LARGE' });
  const normalized = [];
  const errors = [];
  const seen = new Set();
  for (const [index, row] of rawRows.entries()) {
    const line = index + 2;
    const schoolValue = importField(row, 'schoolId', '学校ID', '学校') || input.schoolId || '';
    const gradeValue = importField(row, 'gradeId', '年级ID', 'grade', '年级');
    const classValue = importField(row, 'classId', '班级ID', 'class', '班级');
    const studentNo = importField(row, 'studentNo', '学号', '学生编号');
    const name = importField(row, 'name', '姓名', '学生姓名');
    const school = schoolValue ? (await query('SELECT id,name,status FROM schools WHERE id=$1 OR name=$1 LIMIT 1', [schoolValue])).rows[0] : null;
    const grade = school && gradeValue ? (await query(`SELECT id,name,school_id,period_id FROM grades WHERE school_id=$1 AND (id=$2 OR name=$2) ORDER BY academic_year DESC NULLS LAST LIMIT 1`, [school.id, gradeValue])).rows[0] : null;
    const classRow = school && classValue ? (await query(`SELECT id,name,school_id,grade_id,period_id FROM classes WHERE school_id=$1 AND (id=$2 OR name=$2) ${grade ? 'AND grade_id=$3' : ''} ORDER BY name LIMIT 1`, grade ? [school.id, classValue, grade.id] : [school.id, classValue])).rows[0] : null;
    const rowErrors = [];
    if (!schoolValue) rowErrors.push('缺少学校');
    else if (!school) rowErrors.push('学校不存在');
    else if (school.status !== 'active') rowErrors.push('学校已停用');
    else if (!schoolAllowed(user, school.id)) rowErrors.push('无权操作该学校');
    if (!gradeValue) rowErrors.push('缺少年级');
    else if (!grade) rowErrors.push('年级不存在或不属于该学校');
    if (!classValue) rowErrors.push('缺少班级');
    else if (!classRow) rowErrors.push('班级不存在或不属于该年级');
    if (!name) rowErrors.push('缺少姓名');
    const birthDate = importField(row, 'birthDate', '出生日期', '生日');
    if (birthDate && !/^\d{4}-\d{2}-\d{2}$/.test(birthDate)) rowErrors.push('出生日期必须是 YYYY-MM-DD');
    const key = `${school?.id || schoolValue}:${studentNo || `${classRow?.id || classValue}:${name}`}`;
    if (seen.has(key)) rowErrors.push('文件内存在重复学生');
    seen.add(key);
    if (rowErrors.length) errors.push({ line, name, errors: rowErrors });
    else normalized.push({
      schoolId: school.id,
      schoolName: school.name,
      gradeId: grade.id,
      gradeName: grade.name,
      classId: classRow.id,
      className: classRow.name,
      periodId: classRow.period_id || grade.period_id || input.periodId || null,
      studentNo: studentNo || null,
      name,
      gender: importField(row, 'gender', '性别'),
      birthDate: birthDate || null,
      region: importField(row, 'region', '地区'),
      isPovertyArea: booleanCell(importField(row, 'isPovertyArea', '重点帮扶', '重点地区'))
    });
  }
  return { rawRows, normalized, errors };
}

