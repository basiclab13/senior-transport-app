'use strict';

const { isDeepStrictEqual } = require('node:util');
const { createHash } = require('node:crypto');

const EXPECTED_PROJECT = 'senior-transport-app';
const EXPECTED_VERSION = 'deploy-test-v1';
const EXPECTED_IDS = {
  staff: ['s1', 's2', 's3'], vehicles: ['v1', 'v2', 'v3'],
  passengers: ['p1', 'p2', 'p3', 'p4', 'p5'],
  baseRoutes: ['morning-a', 'morning-b', 'afternoon-a', 'afternoon-b'],
};
const META = { ready: true, fictional: true, schemaVersion: 1 };

class RegistrationError extends Error {
  constructor(code, message, report) { super(message); this.code = code; this.report = report; }
}
function fail(message) { throw new RegistrationError('INVALID_MANIFEST', message); }
function object(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function exactKeys(value, keys, label) {
  if (!object(value) || !isDeepStrictEqual(Object.keys(value).sort(), [...keys].sort())) fail(`${label}: 필드 구성이 올바르지 않습니다.`);
}
function string(value, label) { if (typeof value !== 'string' || !value.trim()) fail(`${label}: 비어 있지 않은 문자열이 필요합니다.`); }
function uniqueIds(values, label) {
  if (!Array.isArray(values) || values.some((id) => typeof id !== 'string') || new Set(values).size !== values.length) fail(`${label}: ID 배열을 확인해 주세요.`);
}
function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (object(value)) return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  return value;
}

function makePlan(manifest) {
  exactKeys(manifest, ['projectId', 'databaseId', 'catalogVersion', 'catalogMetadata', 'collections', 'settings'], 'manifest');
  if (manifest.projectId !== EXPECTED_PROJECT || manifest.databaseId !== '(default)' || manifest.catalogVersion !== EXPECTED_VERSION) fail('기준 프로젝트·기본 DB·catalog 버전이 일치하지 않습니다.');
  if (!isDeepStrictEqual(manifest.catalogMetadata, META) ||
      !isDeepStrictEqual(manifest.settings, { documentPath: 'settings/schedules', fields: { catalogVersion: EXPECTED_VERSION } })) fail('부모 메타데이터 또는 settings 설정이 올바르지 않습니다.');
  exactKeys(manifest.collections, Object.keys(EXPECTED_IDS), 'collections');
  const documents = [];
  for (const [name, expectedIds] of Object.entries(EXPECTED_IDS)) {
    const items = manifest.collections[name];
    if (!Array.isArray(items) || items.length !== expectedIds.length || items.some((item) => !object(item)) ||
        !isDeepStrictEqual(items.map((item) => item.id).sort(), [...expectedIds].sort())) fail(`${name}: 기준 문서 ID·개수가 일치하지 않습니다. 부하 테스트 데이터는 등록할 수 없습니다.`);
    for (const item of items) {
      if (name === 'staff') {
        exactKeys(item, ['id', 'name', 'active', 'unavailableWeekdays'], 'staff');
        if (item.active !== true || !Array.isArray(item.unavailableWeekdays) ||
            item.unavailableWeekdays.some((day) => !Number.isInteger(day) || day < 1 || day > 7) ||
            new Set(item.unavailableWeekdays).size !== item.unavailableWeekdays.length) fail('직원 활성 상태·근무 불가 요일 타입을 확인해 주세요.');
      } else if (name === 'vehicles') {
        exactKeys(item, ['id', 'name', 'passengerCapacity'], 'vehicles');
        if (!Number.isInteger(item.passengerCapacity) || item.passengerCapacity < 1) fail('차량 정원은 양의 정수여야 합니다.');
      } else if (name === 'passengers') {
        exactKeys(item, ['id', 'name', 'address', 'note'], 'passengers');
        string(item.address, 'address');
        if (typeof item.note !== 'string') fail('note는 문자열이어야 합니다.');
      } else {
        exactKeys(item, ['id', 'name', 'period', 'staffId', 'vehicleId', 'passengerIds'], 'baseRoutes');
        if (!['morning', 'afternoon'].includes(item.period) || !item.id.startsWith(`${item.period}-`) ||
            !EXPECTED_IDS.staff.includes(item.staffId) || !EXPECTED_IDS.vehicles.includes(item.vehicleId)) fail('기본 코스의 시간대·직원·차량 참조가 올바르지 않습니다.');
        uniqueIds(item.passengerIds, 'passengerIds');
        if (item.passengerIds.some((id) => !EXPECTED_IDS.passengers.includes(id))) fail('존재하지 않는 이용자 참조입니다.');
        const vehicle = manifest.collections.vehicles.find((v) => v.id === item.vehicleId);
        if (item.passengerIds.length > vehicle.passengerCapacity) fail('기본 코스가 차량 정원을 초과합니다.');
      }
      string(item.name, 'name');
      const { id, ...data } = item;
      documents.push({ path: `catalogs/${EXPECTED_VERSION}/${name}/${id}`, data });
    }
  }
  for (const period of ['morning', 'afternoon']) {
    const routes = manifest.collections.baseRoutes.filter((r) => r.period === period);
    for (const property of ['staffId', 'vehicleId']) if (new Set(routes.map((r) => r[property])).size !== routes.length) fail('같은 시간대 직원·차량 중복 배정입니다.');
    const ids = routes.flatMap((r) => r.passengerIds);
    if (!isDeepStrictEqual([...ids].sort(), [...EXPECTED_IDS.passengers].sort())) fail('시간대별 이용자 누락·중복 배정입니다.');
  }
  return {
    projectId: EXPECTED_PROJECT, databaseId: '(default)', catalogVersion: EXPECTED_VERSION,
    parentPath: `catalogs/${EXPECTED_VERSION}`, settingsPath: 'settings/schedules',
    metadata: META, settingsFields: { catalogVersion: EXPECTED_VERSION }, documents,
    counts: Object.fromEntries(Object.entries(EXPECTED_IDS).map(([name, ids]) => [name, ids.length])),
    manifestSha256: createHash('sha256').update(JSON.stringify(canonical(manifest))).digest('hex'),
  };
}

