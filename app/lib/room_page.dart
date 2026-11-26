import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'asset_panel.dart';
import 'csv_import.dart';
import 'forms.dart';
import 'inventory_data.dart';
import 'inventory_repository.dart';
import 'inventory_theme.dart';

/// The plan is this many times the viewport on each side, so assets and
/// zones have room to spread out; zoom in to work on a part of it.
const planScale = 2.0;
const fitScale = 1 / planScale;
const maxPlanScale = 5.0;
Matrix4 fitMatrix() => Matrix4.diagonal3Values(fitScale, fitScale, 1);

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
  final transform = TransformationController(fitMatrix());
  final viewportKey = GlobalKey();
  final search = TextEditingController();
  Asset? selected;
  bool showList = false;
  Map<Asset, Offset>? draft;

  /// While editing the plan: a working copy of the room's zones, and the one
  /// currently selected (so its controls show). Null when not editing.
  List<RoomItem>? itemDraft;
  RoomItem? selectedItem;

  @override
  void dispose() {
    transform.dispose();
    search.dispose();
    super.dispose();
  }

  void openAsset(Asset asset, bool wide) {
    setState(() {
      selected = asset;
      selectedItem = null;
    });
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
      selectedItem = null;
      positions[asset] =
          Offset(next.dx.clamp(0.0, 1.0), next.dy.clamp(0.0, 1.0));
    });
  }

  // --- Zones (tables, rows, racks) -----------------------------------------

  void addItem(RoomItemKind kind) {
    final items = itemDraft;
    if (items == null) return;
    final item =
        RoomItem(kind, const Rect.fromLTWH(0.35, 0.4, 0.3, 0.2), label: '');
    setState(() {
      items.add(item);
      selectedItem = item;
      selected = null;
    });
  }

  void selectItem(RoomItem? item) => setState(() {
        selectedItem = item;
        if (item != null) selected = null;
      });

  void moveItem(RoomItem item, Offset deltaNorm) {
    setState(() {
      selectedItem = item;
      final r = item.rect.shift(deltaNorm);
      item.rect = Rect.fromLTWH(
        r.left.clamp(0.0, 1 - item.rect.width),
        r.top.clamp(0.0, 1 - item.rect.height),
        item.rect.width,
        item.rect.height,
      );
    });
  }

  void resizeItem(RoomItem item, Offset deltaNorm) {
    setState(() {
      selectedItem = item;
      item.rect = Rect.fromLTWH(
        item.rect.left,
        item.rect.top,
        (item.rect.width + deltaNorm.dx).clamp(0.08, 1 - item.rect.left),
        (item.rect.height + deltaNorm.dy).clamp(0.06, 1 - item.rect.top),
      );
    });
  }

  void deleteItem(RoomItem item) => setState(() {
        itemDraft?.remove(item);
        if (selectedItem == item) selectedItem = null;
      });

  Future<void> editItem(RoomItem item) async {
    final controller = TextEditingController(text: item.label);
    var kind = item.kind;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Zona'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 8, children: [
              for (final k in RoomItemKind.values)
                ChoiceChip(
                  label: Text(k.label),
                  selected: kind == k,
                  onSelected: (_) => setLocal(() => kind = k),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'Etiqueta (opcional)', hintText: 'Ej. Rack A'),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Aplicar')),
          ],
        ),
      ),
    );
    if (saved == true) {
      setState(() {
        item.label = controller.text.trim();
        item.kind = kind;
      });
    }
  }

  Future<void> finishEdit({required bool save}) async {
    if (save) {
      for (final entry in draft!.entries) {
        entry.key.position = entry.value;
      }
      widget.room.items
        ..clear()
        ..addAll(itemDraft!);
    }
    setState(() {
      draft = null;
      itemDraft = null;
      selectedItem = null;
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
    final next = (current * factor).clamp(fitScale, maxPlanScale);
    if (next == fitScale) {
      transform.value = fitMatrix();
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
        itemDraft = [
          for (final item in widget.room.items)
            RoomItem(item.kind, item.rect, label: item.label)
        ];
        selectedItem = null;
        selected = null;
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

  void downloadTemplate() =>
      downloadCsv('plantilla-inventario.csv', assetsCsvTemplate());

  Future<void> importCsv() async {
    final messenger = ScaffoldMessenger.of(context);
    final content = await pickCsvFile();
    if (content == null || !mounted) return;
    final result = parseAssetsCsv(content);
    final problems = [
      for (final e in result.errors) 'Fila ${e.line}: ${e.message}'
    ];
    final existing = {for (final a in widget.room.assets) a.code.toLowerCase()};
    var added = 0;
    for (final row in result.assets) {
      if (existing.contains(row.code.toLowerCase())) {
        problems.add('${row.code}: ya existe, se omitió');
        continue;
      }
      try {
        final asset = await widget.repo.createAsset(
          widget.room,
          code: row.code,
          name: row.name,
          type: row.type,
          icon: row.icon,
          responsible: row.responsible,
          position: cascadePosition(widget.room.assets.length),
        );
        widget.room.assets.add(asset);
        existing.add(row.code.toLowerCase());
        if (row.status != AssetStatus.unknown) {
          try {
            await widget.repo.updateStatus(asset, row.status, 'Importado');
          } on ApiException {
            // Keep the asset even if the initial status couldn't be set.
          }
        }
        added++;
      } on ApiException catch (e) {
        problems.add('${row.code}: ${e.message}');
      }
    }
    if (added > 0) {
      try {
        await widget.repo.saveLayout(widget.room);
      } on ApiException {
        // Positions persist on the next layout save.
      }
    }
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
    messenger.showSnackBar(SnackBar(
        content: Text(
            added == 1 ? '1 equipo importado' : '$added equipos importados')));
    if (problems.isNotEmpty) await _showImportProblems(added, problems);
  }

  Future<void> _showImportProblems(int added, List<String> problems) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Resultado de la importación'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(added == 1
                    ? '1 equipo agregado.'
                    : '$added equipos agregados.'),
                const SizedBox(height: 12),
                Text('No se pudieron agregar ${problems.length}:',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final problem in problems)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text('• $problem',
                                style: const TextStyle(fontSize: 13)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Entendido')),
          ],
        ),
      );

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
            if (widget.editing && !editingMap)
              PopupMenuButton<String>(
                tooltip: 'Más acciones',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  if (value == 'import') importCsv();
                  if (value == 'template') downloadTemplate();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'import',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.upload_file_outlined),
                      title: Text('Importar CSV'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'template',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.download_outlined),
                      title: Text('Descargar plantilla'),
                    ),
                  ),
                ],
              ),
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
                      items: itemDraft ?? widget.room.items,
                      editingItems: editingMap,
                      selectedItem: selectedItem,
                      onSelectItem: selectItem,
                      onMoveItem: moveItem,
                      onResizeItem: resizeItem,
                      onSelect: (asset) => openAsset(asset, wide),
                      onMove: moveAsset,
                      onAdd: widget.editing && !editingMap
                          ? () => addAsset(wide)
                          : null,
                    ),
                  ),
                ),
                if (editingMap)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _AddZoneBar(onAdd: addItem),
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
                          child: editingMap && selectedItem != null
                              ? _ItemControls(
                                  item: selectedItem!,
                                  onEdit: () => editItem(selectedItem!),
                                  onDelete: () => deleteItem(selectedItem!))
                              : editingMap && detail != null
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
                                                    if (widget.room
                                                            .count(status) >
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
                                onPressed: () => transform.value = fitMatrix(),
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

/// A drawn zone (table, row or rack) on the plan. Visual only unless editing,
/// where it can be selected, dragged and resized.
class _ZoneBox extends StatelessWidget {
  const _ZoneBox({
    required this.item,
    required this.editing,
    required this.selected,
    required this.onTap,
    required this.onMove,
    required this.onResize,
  });

  final RoomItem item;
  final bool editing;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMove;
  final ValueChanged<Offset> onResize;

  @override
  Widget build(BuildContext context) {
    final label = item.label.isEmpty ? item.kind.label : item.label;
    final visual = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x14172721),
        border: Border.all(
            color: selected ? ink : hairlineStrong, width: selected ? 1.5 : 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(item.kind.icon, size: 14, color: inkFaint),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: inkSoft)),
            ),
          ]),
        ),
      ),
    );

    if (!editing) return IgnorePointer(child: visual);

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: GestureDetector(
        onTap: onTap,
        onPanUpdate: (event) => onMove(event.delta),
        child: Stack(children: [
          Positioned.fill(child: visual),
          if (selected)
            Positioned(
              right: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeDownRight,
                child: GestureDetector(
                  onPanUpdate: (event) => onResize(event.delta),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: ink,
                      borderRadius:
                          BorderRadius.only(topLeft: Radius.circular(6)),
                    ),
                    child: const Icon(Icons.open_in_full_rounded,
                        size: 12, color: sheet),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Edit-mode control to drop a new zone onto the plan.
class _AddZoneBar extends StatelessWidget {
  const _AddZoneBar({required this.onAdd});
  final ValueChanged<RoomItemKind> onAdd;

  @override
  Widget build(BuildContext context) => _Floating(
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Agregar zona',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: inkSoft)),
            for (final kind in RoomItemKind.values)
              IconButton(
                tooltip: kind.label,
                onPressed: () => onAdd(kind),
                icon: Icon(kind.icon, size: 18),
              ),
          ]),
        ),
      );
}

/// Bottom-strip controls for the selected zone.
class _ItemControls extends StatelessWidget {
  const _ItemControls(
      {required this.item, required this.onEdit, required this.onDelete});
  final RoomItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => _Floating(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(item.kind.icon, size: 16, color: inkSoft),
              const SizedBox(width: 6),
              Text(item.label.isEmpty ? item.kind.label : item.label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500, color: ink)),
            ]),
          ),
          IconButton(
              tooltip: 'Editar zona',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18)),
          IconButton(
              tooltip: 'Eliminar zona',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 18)),
        ]),
      );
}

