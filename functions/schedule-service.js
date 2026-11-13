"use strict";
const { createHash } = require("node:crypto");
const { FieldValue } = require("firebase-admin/firestore");
const { HttpsError } = require("firebase-functions/v2/https");
const { validateRequest, validateSchedule, idPattern } = require("./validation");
const { absenceData } = require("./staff-absence-service");
const { validateExistingSchedule } = require("./existing-schedule");

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === "object") return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])]));
  return value;
}

async function confirm(db, uid, data) {
  if (!uid) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
  validateRequest(data);
  const scheduleId = `${data.date}_${data.period}`;
  const scheduleRef = db.doc(`schedules/${scheduleId}`);
  const commitRef = scheduleRef.collection("commits").doc(data.requestId);
  const hash = createHash("sha256").update(JSON.stringify(canonical(data))).digest("hex");
  return db.runTransaction(async (tx) => {
    // Every read (including catalog queries) precedes the first write.
    const [profile, existing, receipt, settings] = await tx.getAll(
      db.doc(`users/${uid}`), scheduleRef, commitRef, db.doc("settings/schedules"));
    if (profile.data()?.active !== true || profile.data()?.role !== "admin") throw new HttpsError("permission-denied", "관리자만 확정할 수 있습니다.");
    if (receipt.exists) {
      if (receipt.data().uid !== uid || receipt.data().hash !== hash) throw new HttpsError("already-exists", "같은 요청 ID를 다른 내용으로 사용할 수 없습니다.");
      return { scheduleId, version: receipt.data().version, requestId: data.requestId };
    }
    const old = existing.data();
    if (existing.exists) validateExistingSchedule(old, data.date, data.period);
    if ((old?.version ?? 0) !== data.expectedVersion) throw new HttpsError("aborted", "다른 관리자가 일정을 변경했습니다. 최신본을 다시 확인해 주세요.");
    if (data.catalogVersion !== (old?.catalogVersion || settings.data()?.catalogVersion)) throw new HttpsError("failed-precondition", "기본 데이터 버전이 변경되었습니다. 다시 불러와 주세요.");
    const catalogRef = db.doc(`catalogs/${data.catalogVersion}`);
    const metadata = await tx.get(catalogRef);
    if (metadata.data()?.ready !== true || metadata.data()?.fictional !== true) throw new HttpsError("failed-precondition", "등록된 가상 기본 데이터가 없습니다.");
    const catalog = {};
    for (const collection of ["staff", "vehicles", "passengers", "baseRoutes"]) {
      const query = await tx.get(catalogRef.collection(collection));
      catalog[collection] = query.docs.map((doc) => ({ ...doc.data(), id: doc.id }));
    }
    validateSchedule(data, catalog);
    const assigned = [...new Set(data.routes.map((r) => r.staffId))];
    const availability = assigned.length ? await tx.getAll(...assigned.map((id) => db.doc(`staffAvailability/${data.date}/staff/${id}`))) : [];
    for (let i = 0; i < assigned.length; i++) {
      const status = absenceData(availability[i], data.date, assigned[i]);
      if (status.unavailablePeriods.includes(data.period)) throw new HttpsError('failed-precondition', '결근 직원의 코스가 남아 있습니다. 재배정이 필요합니다.');
      if (data.expectedAvailabilityVersions !== undefined && data.expectedAvailabilityVersions[assigned[i]] !== status.version) {
        throw new HttpsError('aborted', '검토 후 결근 상태가 변경되었습니다. 최신 상태로 다시 검토해 주세요.');
      }
    }
    const version = data.expectedVersion + 1;
    const snapshot = {
      schemaVersion: 1, catalogVersion: data.catalogVersion, date: data.date, period: data.period,
      timezone: "Asia/Seoul", status: "confirmed", version,
      lastRequestId: data.requestId,
      routes: data.routes, absentIds: data.absentIds, excludedIds: data.excludedIds,
      confirmedBy: uid, confirmedAt: FieldValue.serverTimestamp(),
    };
    const currentStaff = new Set(data.routes.map((route) => route.staffId));
    const previousStaff = new Set((old?.routes || []).map((route) => route.staffId));
    tx.set(scheduleRef, snapshot);
    // Deletions and additions affect only this exact date + period.
    for (const staffId of previousStaff) {
      if (!idPattern.test(staffId)) throw new HttpsError("data-loss", "저장된 직원 ID를 확인해 주세요.");
      if (!currentStaff.has(staffId)) tx.delete(db.doc(`staffSchedules/${staffId}/days/${scheduleId}`));
    }
    for (const staffId of currentStaff) {
      const routes = data.routes.filter((route) => route.staffId === staffId);
      const passengerIds = new Set(routes.flatMap((route) => route.passengerIds));
      const baseIds = new Set(routes.map((route) => route.baseRouteId));
      const vehicleIds = new Set(routes.map((route) => route.vehicleId));
      const { confirmedBy, ...staffSnapshot } = snapshot;
      tx.set(db.doc(`staffSchedules/${staffId}/days/${scheduleId}`), {
        ...staffSnapshot, staffId, absentIds: [], excludedIds: [],
        // Only this staff member's presentation data, never another route.
        routes,
        catalog: {
          staff: catalog.staff.filter((s) => s.id === staffId),
          vehicles: catalog.vehicles.filter((v) => vehicleIds.has(v.id)),
          passengers: catalog.passengers.filter((p) => passengerIds.has(p.id)),
          baseRoutes: catalog.baseRoutes.filter((b) => baseIds.has(b.id)).map((b) => ({
            ...b, staffId, passengerIds: routes.find((r) => r.baseRouteId === b.id).passengerIds,
          })),
        },
      });
    }
    tx.create(commitRef, { uid, hash, version, requestId: data.requestId, confirmedAt: FieldValue.serverTimestamp() });
    return { scheduleId, version, requestId: data.requestId };
  });
}
module.exports = { confirm };
