import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'forms.dart';
import 'auth_gate.dart';
import 'auth_session.dart';
import 'inventory_data.dart';
import 'inventory_repository.dart';
import 'inventory_theme.dart';
import 'room_page.dart';

export 'inventory_data.dart' show Asset, AssetStatus, DeviceIcon, Room;
export 'inventory_repository.dart'
    show InventoryRepository, DemoInventoryRepository, HttpInventoryRepository;
export 'room_page.dart' show Marker, RoomPage;

void main() => runApp(const InventoryApp());

class InventoryApp extends StatefulWidget {
  const InventoryApp({super.key, this.repository});
  final InventoryRepository? repository;

  @override
  State<InventoryApp> createState() => _InventoryAppState();
}

class _InventoryAppState extends State<InventoryApp> {
  final navigator = GlobalKey<NavigatorState>();
  late final InventoryRepository initialRepository =
      widget.repository ?? defaultRepository();
  late final AuthSession? session = initialRepository is HttpInventoryRepository
      ? AuthSession(base: (initialRepository as HttpInventoryRepository).base)
      : null;

  @override
  void dispose() {
    session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigator,
        title: 'Inventario TI',
        debugShowCheckedModeBanner: false,
        locale: const Locale('es', 'CO'),
        supportedLocales: const [Locale('es', 'CO')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: inventoryTheme(),
        home: session == null
            ? HomePage(repository: initialRepository)
            : AuthGate(
                session: session!,
                navigatorKey: navigator,
                homeBuilder: (repository, logout) =>
                    HomePage(repository: repository, onLogout: logout),
              ),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.repository, this.onLogout});
  final InventoryRepository? repository;
  final VoidCallback? onLogout;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final InventoryRepository repo =
      widget.repository ?? defaultRepository();
  List<Room>? rooms;
  Object? error;
  bool loading = true;
  bool presenting = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await repo.loadRooms();
      if (!mounted) return;
      setState(() {
        rooms = result;
        loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        error = err;
        loading = false;
      });
    }
  }

  Future<void> openRoom(Room room) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => RoomPage(
        room: room,
        repo: repo,
        editing: !presenting,
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
    ));
  }

  Future<void> addRoom() async {
    final room =
        await showAddRoomForm(context, repo: repo, existing: rooms ?? const []);
    if (room == null || !mounted) return;
    setState(() => rooms!.add(room));
    await openRoom(room);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          _TopBar(
            presenting: presenting,
            onLogout: widget.onLogout,
            onModeChanged: (value) => setState(() => presenting = value),
          ),
          Expanded(child: _body()),
        ]),
      ),
    );
  }

  Widget _body() {
    if (loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (error != null) {
      return _ErrorState(message: '$error', onRetry: load);
    }
    return _content(rooms!);
  }

  Widget _content(List<Room> rooms) {
    final text = Theme.of(context).textTheme;
    final total = rooms.fold(0, (sum, room) => sum + room.assets.length);
    final demo = repo is DemoInventoryRepository;
    return LayoutBuilder(builder: (context, bounds) {
      final wide = bounds.maxWidth >= 840;
      final gutter = wide ? 40.0 : 16.0;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(gutter, wide ? 48 : 24, gutter, 40),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                    header: true,
                    child: Text('Espacios', style: text.headlineMedium)),
                const SizedBox(height: 6),
                Text(
                  '${rooms.length} salas · $total equipos'
                  '${demo ? ' · datos de demostración' : ''}',
                  style: text.bodyMedium?.copyWith(color: inkFaint),
                ),
                if (presenting) ...[
                  const SizedBox(height: 12),
                  const _PresentationNotice(),
                ],
                SizedBox(height: wide ? 32 : 24),
                _StatusOverview(rooms: rooms, wide: wide),
                SizedBox(height: wide ? 40 : 28),
                Semantics(
                  header: true,
                  child: Text('Salas',
                      style: text.titleMedium?.copyWith(color: inkSoft)),
                ),
                const SizedBox(height: 10),
                SheetSurface(
                  child: Column(children: [
                    for (final (index, room) in rooms.indexed) ...[
                      if (index > 0) const Divider(indent: 16, endIndent: 16),
                      _RoomRow(
                          room: room, wide: wide, onTap: () => openRoom(room)),
                    ],
                    if (!presenting) ...[
                      if (rooms.isNotEmpty)
                        const Divider(indent: 16, endIndent: 16),
                      AddRow(label: 'Agregar sala', onTap: addRoom),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SheetSurface(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off_outlined, color: inkSoft),
                  const SizedBox(height: 12),
                  Text('No se pudo cargar el inventario',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: inkFaint)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Reintentar'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar(
      {required this.presenting, required this.onModeChanged, this.onLogout});
  final VoidCallback? onLogout;
  final bool presenting;
  final ValueChanged<bool> onModeChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: sheet,
          border: Border(bottom: BorderSide(color: hairline)),
        ),
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const _Mark(),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Text('Inventario TI',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              const SizedBox(width: 8),
              // Shrinks rather than overflowing on narrow screens / big text.
              Flexible(
                flex: 3,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _ModeToggle(
                        presenting: presenting, onChanged: onModeChanged),
                  ),
                ),
              ),
              if (onLogout != null)
                IconButton(
                    tooltip: 'Cerrar sesión',
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout)),
            ]),
          ),
        ),
      );
}

/// Brand mark: a 2×2 block of ports on graphite.
class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(7),
          ),
          padding: const EdgeInsets.all(7),
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final lit in [true, false, false, true])
                DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        lit ? const Color(0xFF2EA66A) : const Color(0xFF5A606D),
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
            ],
          ),
        ),
      );
}

