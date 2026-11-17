import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'asset_panel.dart';
import 'forms.dart';
import 'inventory_data.dart';
import 'inventory_repository.dart';
import 'inventory_theme.dart';

class RoomPage extends StatefulWidget {
  const RoomPage({
    super.key,
    required this.room,
    required this.repo,
    required this.editing,
    required this.onChanged,
  });
  final Room room;
  final InventoryRepository repo;
  final bool editing;
  final VoidCallback onChanged;

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final transform = TransformationController();
  final viewportKey = GlobalKey();
  final search = TextEditingController();
  Asset? selected;
  bool showList = false;
  Map<Asset, Offset>? draft;

  @override
  void dispose() {
    transform.dispose();
    search.dispose();
    super.dispose();
  }

  void openAsset(Asset asset, bool wide) {
    setState(() => selected = asset);
    if (wide || draft != null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .9,
        child: Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: AssetDetail(
            asset: asset,
            repo: widget.repo,
            roomName: widget.room.name,
            editable: widget.editing,
            onClose: () => Navigator.of(sheetContext).pop(),
            onSaved: refresh,
          ),
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => selected = null);
    });
  }

  void refresh() {
    setState(() {});
    widget.onChanged();
  }

  void moveAsset(Asset asset, Offset translation) {
    final positions = draft;
    if (positions == null) return;
    final next = positions[asset]! + translation;
    setState(() {
      selected = asset;
      positions[asset] =
          Offset(next.dx.clamp(0.0, 1.0), next.dy.clamp(0.0, 1.0));
    });
  }

  Future<void> finishEdit({required bool save}) async {
    if (save) {
      for (final entry in draft!.entries) {
        entry.key.position = entry.value;
      }
    }
    setState(() {
      draft = null;
      selected = null;
    });
    if (!save) return;
    widget.onChanged();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repo.saveLayout(widget.room);
      messenger.showSnackBar(
        const SnackBar(content: Text('Distribución guardada')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void zoom(double factor) {
    final current = transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(1.0, 3.0);
    if (next == 1) {
      transform.value = Matrix4.identity();
    } else {
      final viewport = viewportKey.currentContext?.findRenderObject();
      if (viewport is! RenderBox) return;
      final center = viewport.size.center(Offset.zero);
      final anchor = transform.toScene(center);
      transform.value = Matrix4.identity()
        ..translateByDouble(
            center.dx - anchor.dx * next, center.dy - anchor.dy * next, 0, 1)
        ..scaleByDouble(next, next, 1, 1);
    }
  }

  Future<void> leaveEditing() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Salir de la edición?'),
        content: const Text(
            'Se descartarán las posiciones que aún no hayas guardado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Seguir editando')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Salir sin guardar')),
        ],
      ),
    );
    if (!mounted || discard != true) return;
    finishEdit(save: false);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).maybePop();
  }

  void startEditing() => setState(() {
        draft = {for (final asset in widget.room.assets) asset: asset.position};
        showList = false;
      });

  Future<void> addAsset(bool wide) async {
    final asset =
        await showAddAssetForm(context, repo: widget.repo, room: widget.room);
    if (asset == null || !mounted) return;
    setState(() => widget.room.assets.add(asset));
    widget.onChanged();
    // Persist the new marker's position (no-op for the demo repository).
    try {
      await widget.repo.saveLayout(widget.room);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Equipo creado. ${e.message}')));
      }
    }
    if (mounted) openAsset(asset, wide);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final activeDraft = draft;
    final editingMap = activeDraft != null;
    final assets = widget.room.assets;
    return PopScope(
      canPop: !editingMap,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && editingMap) leaveEditing();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.room.name),
          actions: [
            if (!widget.editing)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Row(children: [
                  Icon(Icons.visibility_outlined, size: 16, color: inkFaint),
                  SizedBox(width: 6),
                  Text('Presentación',
                      style: TextStyle(fontSize: 13.5, color: inkFaint)),
                ]),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(builder: (context, bounds) {
            final wide = bounds.maxWidth >= 760;
            final short = bounds.maxHeight < 470;
            final detail = selected;
            final gutter = wide ? 24.0 : 12.0;

            final map = SheetSurface(
              child: Stack(children: [
                Positioned.fill(
                  child: ClipRect(
                    key: viewportKey,
                    child: _RoomCanvas(
                      assets: assets,
                      draft: activeDraft,
                      selected: detail,
                      controller: transform,
                      onSelect: (asset) => openAsset(asset, wide),
                      onMove: moveAsset,
                      onAdd: widget.editing && !editingMap
                          ? () => addAsset(wide)
                          : null,
                    ),
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: editingMap && detail != null
                              ? _PositionControls(
                                  asset: detail, onMove: moveAsset)
                              : !short && !editingMap && assets.isNotEmpty
                                  ? _Floating(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 9),
                                        child: Wrap(
                                            spacing: 14,
                                            runSpacing: 6,
                                            children: [
                                              for (final status
                                                  in statusesBySeverity)
                                                if (widget.room.count(status) >
                                                    0)
                                                  StatusTag(status,
                                                      count: widget.room
                                                          .count(status)),
                                            ]),
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                        ),
                      ),
                      // While positioning, the arrows own this strip.
                      if (!editingMap) ...[
                        const SizedBox(width: 8),
                        _Floating(
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                                tooltip: 'Alejar plano',
                                onPressed: () => zoom(.8),
                                icon:
                                    const Icon(Icons.remove_rounded, size: 18)),
                            IconButton(
                                tooltip: 'Acercar plano',
                                onPressed: () => zoom(1.25),
                                icon: const Icon(Icons.add_rounded, size: 18)),
                            IconButton(
                                tooltip: 'Restablecer vista',
                                onPressed: () =>
                                    transform.value = Matrix4.identity(),
                                icon: const Icon(Icons.crop_free_rounded,
                                    size: 18)),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
              ]),
            );

            final panel = SheetSurface(
              child: detail != null && wide && !editingMap
                  ? AssetDetail(
                      key: ValueKey(detail.id),
                      asset: detail,
                      repo: widget.repo,
                      roomName: widget.room.name,
                      editable: widget.editing,
                      onClose: () => setState(() => selected = null),
                      onSaved: refresh,
                    )
                  : AssetList(
                      room: widget.room,
                      search: search,
                      selected: detail,
                      onSelect: (asset) => openAsset(asset, wide),
                    ),
            );

            final titleBlock = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  editingMap
                      ? 'Editando distribución'
                      : assets.length == 1
                          ? '1 equipo'
                          : '${assets.length} equipos',
                  style: short ? text.titleMedium : text.titleLarge,
                ),
                if (!short && editingMap)
                  Text('Arrastra un equipo o selecciónalo y usa las flechas.',
                      style: text.bodyMedium?.copyWith(color: inkFaint)),
              ],
            );

            // Primary action is emphasised; the secondary one only appears
            // when it applies (you can't arrange an empty room).
            Widget? primary, secondary;
            if (editingMap) {
              secondary = OutlinedButton(
                  onPressed: () => finishEdit(save: false),
                  child: const Text('Descartar'));
              primary = FilledButton(
                  onPressed: () => finishEdit(save: true),
                  child: const Text('Guardar plano'));
            } else if (widget.editing) {
              if (assets.isNotEmpty) {
                secondary = OutlinedButton.icon(
                  onPressed: startEditing,
                  icon: const Icon(Icons.open_with_rounded, size: 18),
                  label: const Text('Editar distribución'),
                );
              }
              primary = FilledButton.icon(
                onPressed: () => addAsset(wide),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Agregar equipo'),
              );
            }

            final Widget header = primary == null
                ? Align(alignment: Alignment.centerLeft, child: titleBlock)
                : wide
                    ? Row(children: [
                        Expanded(child: titleBlock),
                        const SizedBox(width: 16),
                        if (secondary != null) ...[
                          secondary,
                          const SizedBox(width: 8),
                        ],
                        primary,
                      ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          titleBlock,
                          const SizedBox(height: 12),
                          primary,
                          if (secondary != null) ...[
                            const SizedBox(height: 8),
                            secondary,
                          ],
                        ],
                      );

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      gutter, short ? 8 : 20, gutter, short ? 8 : gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      SizedBox(height: short ? 8 : 16),
                      if (!wide && !editingMap) ...[
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                                value: false,
                                label: Text('Plano'),
                                icon: Icon(Icons.grid_view_rounded, size: 18)),
                            ButtonSegment(
                                value: true,
                                label: Text('Equipos'),
                                icon: Icon(Icons.view_list_rounded, size: 18)),
                          ],
                          selected: {showList},
                          onSelectionChanged: (value) =>
                              setState(() => showList = value.single),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Expanded(
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: map),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                      width: (bounds.maxWidth * .32)
                                          .clamp(300.0, 380.0),
                                      child: panel),
                                ],
                              )
                            : showList && !editingMap
                                ? panel
                                : map,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Small white panel floating over the plan.