async function readState(db, plan, tx) {
  const get = (reference) => tx ? tx.get(reference) : reference.get();
  const parent = await get(db.doc(plan.parentPath));
  const settings = await get(db.doc(plan.settingsPath));
  const children = new Map();
  for (const name of Object.keys(EXPECTED_IDS)) {
    const result = await get(db.collection(`${plan.parentPath}/${name}`));
    for (const doc of result.docs) children.set(doc.ref.path, doc.data());
  }
  // One equality field: no composite index or Auth export is required.
  const accounts = await get(db.collection('users').where('active', '==', true));
  return { parent: parent.exists ? parent.data() : null,
    settings: settings.exists ? settings.data() : null,
    children, activeAccounts: accounts.docs.map((doc) => doc.data()) };
}

function assess(plan, state) {
  const issues = [];
  const missing = [];
  let identical = 0;
  const expected = new Map(plan.documents.map((doc) => [doc.path, doc.data]));
  for (const doc of plan.documents) {
    if (!state.children.has(doc.path)) missing.push(doc);
    else if (isDeepStrictEqual(state.children.get(doc.path), doc.data)) identical++;
    else issues.push({ code: 'DOCUMENT_CONFLICT', path: doc.path, guidance: '기존 값이 기준 데이터와 다릅니다. 자동 덮어쓰기·삭제하지 않습니다. Console에서 별도 검토해 주세요.' });
  }
  for (const path of state.children.keys()) if (!expected.has(path)) issues.push({code: 'UNEXPECTED_DOCUMENT', path, guidance: '기준 15개 이외의 기존 문서가 있습니다. 자동으로 삭제하거나 섞지 않습니다.'});
  if (state.parent !== null) {
    const arrays = Object.entries(state.parent).filter(([, value]) => Array.isArray(value)).map(([name]) => name);
    for (const name of arrays) issues.push({ code: 'PARENT_ARRAY_FIELD', path: plan.parentPath,
      field: name, guidance: ['staff','vehicles','passengers','baseRoutes'].includes(name)
        ? '이 값은 부모의 배열 필드가 아니라 같은 이름의 하위 컬렉션 문서로 등록해야 합니다. 자동 수정하지 않습니다.'
        : '부모에는 ready(boolean), fictional(boolean), schemaVersion(integer) 메타데이터만 둡니다. 직원 요일 배열은 staff 문서, 방문 순서 배열은 baseRoutes 문서에 둡니다. 자동 수정하지 않습니다.' });
    if (!isDeepStrictEqual(state.parent, plan.metadata)) issues.push({ code: 'PARENT_CONFLICT', path: plan.parentPath,
      guidance: '기존 부모의 필드·타입·값이 최종 기준과 다릅니다. ready:false도 자동 변경하지 않습니다. 자식 문서 검증 없이 ready를 true로 바꾸지 마세요.' });
    if (missing.length) issues.push({ code: 'EXISTING_PARENT_INCOMPLETE', path: plan.parentPath,
      guidance: '기존 부모가 있지만 자식 문서가 미완성입니다. 이 상태에 자동으로 이어 쓰거나 활성화하지 않습니다.' });
  }
  if (state.settings !== null) {
    if (state.settings.catalogVersion !== plan.catalogVersion) issues.push({ code: 'SETTINGS_CONFLICT', path: plan.settingsPath,
      guidance: '기존 settings 포인터를 변경하지 않습니다. catalog 전환은 별도 검토 작업입니다.' });
    else if (state.parent === null) issues.push({ code: 'POINTER_WITHOUT_PARENT', path: plan.settingsPath,
      guidance: '포인터가 이미 대상 catalog를 가리키지만 부모가 없습니다. 기존 활성화 상태를 별도 검토해 주세요.' });
  }
  const staff = new Set(plan.documents.filter((doc) => doc.path.includes('/staff/')).map((doc) => doc.path.split('/').at(-1)));
  const staffAccounts = state.activeAccounts.filter((account) => account.role === 'staff');
  const invalidAccounts = staffAccounts.filter((account) => typeof account.staffId !== 'string' || !staff.has(account.staffId));
  if (invalidAccounts.length) issues.push({ code: 'STAFF_ACCOUNT_MAPPING', count: invalidAccounts.length,
    guidance: '일부 활성 직원 계정의 staffId가 기준 직원 ID와 연결되지 않습니다. users를 자동 수정하지 않고 등록을 중단합니다.' });
  return { issues, missing, identical, checkedActiveStaffAccounts: staffAccounts.length,
    complete: issues.length === 0 && missing.length === 0 && state.parent !== null && state.settings !== null };
}

