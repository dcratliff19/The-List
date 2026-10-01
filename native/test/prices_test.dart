import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:the_list/store.dart';

void main() {
  test(
    'prices use exact cents, separate currencies and exclude removed links',
    () {
      final store = Store(
        Directory.systemTemp,
        database: sqlite3.openInMemory(),
      );
      addTearDown(store.dispose);
      final p = store.create('project', '', {'title': 'Budget'});
      final first = store.create('link', p, {
        'title': 'First',
        'price': '0.10',
        'currency': 'USD',
      });
      store.create('link', p, {
        'title': 'Second',
        'price': '0.20',
        'currency': 'USD',
      });
      store.create('link', p, {
        'title': 'Euro',
        'price': '3.00',
        'currency': 'EUR',
      });
      store.create('link', p, {'title': 'Unpriced'});
      expect(store.projectTotals(p), {'USD': 30, 'EUR': 300});
      store.update(store.get(first)!, {'deleted': true});
      expect(store.projectTotals(p)['USD'], 20);
      store.update(store.get(first)!, {'deleted': false, 'price': ''});
      expect(store.projectTotals(p)['USD'], 20);
      store.update(store.get(first)!, {'price': '0.00'});
      expect(store.get(first)!.priceLabel, 'USD 0.00');
      expect(Entry.parsePrice('12.3'), 1230);
      for (final invalid in ['-1', '1.234', 'NaN', '1,000', '1000000000']) {
        expect(() => Entry.parsePrice(invalid), throwsFormatException);
      }
    },
  );
}
