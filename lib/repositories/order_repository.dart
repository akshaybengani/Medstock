import '../models/order.dart';
import '../services/database_service.dart';

class OrderRepository {
  final DatabaseService _dbs;
  OrderRepository([DatabaseService? dbs])
      : _dbs = dbs ?? DatabaseService.instance;

  /// Newest first, with items attached — two queries total.
  Future<List<Order>> all() async {
    final db = await _dbs.database;

    final orderRows = await db.query('orders', orderBy: 'created_at DESC');
    final itemRows = await db.query('order_items', orderBy: 'id ASC');

    final byOrder = <int, List<OrderItem>>{};
    for (final row in itemRows) {
      final item = OrderItem.fromMap(row);
      if (item.orderId == null) continue;
      byOrder.putIfAbsent(item.orderId!, () => []).add(item);
    }

    return orderRows.map((row) {
      final id = row['id'] as int?;
      return Order.fromMap(
        row,
        items: id == null ? const [] : (byOrder[id] ?? const []),
      );
    }).toList();
  }

  Future<Order?> byId(int id) async {
    final db = await _dbs.database;
    final rows =
        await db.query('orders', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;

    final itemRows = await db.query(
      'order_items',
      where: 'order_id = ?',
      whereArgs: [id],
      orderBy: 'id ASC',
    );

    return Order.fromMap(
      rows.first,
      items: itemRows.map(OrderItem.fromMap).toList(),
    );
  }

  Future<Order> insert(Order order) async {
    final db = await _dbs.database;

    final id = await db.transaction((txn) async {
      final orderId = await txn.insert('orders', order.toMap()..remove('id'));
      for (final item in order.items) {
        await txn.insert(
          'order_items',
          item.copyWith(orderId: orderId).toMap()..remove('id'),
        );
      }
      return orderId;
    });

    return (await byId(id))!;
  }

  /// Updates the order row and replaces its item list.
  Future<Order> update(Order order) async {
    final db = await _dbs.database;
    final id = order.id!;

    await db.transaction((txn) async {
      await txn.update('orders', order.toMap(),
          where: 'id = ?', whereArgs: [id]);
      await txn
          .delete('order_items', where: 'order_id = ?', whereArgs: [id]);
      for (final item in order.items) {
        await txn.insert(
          'order_items',
          item.copyWith(orderId: id).toMap()..remove('id'),
        );
      }
    });

    return (await byId(id))!;
  }

  Future<void> updateStatusFields(Order order) async {
    final db = await _dbs.database;
    await db.update(
      'orders',
      {
        'status': order.status.name,
        'received_at': order.receivedAt?.toIso8601String(),
        'pharmacy_id': order.pharmacyId,
        'pharmacy_name': order.pharmacyName,
      },
      where: 'id = ?',
      whereArgs: [order.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _dbs.database;
    await db.delete('orders', where: 'id = ?', whereArgs: [id]);
  }
}