class _Floating extends StatelessWidget {
  const _Floating({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

class _RoomCanvas extends StatelessWidget {
  const _RoomCanvas({
    required this.assets,
    required this.draft,
    required this.selected,
    required this.controller,
    required this.onSelect,
    required this.onMove,
    required this.onAdd,
  });

  final List<Asset> assets;
  final Map<Asset, Offset>? draft;
  final Asset? selected;
  final TransformationController controller;
  final ValueChanged<Asset> onSelect;
  final void Function(Asset, Offset) onMove;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final width = bounds.maxWidth;
        final height = bounds.maxHeight;
        final compact = width < 335;
        final markerWidth = compact
            ? 84.0
            : width < 520
                ? 124.0
                : 152.0;
        final markerHeight = compact ? 40.0 : 52.0;
        final left = math.min(32.0, math.max(8.0, width * .05));
        final top = math.min(32.0, math.max(8.0, height * .05));
        // Leave room for the floating legend and zoom controls.
        final bottom = math.min(72.0, math.max(8.0, height * .12));
        final travelX = math.max(1.0, width - markerWidth - 2 * left);
        final travelY = math.max(1.0, height - markerHeight - top - bottom);

        // Markers have fixed footprints on the plan; cap text scaling so
        // labels never overflow (the list view shows full-size text).
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: InteractiveViewer(
            transformationController: controller,
            minScale: 1,
            maxScale: 3,
            boundaryMargin: const EdgeInsets.all(24),
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                        painter: _PlanPaper(editing: draft != null)),
                  ),
                ),
                if (assets.isEmpty)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Esta sala aún no tiene equipos.',
                            style: TextStyle(color: inkFaint)),
                        if (onAdd != null) ...[
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: onAdd,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Agregar el primer equipo'),
                          ),
                        ],
                      ],
                    ),
                  ),
                for (final asset in assets)
                  Positioned(
                    left: left + (draft?[asset] ?? asset.position).dx * travelX,
                    top: top + (draft?[asset] ?? asset.position).dy * travelY,
                    width: markerWidth,
                    height: markerHeight,
                    child: MouseRegion(
                      cursor: draft == null
                          ? SystemMouseCursors.click
                          : SystemMouseCursors.grab,
                      child: GestureDetector(
                        onPanUpdate: draft == null
                            ? null
                            : (event) => onMove(
                                  asset,
                                  Offset(event.delta.dx / travelX,
                                      event.delta.dy / travelY),
                                ),
                        child: Marker(
                          asset: asset,
                          selected: selected == asset,
                          onTap: () => onSelect(asset),
                          compact: compact,
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        );
      });
}

