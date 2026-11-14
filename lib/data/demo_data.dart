import '../models/transport.dart';

class DemoData {
  static const staff = [
    Staff('s1', '김다정'),
    Staff('s2', '이온유'),
    Staff('s3', '박여유', unavailableWeekdays: {DateTime.friday}),
  ];

  static const passengers = [
    Passenger('p1', '가상 어르신 A', '가상마을 햇살길 1', '승하차 시 천천히 안내'),
    Passenger('p2', '가상 어르신 B', '가상마을 햇살길 2', '도착 후 초인종으로 안내'),
    Passenger('p3', '가상 어르신 C', '가상마을 햇살길 3', '현관 앞에서 탑승'),
    Passenger('p4', '가상 어르신 D', '가상마을 나무길 1', '승하차 시 천천히 안내'),
    Passenger('p5', '가상 어르신 E', '가상마을 나무길 2', '정문 앞에서 탑승'),
  ];

  static const vehicles = [
    Vehicle('v1', '햇살 1호', 3),
    Vehicle('v2', '나무 2호', 3),
    Vehicle('v3', '예비 3호', 2),
  ];

  static final List<BaseRoute> baseRoutes = List.unmodifiable([
    for (final period in TransportPeriod.values) ...[
      BaseRoute(
        id: '${period.name}-a',
        name: '햇살 A코스',
        period: period,
        staffId: 's1',
        vehicleId: 'v1',
        passengerIds: period == TransportPeriod.morning
            ? ['p1', 'p2', 'p3']
            : ['p3', 'p1', 'p2'],
      ),
      BaseRoute(
        id: '${period.name}-b',
        name: '나무 B코스',
        period: period,
        staffId: 's2',
        vehicleId: 'v2',
        passengerIds: period == TransportPeriod.morning
            ? ['p4', 'p5']
            : ['p5', 'p4'],
      ),
    ],
  ]);
}