function report(plan, check, mode) {
  return { mode, projectId: plan.projectId, databaseId: plan.databaseId, catalogVersion: plan.catalogVersion,
    manifestSha256: plan.manifestSha256, baselineCounts: plan.counts,
    existingIdenticalChildDocuments: check.identical,
    plannedChildDocuments: check.missing.map((doc) => doc.path),
    checkedActiveStaffAccounts: check.checkedActiveStaffAccounts,
    issues: check.issues, alreadyRegistered: check.complete,
    createdChildDocuments: 0, createdMetadataDocuments: 0, activated: check.complete };
}

async function registerInitialCatalog(db, plan, { apply = false } = {}) {
  const check = assess(plan, await readState(db, plan));
  const result = report(plan, check, apply ? 'apply' : 'dry-run');
  if (check.issues.length) return { ...result, status: 'BLOCKED' };
  if (check.complete) return { ...result, status: 'ALREADY_REGISTERED', verification: 'passed' };
  if (!apply) return { ...result, status: 'DRY_RUN_OK', activated: false };
  let phase = 'stage';
  try {
    // Stage: create absent children only. Existing documents are NEVER changed.
    result.createdChildDocuments = await db.runTransaction(async (tx) => {
      const current = assess(plan, await readState(db, plan, tx));
      if (current.issues.length) throw new RegistrationError('CONFLICT', '사전 확인 후 충돌이 발생했습니다.', report(plan, current, 'apply'));
      for (const doc of current.missing) tx.create(db.doc(doc.path), doc.data);
      return current.missing.length;
    });
    phase = 'verify-children';
    const staged = assess(plan, await readState(db, plan));
    if (staged.issues.length || staged.missing.length) throw new RegistrationError('STAGED_VERIFICATION_FAILED', '자식 문서 검증이 실패했습니다.', report(plan, staged, 'apply'));
    phase = 'activate';
    // Activation re-reads ALL children and active staff accounts in its own
    // transaction, so a concurrent mutation prevents/retries this activation.
    result.createdMetadataDocuments = await db.runTransaction(async (tx) => {
      const state = await readState(db, plan, tx);
      const current = assess(plan, state);
      if (current.issues.length || current.missing.length) throw new RegistrationError('ACTIVATION_CONFLICT', '활성화 전 검증이 실패했습니다.', report(plan, current, 'apply'));
      let count = 0;
      if (state.parent === null) { tx.create(db.doc(plan.parentPath), plan.metadata); count++; }
      if (state.settings === null) { tx.create(db.doc(plan.settingsPath), plan.settingsFields); count++; }
      return count;
    });
    phase = 'verify-final';
    const final = assess(plan, await readState(db, plan));
    return { ...result, status: final.complete ? 'APPLIED' : 'VERIFICATION_FAILED',
      activated: final.complete, verification: final.complete ? 'passed' : 'failed',
      verifiedChildDocuments: final.identical, checkedActiveStaffAccounts: final.checkedActiveStaffAccounts,
      issues: final.issues };
  } catch (error) {
    // No destructive rollback. Child creation may have committed even when an
    // acknowledgement was lost; say unknown rather than falsely reporting 0.
    return { ...result, status: 'APPLY_FAILED', phase, activated: null,
      createdChildDocuments: phase === 'stage' ? null : result.createdChildDocuments,
      createdMetadataDocuments: phase === 'activate' ? null : result.createdMetadataDocuments,
      verification: 'not-completed', issues: error instanceof RegistrationError ? error.report?.issues || [] : [],
      errorCode: error instanceof RegistrationError ? error.code : 'FIRESTORE_OPERATION_FAILED',
      guidance: '자동 삭제·덮어쓰기하지 않았습니다. dry-run으로 서버 상태를 다시 확인하세요. 비활성 자식 문서만 남은 경우 값이 일치하면 안전하게 재실행할 수 있습니다.' };
  }
}

module.exports = { makePlan, assess, readState, registerInitialCatalog, RegistrationError, EXPECTED_PROJECT };
