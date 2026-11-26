import 'package:flutter/material.dart';

import 'forms.dart';
import 'inventory_data.dart';
import 'inventory_repository.dart';
import 'inventory_theme.dart';

class AssetList extends StatelessWidget {
  const AssetList({
    super.key,
    required this.room,
    required this.search,
    required this.selected,
    required this.onSelect,
  });
  final Room room;
  final TextEditingController search;
  final Asset? selected;
  final ValueChanged<Asset> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder(
      valueListenable: search,
      builder: (context, value, _) {
        final query = value.text.toLowerCase().trim();
        final filtered = room.assets
            .where(
              (asset) =>
                  '${asset.code} ${asset.name} ${asset.type} ${asset.responsible} ${asset.status.label}'
                      .toLowerCase()
                      .contains(query),
            )
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Semantics(
                          header: true,
                          child: Text('Equipos en la sala',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium)),
                    ),
                    const SizedBox(width: 8),
                    Text('${room.assets.length}',
                        style: monoStyle(color: inkFaint)),
                  ]),
            ),
            if (room.assets.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: search,
                  decoration: InputDecoration(
                    hintText: 'Buscar equipo, persona o estado',
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: search.clear,
                            tooltip: 'Limpiar búsqueda',
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                  ),
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        room.assets.isEmpty
                            ? 'Esta sala aún no tiene equipos.'
                            : 'Ningún equipo coincide con «${value.text.trim()}».',
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(color: inkFaint),
                      ),
                    ))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final asset = filtered[index];
                        return AssetRow(
                          key: ValueKey(asset.code),
                          asset: asset,
                          selected: selected == asset,
                          onTap: () => onSelect(asset),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class AssetRow extends StatelessWidget {
  const AssetRow(
      {super.key,
      required this.asset,
      required this.selected,
      required this.onTap,
      this.roomName,
      this.showMaintenance = true});
  final Asset asset;
  final bool selected;
  final VoidCallback onTap;

  /// Shown after the responsible person in lists that span several rooms.
  final String? roomName;

  /// Off where the whole list is already "mantenimiento pendiente".
  final bool showMaintenance;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        child: Material(
          color: selected ? selectedFill : Colors.transparent,
          borderRadius: BorderRadius.circular(radiusControl),
          child: InkWell(
            borderRadius: BorderRadius.circular(radiusControl),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(children: [
                DeviceGlyph(asset.icon, asset.status, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(asset.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 3),
                      Text(
                          roomName == null
                              ? asset.assignedLabel
                              : '${asset.assignedLabel}  ·  $roomName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(fontSize: 12.5, color: inkFaint)),
                      const SizedBox(height: 2),
                      Row(children: [
                        Text(asset.code,
                            style: monoStyle(size: 12, color: inkFaint)),
                        const Text('  ·  ',
                            style: TextStyle(fontSize: 12, color: inkGhost)),
                        Flexible(
                          child: Text(asset.status.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: asset.status.color)),
                        ),
                      ]),
                      if (showMaintenance && asset.maintenancePending) ...[
                        const SizedBox(height: 4),
                        const MaintenanceTag(),
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

class AssetDetail extends StatefulWidget {
  const AssetDetail({
    super.key,
    required this.asset,
    required this.repo,
    required this.roomName,
    required this.editable,
    required this.onSaved,
    required this.onClose,
  });
  final Asset asset;
  final InventoryRepository repo;
  final String roomName;
  final bool editable;
  final VoidCallback onSaved;
  final VoidCallback onClose;

  @override
  State<AssetDetail> createState() => _AssetDetailState();
}

class _AssetDetailState extends State<AssetDetail> {
  late AssetStatus pending = widget.asset.status;
  final note = TextEditingController();
  late List<StatusChange> history = widget.asset.history;
  bool saving = false;
  bool savingMaintenance = false;

  @override
  void initState() {
    super.initState();
    if (widget.editable) _loadHistory();
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final loaded = await widget.repo.loadHistory(widget.asset);
      if (mounted) setState(() => history = loaded);
    } catch (_) {
      // History is non-essential; leave what we have.
    }
  }

  Future<void> save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => saving = true);
    try {
      await widget.repo.updateStatus(widget.asset, pending, note.text);
      note.clear();
      widget.onSaved();
      await _loadHistory();
      messenger.showSnackBar(
        const SnackBar(content: Text('Estado guardado')),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> setMaintenance(bool value) async {
    setState(() => savingMaintenance = true);
    try {
      await widget.repo.updateMaintenance(widget.asset, value);
      if (!mounted) return;
      setState(() {});
      widget.onSaved();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is ApiException
                ? error.message
                : 'No se pudo guardar el mantenimiento.')));
      }
    } finally {
      if (mounted) setState(() => savingMaintenance = false);
    }
  }

  Future<void> edit() async {
    final saved = await showEditAssetForm(context,
        repo: widget.repo, asset: widget.asset);
    if (saved == true && mounted) {
      setState(() {});
      widget.onSaved();
    }
  }

  // The icon applies on tap; it reverts if the server rejects the change.
  Future<void> changeIcon(DeviceIcon icon) async {
    final previous = widget.asset.icon;
    setState(() => widget.asset.icon = icon);
    try {
      await widget.repo.updateIcon(widget.asset, icon);
      widget.onSaved();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => widget.asset.icon = previous);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final asset = widget.asset;
    final localizations = MaterialLocalizations.of(context);
    final unchanged = pending == asset.status;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Identity stays pinned while the form scrolls.
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: well,
                borderRadius: BorderRadius.circular(radiusControl + 2),
              ),
              child: Center(
                  child: DeviceGlyph(asset.icon, asset.status, size: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Semantics(
                  header: true,
                  child: Text(asset.name, style: text.titleLarge)),
            ),
          ),
          if (widget.editable)
            IconButton(
                onPressed: edit,
                tooltip: 'Editar equipo',
                icon: const Icon(Icons.edit_outlined)),
          IconButton(
              onPressed: widget.onClose,
              tooltip: 'Cerrar ficha',
              icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CodeTag(asset.code),
                  Text('${asset.type} · ${widget.roomName}',
                      style: text.bodySmall),
                ]),
            if (asset.responsible.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.person_outline_rounded,
                    size: 16, color: inkFaint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Responsable: ${asset.responsible}',
                      style: text.bodySmall?.copyWith(color: inkSoft)),
                ),
              ]),
            ],
            const SizedBox(height: 20),
            _CurrentStatus(asset.status),
            const SizedBox(height: 12),
            if (widget.editable)
              // Same framed-row language as the current-status block above.
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: hairline),
                  borderRadius: BorderRadius.circular(radiusControl + 2),
                ),
                child: SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.fromLTRB(14, 2, 8, 2),
                  secondary: Icon(Icons.build_outlined,
                      size: 18,
                      color: asset.maintenancePending
                          ? maintenanceInk
                          : inkFaint),
                  title: Text('Mantenimiento pendiente',
                      style: text.titleSmall),
                  subtitle: Text('Márcalo cuando el equipo necesite revisión.',
                      style: text.bodySmall),
                  value: asset.maintenancePending,
                  onChanged:
                      saving || savingMaintenance ? null : setMaintenance,
                ),
              )
            else if (asset.maintenancePending)
              const MaintenanceTag(),
            if (widget.editable) ...[
              const SizedBox(height: 28),
              Text('Ícono',
                  style: text.titleSmall
                      ?.copyWith(color: inkSoft, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              IconPicker(value: asset.icon, onChanged: changeIcon),
              const SizedBox(height: 28),
              Text('Cambiar estado',
                  style: text.titleSmall
                      ?.copyWith(color: inkSoft, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              _StatusPicker(
                current: asset.status,
                value: pending,
                onChanged: (value) => setState(() => pending = value),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: note,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                    hintText: 'Observación (opcional): qué viste, qué hiciste'),
              ),
              const SizedBox(height: 28),
              Text('Historial',
                  style: text.titleSmall
                      ?.copyWith(color: inkSoft, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              if (history.isEmpty)
                Text('Sin cambios todavía.',
                    style: text.bodyMedium?.copyWith(color: inkFaint)),
              for (final change in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: StatusLed(change.current),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Semantics(
                                  label:
                                      'De ${change.previous.label} a ${change.current.label}',
                                  excludeSemantics: true,
                                  child: Text.rich(TextSpan(children: [
                                    TextSpan(
                                        text: change.previous.label,
                                        style:
                                            const TextStyle(color: inkFaint)),
                                    const TextSpan(
                                        text: '  →  ',
                                        style: TextStyle(color: inkGhost)),
                                    TextSpan(
                                        text: change.current.label,
                                        style: TextStyle(
                                            color: change.current.color,
                                            fontWeight: FontWeight.w600)),
                                  ])),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${localizations.formatShortDate(change.at)} · ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(change.at), alwaysUse24HourFormat: true)}',
                                  style: monoStyle(
                                      size: 11.5,
                                      weight: FontWeight.w400,
                                      color: inkFaint),
                                ),
                                if (change.note.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(change.note, style: text.bodyMedium),
                                ],
                              ]),
                        ),
                      ]),
                ),
            ],
          ],
        ),
      ),
      if (widget.editable) ...[
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  unchanged
                      ? 'Elige un estado distinto al actual.'
                      : 'Nuevo estado: ${pending.label}',
                  style: text.bodySmall?.copyWith(
                      color: unchanged ? inkFaint : ink,
                      fontWeight: unchanged ? null : FontWeight.w500),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed:
                      unchanged || saving || savingMaintenance ? null : save,
                  child: const Text('Guardar estado'),
                ),
              ]),
        ),
      ],
    ]);
  }
}