class _RoomCanvas extends StatelessWidget {
  const _RoomCanvas({
    required this.assets,
    required this.draft,
    required this.selected,
    required this.controller,
    required this.items,
    required this.editingItems,
    required this.selectedItem,
    required this.onSelectItem,
    required this.onMoveItem,
    required this.onResizeItem,
    required this.onSelect,
    required this.onMove,
    required this.onAdd,
  });

  final List<Asset> assets;
  final Map<Asset, Offset>? draft;
  final Asset? selected;
  final TransformationController controller;
  final List<RoomItem> items;
  final bool editingItems;
  final RoomItem? selectedItem;
  final ValueChanged<RoomItem?> onSelectItem;
  final void Function(RoomItem, Offset) onMoveItem;
  final void Function(RoomItem, Offset) onResizeItem;
  final ValueChanged<Asset> onSelect;
  final void Function(Asset, Offset) onMove;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        // The plan is larger than the viewport so there is room to spread
        // out; the default view (fitScale) shows all of it.
        final viewWidth = bounds.maxWidth;
        final width = viewWidth * planScale;
        final height = bounds.maxHeight * planScale;
        final compact = viewWidth < 335;
        final markerWidth = compact
            ? 220.0
            : viewWidth < 520
                ? 280.0
                : 320.0;
        const markerHeight = 104.0;
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
            constrained: false,
            minScale: fitScale,
            maxScale: maxPlanScale,
            boundaryMargin: const EdgeInsets.all(200),
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
                // Zones sit behind the markers.
                for (final item in items)
                  Positioned(
                    left: item.rect.left * width,
                    top: item.rect.top * height,
                    width: item.rect.width * width,
                    height: item.rect.height * height,
                    child: _ZoneBox(
                      item: item,
                      editing: editingItems,
                      selected: selectedItem == item,
                      onTap: () => onSelectItem(item),
                      onMove: (delta) => onMoveItem(
                          item, Offset(delta.dx / width, delta.dy / height)),
                      onResize: (delta) => onResizeItem(
                          item, Offset(delta.dx / width, delta.dy / height)),
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
      label:
          '${asset.name}, ${asset.assignedLabel}, ${asset.code}, ${status.label}${asset.maintenancePending ? ', Mantenimiento pendiente' : ''}',
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
              DeviceGlyph(asset.icon, status, size: compact ? 30 : 36),
              SizedBox(width: compact ? 7 : 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(asset.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: compact ? 22 : 24,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(asset.assignedLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, color: inkFaint)),
                  ],
                ),
              ),
              if (asset.maintenancePending)
                const Tooltip(
                    message: 'Mantenimiento pendiente',
                    child: Icon(Icons.build_outlined,
                        size: 26, color: Color(0xFF8F5607))),
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