/// An asset on the plan, drawn as a label: device icon (coloured by status),
/// code in mono, status below.
class Marker extends StatelessWidget {
  const Marker({
    super.key,
    required this.asset,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final Asset asset;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final status = asset.status;
    return Semantics(
      button: true,
      selected: selected,
      label: '${asset.code}, ${asset.name}, ${status.label}',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusControl),
          side: BorderSide(
              color: selected ? ink : hairlineStrong,
              width: selected ? 1.5 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
            child: Row(children: [
              DeviceGlyph(asset.icon, status, size: compact ? 17 : 20),
              SizedBox(width: compact ? 7 : 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(asset.code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle(size: compact ? 11 : 12.5)),
                    if (!compact) ...[
                      const SizedBox(height: 2),
                      Text(status.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: status.color)),
                    ],
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PositionControls extends StatelessWidget {
  const _PositionControls({required this.asset, required this.onMove});
  final Asset asset;
  final void Function(Asset, Offset) onMove;

  @override
  Widget build(BuildContext context) => _Floating(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 4),
            child: CodeTag(asset.code, small: true),
          ),
          IconButton(
              tooltip: 'Mover a la izquierda',
              onPressed: () => onMove(asset, const Offset(-.05, 0)),
              icon: const Icon(Icons.keyboard_arrow_left_rounded)),
          IconButton(
              tooltip: 'Mover arriba',
              onPressed: () => onMove(asset, const Offset(0, -.05)),
              icon: const Icon(Icons.keyboard_arrow_up_rounded)),
          IconButton(
              tooltip: 'Mover abajo',
              onPressed: () => onMove(asset, const Offset(0, .05)),
              icon: const Icon(Icons.keyboard_arrow_down_rounded)),
          IconButton(
              tooltip: 'Mover a la derecha',
              onPressed: () => onMove(asset, const Offset(.05, 0)),
              icon: const Icon(Icons.keyboard_arrow_right_rounded)),
        ]),
      );
}

/// Drafting paper: a fine dot grid with a heavier dot every fourth step.
/// In edit mode the grid darkens slightly so the change of mode is felt.
class _PlanPaper extends CustomPainter {
  const _PlanPaper({required this.editing});
  final bool editing;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = planPaper);
    final fine = Paint()..color = editing ? hairlineStrong : hairline;
    final major = Paint()..color = editing ? inkGhost : hairlineStrong;
    const step = 20.0;
    for (var i = 1; i * step < size.width; i++) {
      for (var j = 1; j * step < size.height; j++) {
        final majorDot = i % 4 == 0 && j % 4 == 0;
        canvas.drawCircle(Offset(i * step, j * step), majorDot ? 1.4 : 1,
            majorDot ? major : fine);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PlanPaper oldDelegate) =>
      oldDelegate.editing != editing;
}
