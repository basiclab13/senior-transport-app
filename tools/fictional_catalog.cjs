"use strict";
// Development fixtures only. This module is never imported by the Flutter app.
function fictionalCatalog(scale = false) {
  const staff = [
    { id: 's1', name: '김다정', active: true, unavailableWeekdays: [] },
    { id: 's2', name: '이온유', active: true, unavailableWeekdays: [] },
    { id: 's3', name: '박여유', active: true, unavailableWeekdays: [5] },
  ];
  const passengers = [
    ['p1', '가상 어르신 A', '가상마을 햇살길 1', '승하차 시 천천히 안내'],
    ['p2', '가상 어르신 B', '가상마을 햇살길 2', '도착 후 초인종으로 안내'],
    ['p3', '가상 어르신 C', '가상마을 햇살길 3', '현관 앞에서 탑승'],
    ['p4', '가상 어르신 D', '가상마을 나무길 1', '승하차 시 천천히 안내'],
    ['p5', '가상 어르신 E', '가상마을 나무길 2', '정문 앞에서 탑승'],
  ].map(([id, name, address, note]) => ({id, name, address, note}));
  const vehicles = [
    {id: 'v1', name: '햇살 1호', passengerCapacity: 3},
    {id: 'v2', name: '나무 2호', passengerCapacity: 3},
    {id: 'v3', name: '예비 3호', passengerCapacity: 2},
  ];
  const baseRoutes = [];
  for (const period of ['morning', 'afternoon']) {
    baseRoutes.push({id: `${period}-a`, name: '햇살 A코스', period, staffId: 's1', vehicleId: 'v1',
      passengerIds: period === 'morning' ? ['p1','p2','p3'] : ['p3','p1','p2']});
    baseRoutes.push({id: `${period}-b`, name: '나무 B코스', period, staffId: 's2', vehicleId: 'v2',
      passengerIds: period === 'morning' ? ['p4','p5'] : ['p5','p4']});
  }
  if (scale) for (let i = 4; i <= 40; i++) {
    staff.push({id: `s${i}`, name: `가상 직원 ${i}`, active: true, unavailableWeekdays: []});
    vehicles.push({id: `v${i}`, name: `가상 차량 ${i}`, passengerCapacity: 4});
    const ids = [];
    for (let j = 0; j < 2; j++) {
      const id = `p${passengers.length + 1}`; ids.push(id);
      passengers.push({id, name: `가상 이용자 ${passengers.length + 1}`, address: `가상도시 테스트길 ${i}-${j}`, note: '가상 데이터'});
    }
    for (const period of ['morning', 'afternoon']) baseRoutes.push({id: `${period}-extra-${i}`,
      name: `가상 ${i}코스`, period, staffId: `s${i}`, vehicleId: `v${i}`, passengerIds: [...ids]});
  }
  return {staff, vehicles, passengers, baseRoutes};
}
async function registerCatalog(db, version, catalog) {
  // Keep each published version immutable; interrupted imports never become ready.
  const ref = db.doc(`catalogs/${version}`);
  if ((await ref.get()).exists) throw new Error('Catalog version already exists; use a new version');
  await ref.create({ready: false, fictional: true, schemaVersion: 1});
  const batch = db.batch();
  for (const [collection, items] of Object.entries(catalog)) for (const {id, ...data} of items) {
    batch.create(ref.collection(collection).doc(id), data);
  }
  batch.update(ref, {ready: true});
  batch.set(db.doc('settings/schedules'), {catalogVersion: version});
  await batch.commit();
}
module.exports = { fictionalCatalog, registerCatalog };
