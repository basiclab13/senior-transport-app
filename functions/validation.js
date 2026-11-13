"use strict";
const { HttpsError } = require("firebase-functions/v2/https");
const idPattern = /^[A-Za-z0-9_-]{1,80}$/;
function reject(message) { throw new HttpsError("invalid-argument", message); }
function keys(value, allowed) {
  if (!value || typeof value !== "object" || Array.isArray(value) ||
      Object.keys(value).some((key) => !allowed.includes(key))) reject("지원하지 않는 데이터 필드입니다.");
}
function ids(value) {
  if (!Array.isArray(value) || value.some((id) => typeof id !== "string" || !idPattern.test(id)) ||
      new Set(value).size !== value.length) reject("ID 목록에 잘못된 값 또는 중복이 있습니다.");
}
function validateRequest(data) {
  keys(data, ["date", "period", "catalogVersion", "expectedVersion", "requestId", "routes", "absentIds", "excludedIds", "expectedAvailabilityVersions"]);
  if (typeof data.date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(data.date) ||
      !Number.isFinite(Date.parse(`${data.date}T00:00:00Z`)) ||
      new Date(`${data.date}T00:00:00Z`).toISOString().slice(0, 10) !== data.date ||
      !["morning", "afternoon"].includes(data.period) ||
      typeof data.catalogVersion !== 'string' || !idPattern.test(data.catalogVersion) ||
      typeof data.requestId !== 'string' || !idPattern.test(data.requestId) ||
      !Number.isSafeInteger(data.expectedVersion) || data.expectedVersion < 0) reject("날짜·시간대·버전·요청 ID를 확인해 주세요.");
  if (!Array.isArray(data.routes) || data.routes.length > 100 ||
      Buffer.byteLength(JSON.stringify(data)) > 700000) reject("일정 데이터 크기를 확인해 주세요.");
  ids(data.absentIds); ids(data.excludedIds);
  if (data.expectedAvailabilityVersions !== undefined) {
    const versions = data.expectedAvailabilityVersions;
    if (!versions || typeof versions !== 'object' || Array.isArray(versions) || Object.keys(versions).length > 100 ||
        Object.entries(versions).some(([id, version]) => !idPattern.test(id) || !Number.isSafeInteger(version) || version < 0)) reject('결근 정보 버전을 확인해 주세요.');
  }
}
function validateSchedule(data, catalog) {
  const { staff, vehicles, passengers, baseRoutes } = catalog;
  const expected = baseRoutes.filter((route) => route.period === data.period);
  const expectedIds = new Set(expected.flatMap((route) => route.passengerIds));
  const removed = [...data.absentIds, ...data.excludedIds];
  if (new Set(removed).size !== removed.length || removed.some((id) => !expectedIds.has(id))) reject("결석·제외 상태를 확인해 주세요.");
  const usedStaff = new Set(), usedVehicles = new Set(), usedPassengers = new Set(), usedRoutes = new Set();
  const weekday = new Date(`${data.date}T00:00:00Z`).getUTCDay() || 7;
  const validMinute = (value) => Number.isInteger(value) && value >= 0 && value < 1440;
  for (const route of data.routes) {
    keys(route, ["baseRouteId", "staffId", "vehicleId", "passengerIds", "estimatedVisitMinutes", "startMinute", "endMinute"]);
    const base = expected.find((item) => item.id === route.baseRouteId);
    if (!base || usedRoutes.has(route.baseRouteId)) reject("기본 코스 누락·중복 또는 다른 시간대 코스입니다.");
    usedRoutes.add(route.baseRouteId);
    const person = staff.find((item) => item.id === route.staffId && item.active === true);
    const vehicle = vehicles.find((item) => item.id === route.vehicleId);
    if (!person || (person.unavailableWeekdays || []).includes(weekday)) reject("근무할 수 없는 직원입니다.");
    if (usedStaff.has(route.staffId) || usedVehicles.has(route.vehicleId)) reject("직원 또는 차량이 같은 시간대에 중복 배정되었습니다.");
    usedStaff.add(route.staffId); usedVehicles.add(route.vehicleId);
    ids(route.passengerIds);
    if (!vehicle || !Number.isInteger(vehicle.passengerCapacity) || route.passengerIds.length > vehicle.passengerCapacity) reject("차량 참조 또는 정원을 확인해 주세요.");
    const times = route.estimatedVisitMinutes;
    if (!times || typeof times !== "object" || Array.isArray(times) ||
        Object.keys(times).some((id) => !route.passengerIds.includes(id))) reject("예상 방문 시각의 이용자 참조를 확인해 주세요.");
    const start = route.startMinute, end = route.endMinute;
    if ((start == null) !== (end == null) || (start != null &&
        (!validMinute(start) || !validMinute(end) || start >= end))) reject("예상 운행 시작·종료 시각을 확인해 주세요.");
    let previous = -1;
    for (const id of route.passengerIds) {
      if (!expectedIds.has(id) || !passengers.some((p) => p.id === id) || usedPassengers.has(id) || removed.includes(id)) reject("이용자 중복·참조·결석 배정을 확인해 주세요.");
      usedPassengers.add(id);
      if (Object.hasOwn(times, id)) {
        const minute = times[id];
        if (!validMinute(minute) || minute <= previous || (start != null && (minute < start || minute > end))) reject("예상 시각이 방문 순서 또는 운행 범위와 충돌합니다.");
        previous = minute;
      }
    }
  }
  if (usedRoutes.size !== expected.length || usedPassengers.size !== expectedIds.size - removed.length) reject("기본 코스 또는 송영 대상 이용자가 누락되었습니다.");
}
module.exports = { validateRequest, validateSchedule, idPattern };
