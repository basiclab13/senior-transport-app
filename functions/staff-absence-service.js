"use strict";
const { createHash } = require('node:crypto');
const { FieldValue } = require('firebase-admin/firestore');
const { HttpsError } = require('firebase-functions/v2/https');
const { idPattern } = require('./validation');

function absenceData(doc, date, staffId) {
  if (!doc.exists) return { version: 0, unavailablePeriods: [] };
  const data = doc.data();
  if (data.schemaVersion !== 1 || data.date !== date || data.staffId !== staffId ||
      !Number.isSafeInteger(data.version) || data.version < 1 || !Array.isArray(data.unavailablePeriods) ||
      data.unavailablePeriods.some((p) => !['morning', 'afternoon'].includes(p)) ||
      new Set(data.unavailablePeriods).size !== data.unavailablePeriods.length) {
    throw new HttpsError('failed-precondition', '등록된 결근 정보의 형식을 확인해 주세요.');
  }
  return { version: data.version, unavailablePeriods: data.unavailablePeriods };
}

async function setStaffAbsence(db, uid, input) {
  if (!uid) throw new HttpsError('unauthenticated', '로그인이 필요합니다.');
  const allowed = ['date', 'staffId', 'periods', 'absent', 'expectedVersion', 'requestId', 'catalogVersion'];
  if (!input || typeof input !== 'object' || Array.isArray(input) ||
      Object.keys(input).some((key) => !allowed.includes(key)) ||
      typeof input.date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(input.date) ||
      !Number.isFinite(Date.parse(`${input.date}T00:00:00Z`)) ||
      new Date(`${input.date}T00:00:00Z`).toISOString().slice(0, 10) !== input.date ||
      !['staffId', 'requestId', 'catalogVersion'].every((key) => typeof input[key] === 'string' && idPattern.test(input[key])) ||
      typeof input.absent !== 'boolean' || !Number.isSafeInteger(input.expectedVersion) || input.expectedVersion < 0 ||
      !Array.isArray(input.periods) || input.periods.length < 1 || input.periods.length > 2 ||
      input.periods.some((p) => !['morning', 'afternoon'].includes(p)) || new Set(input.periods).size !== input.periods.length) {
    throw new HttpsError('invalid-argument', '결근 날짜·직원·시간대·버전을 확인해 주세요.');
  }
  const data = {date:input.date, staffId:input.staffId, periods:[...input.periods].sort(), absent:input.absent,
    expectedVersion:input.expectedVersion, requestId:input.requestId, catalogVersion:input.catalogVersion};
  const hash = createHash('sha256').update(JSON.stringify(data)).digest('hex');
  const ref = db.doc(`staffAvailability/${data.date}/staff/${data.staffId}`);
  const receiptRef = ref.collection('commits').doc(data.requestId);
  return db.runTransaction(async (tx) => {
    const [profile, existing, receipt, settings, morning, afternoon, metadata, staff] = await tx.getAll(
      db.doc(`users/${uid}`), ref, receiptRef, db.doc('settings/schedules'),
      db.doc(`schedules/${data.date}_morning`), db.doc(`schedules/${data.date}_afternoon`),
      db.doc(`catalogs/${data.catalogVersion}`), db.doc(`catalogs/${data.catalogVersion}/staff/${data.staffId}`));
    if (profile.data()?.role !== 'admin' || profile.data()?.active !== true) throw new HttpsError('permission-denied', '관리자만 결근을 등록·취소할 수 있습니다.');
    if (receipt.exists) {
      if (receipt.data().uid !== uid || receipt.data().hash !== hash) throw new HttpsError('already-exists', '다른 내용에 같은 요청 ID를 사용할 수 없습니다.');
      return receipt.data().result;
    }
    const allowedVersions = [settings.data()?.catalogVersion, morning.data()?.catalogVersion, afternoon.data()?.catalogVersion];
    if (!allowedVersions.includes(data.catalogVersion) || metadata.data()?.ready !== true ||
        metadata.data()?.fictional !== true || !staff.exists) throw new HttpsError('failed-precondition', '직원 기본 데이터와 연결된 일정 버전을 확인해 주세요.');
    const old = absenceData(existing, data.date, data.staffId);
    if (old.version !== data.expectedVersion) throw new HttpsError('aborted', '다른 관리자가 결근 상태를 변경했습니다. 최신 상태를 확인하고 다시 요청해 주세요.');
    const periods = new Set(old.unavailablePeriods);
    for (const period of data.periods) data.absent ? periods.add(period) : periods.delete(period);
    const result = {version:old.version + 1, unavailablePeriods:[...periods].sort()};
    // Never delete a cancelled record: monotonically increasing versions prevent ABA races.
    tx.set(ref, {schemaVersion:1, date:data.date, staffId:data.staffId, ...result,
      updatedBy:uid, updatedAt:FieldValue.serverTimestamp()});
    tx.create(receiptRef, {uid, hash, result, requestId:data.requestId, createdAt:FieldValue.serverTimestamp()});
    return result;
  });
}
module.exports = { setStaffAbsence, absenceData };