class _CurrentStatus extends StatelessWidget {
  const _CurrentStatus(this.status);
  final AssetStatus status;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: well,
          borderRadius: BorderRadius.circular(radiusControl + 2),
        ),
        child: Row(children: [
          StatusLed(status, size: 10),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Estado actual',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 2),
                Text(status.label,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: status.color)),
              ],
            ),
          ),
        ]),
      );
}

/// Every option visible as a row, one tap to choose.
class _StatusPicker extends StatelessWidget {
  const _StatusPicker(
      {required this.current, required this.value, required this.onChanged});
  final AssetStatus current;
  final AssetStatus value;
  final ValueChanged<AssetStatus> onChanged;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: hairline),
          borderRadius: BorderRadius.circular(radiusControl + 2),
        ),
        child: Column(children: [
          for (final (i, status) in statusesBySeverity.indexed) ...[
            if (i > 0) const Divider(indent: 12, endIndent: 12),
            Semantics(
              key: ValueKey('status-${status.name}'),
              button: true,
              selected: value == status,
              inMutuallyExclusiveGroup: true,
              label: status.label,
              excludeSemantics: true,
              child: InkWell(
                onTap: () => onChanged(status),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(i == 0 ? radiusControl + 1 : 0),
                  bottom: Radius.circular(i == statusesBySeverity.length - 1
                      ? radiusControl + 1
                      : 0),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      StatusLed(status),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(status.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: value == status
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: value == status ? ink : inkSoft,
                            )),
                      ),
                      if (status == current)
                        const Flexible(
                          child: Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Text('Actual',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(fontSize: 12, color: inkFaint)),
                          ),
                        ),
                      SizedBox(
                        width: 20,
                        child: value == status
                            ? const Icon(Icons.check_rounded,
                                size: 18, color: ink)
                            : null,
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );
}

/// Opens an asset's detail as a bottom sheet (used by lists that span rooms).
Future<void> showAssetSheet(
  BuildContext context, {
  required Asset asset,
  required InventoryRepository repo,
  required String roomName,
  required bool editable,
  required VoidCallback onSaved,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: sheet,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .92,
        child: Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: AssetDetail(
            asset: asset,
            repo: repo,
            roomName: roomName,
            editable: editable,
            onClose: () => Navigator.pop(sheetContext),
            onSaved: onSaved,
          ),
        ),
      ),
    );