/// Two-state mode control: the current mode is always named.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.presenting, required this.onChanged});
  final bool presenting;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: well,
          borderRadius: BorderRadius.circular(radiusControl + 2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _ModeOption(
              label: 'Edición',
              selected: !presenting,
              onTap: () => onChanged(false)),
          _ModeOption(
              label: 'Presentación',
              selected: presenting,
              onTap: () => onChanged(true)),
        ]),
      );
}

class _ModeOption extends StatelessWidget {
  const _ModeOption(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: selected ? sheet : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusControl),
            side: BorderSide(color: selected ? hairline : Colors.transparent),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(radiusControl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  widthFactor: 1,
                  child: Text(label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: selected ? ink : inkFaint,
                      )),
                ),
              ),
            ),
          ),
        ),
      );
}

class _PresentationNotice extends StatelessWidget {
  const _PresentationNotice();

  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.visibility_outlined, size: 16, color: inkSoft),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Modo presentación: solo consulta. Los estados y el plano no se pueden cambiar.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: inkSoft),
          ),
        ),
      ]);
}

/// Inventory health in one line of instruments: total, proportion bar,
/// and a legend that doubles as the count per status.
class _StatusOverview extends StatelessWidget {
  const _StatusOverview({required this.rooms, required this.wide});
  final List<Room> rooms;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final counts = {
      for (final status in statusesBySeverity)
        status: rooms.fold(0, (total, room) => total + room.count(status)),
    };
    final total = counts.values.fold(0, (a, b) => a + b);
    final attention =
        counts[AssetStatus.faulty]! + counts[AssetStatus.offline]!;
    final verified = total - counts[AssetStatus.unknown]!;

    final headline = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          attention == 0
              ? verified == 0
                  ? 'Aún no hay equipos verificados'
                  : 'Sin fallas reportadas'
              : attention == 1
                  ? '1 equipo requiere atención'
                  : '$attention equipos requieren atención',
          style: text.titleLarge?.copyWith(
              color: attention == 0 ? ink : AssetStatus.faulty.color),
        ),
        const SizedBox(height: 4),
        Text('$verified de $total equipos verificados',
            style: text.bodyMedium?.copyWith(color: inkFaint)),
      ],
    );

    final legend = Wrap(spacing: 20, runSpacing: 10, children: [
      for (final status in statusesBySeverity)
        Semantics(
          label: '${counts[status]} ${status.label}',
          excludeSemantics: true,
          child: Opacity(
            opacity: counts[status]! > 0 ? 1 : .45,
            child: StatusTag(status, count: counts[status]),
          ),
        ),
    ]);

    return SheetSurface(
      child: Padding(
        padding: EdgeInsets.all(wide ? 24 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: headline),
            const SizedBox(height: 18),
            if (total > 0) _ProportionBar(counts: counts),
            const SizedBox(height: 16),
            legend,
          ],
        ),
      ),
    );
  }
}

class _ProportionBar extends StatelessWidget {
  const _ProportionBar({required this.counts});
  final Map<AssetStatus, int> counts;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          height: 6,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, status)
                in statusesBySeverity.where((s) => counts[s]! > 0).indexed) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                flex: counts[status]!,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: status.led,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ]),
        ),
      );
}

class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.room, required this.wide, required this.onTap});
  final Room room;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = room.assets.length;
    final statuses =
        statusesBySeverity.where((status) => room.count(status) > 0);
    final tags = Wrap(spacing: 14, runSpacing: 6, children: [
      for (final status in statuses)
        StatusTag(status, count: room.count(status)),
    ]);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          ExcludeSemantics(
            child: SizedBox(
              width: wide ? 88 : 64,
              height: wide ? 56 : 48,
              child: CustomPaint(painter: _RoomThumbnail(room.assets)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(room.name, style: text.titleMedium),
                const SizedBox(height: 2),
                Text(total == 1 ? '1 equipo' : '$total equipos',
                    style: text.bodySmall),
                if (!wide && statuses.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  tags,
                ],
              ],
            ),
          ),
          if (wide) ...[
            const SizedBox(width: 16),
            Flexible(
                flex: 2,
                child: Align(alignment: Alignment.centerRight, child: tags)),
          ],
          const SizedBox(width: 12),
          const Icon(Icons.chevron_right_rounded, color: inkGhost),
        ]),
      ),
    );
  }
}

/// Miniature of the room plan: the real asset positions as LEDs.
class _RoomThumbnail extends CustomPainter {
  _RoomThumbnail(List<Asset> assets)
      : points = [for (final asset in assets) (asset.position, asset.status)];
  final List<(Offset, AssetStatus)> points;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(.5), const Radius.circular(6));
    canvas.drawRRect(rect, Paint()..color = well);
    final dot = Paint()..color = hairlineStrong;
    for (var x = 8.0; x < size.width - 4; x += 8) {
      for (var y = 8.0; y < size.height - 4; y += 8) {
        canvas.drawCircle(Offset(x, y), .6, dot);
      }
    }
    for (final (position, status) in points) {
      final center = Offset(8 + position.dx * (size.width - 16),
          8 + position.dy * (size.height - 16));
      if (status == AssetStatus.offline) {
        canvas.drawCircle(
            center,
            3,
            Paint()
              ..color = status.led
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4);
      } else {
        canvas.drawCircle(center, 3.4, Paint()..color = status.led);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoomThumbnail oldDelegate) => true;
}
