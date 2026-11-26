import 'package:flutter/material.dart';

import 'asset_panel.dart';
import 'inventory_data.dart';
import 'inventory_repository.dart';
import 'inventory_theme.dart';

class AllAssetsPage extends StatefulWidget {
  const AllAssetsPage({super.key, required this.repo, required this.editable});
  final InventoryRepository repo;
  final bool editable;

  @override
  State<AllAssetsPage> createState() => _AllAssetsPageState();
}

class _AllAssetsPageState extends State<AllAssetsPage> {
  final search = TextEditingController();
  List<Asset>? assets;
  String? error;
  bool onlyPending = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      assets = null;
      error = null;
    });
    try {
      final result = await widget.repo.loadAssets();
      if (mounted) setState(() => assets = result);
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    }
  }

  Future<void> open(Asset asset) async {
    await showModalBottomSheet<void>(
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
            repo: widget.repo,
            roomName: asset.roomName ?? 'Sin sala',
            editable: widget.editable,
            onClose: () => Navigator.pop(sheetContext),
            onSaved: () {
              if (mounted) setState(() {});
            },
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Todos los equipos'),
          actions: [
            IconButton(
                tooltip: 'Actualizar inventario',
                onPressed: load,
                icon: const Icon(Icons.refresh)),
          ],
        ),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Buscar equipos',
                      hintText: 'Nombre, persona, código o sala',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        label: const Text('Mantenimiento pendiente'),
                        selected: onlyPending,
                        onSelected: (value) =>
                            setState(() => onlyPending = value),
                      )),
                  const SizedBox(height: 8),
                  Expanded(child: body()),
                ]),
          ),
        ))),
      );

  Widget body() {
    if (error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error!, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        FilledButton(onPressed: load, child: const Text('Reintentar')),
      ]));
    }
    if (assets == null) return const Center(child: CircularProgressIndicator());
    final query = search.text.trim().toLowerCase();
    final filtered = assets!.where((asset) {
      final content =
          '${asset.name} ${asset.responsible} ${asset.code} ${asset.type} ${asset.roomName ?? ''}';
      return (!onlyPending || asset.maintenancePending) &&
          content.toLowerCase().contains(query);
    }).toList();
    if (filtered.isEmpty) {
      return Center(
          child: Text(assets!.isEmpty
              ? 'Aún no hay equipos registrados.'
              : 'Ningún equipo coincide con los filtros.'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text('${filtered.length} de ${assets!.length} equipos',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      Expanded(
          child: SheetSurface(
              child: ListView.separated(
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final asset = filtered[index];
          return ListTile(
            onTap: () => open(asset),
            leading: DeviceGlyph(asset.icon, asset.status),
            title: Text(asset.name),
            subtitle:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(asset.assignedLabel),
              Text('${asset.code} · ${asset.roomName ?? 'Sin sala'}',
                  style: Theme.of(context).textTheme.bodySmall),
              StatusTag(asset.status),
              if (asset.maintenancePending) const MaintenanceTag(),
            ]),
            trailing: const Icon(Icons.chevron_right),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          );
        },
      ))),
    ]);
  }
}
