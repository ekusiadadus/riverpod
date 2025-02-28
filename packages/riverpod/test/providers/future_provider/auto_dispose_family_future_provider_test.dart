import 'package:mockito/mockito.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

import '../../third_party/fake_async.dart';
import '../../utils.dart';

void main() {
  test('supports cacheTime', () async {
    final onDispose = cacheFamily<int, OnDisposeMock>(
      (key) => OnDisposeMock(),
    );

    await fakeAsync((async) async {
      final container = createContainer();
      final provider =
          FutureProvider.autoDispose.family<int, int>((ref, value) {
        ref.onDispose(onDispose(value));
        return value;
      }, cacheTime: const Duration(minutes: 5));

      final sub = container.listen<Future<int>>(
        provider(42).future,
        (previous, next) {},
      );

      expect(await sub.read(), 42);

      verifyZeroInteractions(onDispose(42));

      sub.close();

      async.elapse(const Duration(minutes: 2));
      await container.pump();

      verifyZeroInteractions(onDispose(42));

      async.elapse(const Duration(minutes: 3));
      await container.pump();

      verifyOnly(onDispose(42), onDispose(42)());
    });
  });

  test('specifies `from` & `argument` for related providers', () {
    final provider = FutureProvider.autoDispose.family<int, int>((ref, _) => 0);

    expect(provider(0).from, provider);
    expect(provider(0).argument, 0);

    expect(provider(0).future.from, provider);
    expect(provider(0).future.argument, 0);

    expect(provider(0).stream.from, provider);
    expect(provider(0).stream.argument, 0);
  });

  group('scoping an override overrides all the associated subproviders', () {
    test('when passing the provider itself', () async {
      final provider =
          FutureProvider.autoDispose.family<int, int>((ref, _) async => 0);
      final root = createContainer();
      final container = createContainer(parent: root, overrides: [provider]);

      expect(await container.read(provider(0).future), 0);
      expect(container.read(provider(0)), const AsyncData(0));
      expect(container.getAllProviderElementsInOrder(), [
        isA<ProviderElementBase>()
            .having((e) => e.origin, 'origin', provider(0)),
        isA<ProviderElementBase>()
            .having((e) => e.origin, 'origin', provider(0).future),
      ]);
      expect(root.getAllProviderElementsInOrder(), isEmpty);
    });

    test('can be auto-scoped', () async {
      final dep = Provider((ref) => 0);
      final provider = FutureProvider.family.autoDispose<int, int>(
        (ref, i) => ref.watch(dep) + i,
        dependencies: [dep],
      );
      final root = createContainer();
      final container = createContainer(
        parent: root,
        overrides: [dep.overrideWithValue(42)],
      );

      expect(container.read(provider(10)), const AsyncData(52));
      expect(container.read(provider(10).future), completion(52));

      expect(root.getAllProviderElements(), isEmpty);
    });

    test('when using provider.overrideWithProvider', () async {
      final provider = FutureProvider.autoDispose.family<int, int>((ref, _) {
        return 0;
      });
      final root = createContainer();
      final container = createContainer(parent: root, overrides: [
        provider.overrideWithProvider(
          (value) => FutureProvider.autoDispose((ref) => 42),
        ),
      ]);

      expect(await container.read(provider(0).future), 42);
      expect(container.read(provider(0)), const AsyncData(42));
      expect(root.getAllProviderElementsInOrder(), isEmpty);
      expect(container.getAllProviderElementsInOrder(), [
        isA<ProviderElementBase>()
            .having((e) => e.origin, 'origin', provider(0)),
        isA<ProviderElementBase>()
            .having((e) => e.origin, 'origin', provider(0).future),
      ]);
    });
  });

  test('works', () async {
    final provider = FutureProvider.autoDispose.family<int, int>((ref, a) {
      return Future.value(a * 2);
    });
    final container = createContainer();
    final listener = Listener<AsyncValue<int>>();

    container.listen(provider(21), listener, fireImmediately: true);

    verifyOnly(listener, listener(null, const AsyncValue.loading()));

    await container.pump();

    verifyOnly(
      listener,
      listener(const AsyncValue.loading(), const AsyncValue.data(42)),
    );
  });
}
