import 'package:flutter/material.dart';

import 'asset_panel.dart';
import 'inventory_data.dart';
import 'inventory_repository.dart';
import 'inventory_theme.dart';

class AllAssetsPage extends StatefulWidget {
  const AllAssetsPage({
    super.key,
    required this.repo,
    required this.editable,
    this.onlyPending = false,
  });
  final InventoryRepository repo;
  final bool editable;

  /// Start with the "Mantenimiento pendiente" filter on.
  final bool onlyPending;

  @override
  State<AllAssetsPage> createState() => _AllAssetsPageState();
}

class _AllAssetsPageState extends State<AllAssetsPage> {
  final search = TextEditingController();
  List<Asset>? assets;
  String? error;
  late bool onlyPending = widget.onlyPending;

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
      if (mounted) {
        setState(() => error = failure is ApiException
            ? failure.message
            : 'Revisa la conexión e inténtalo de nuevo.');
      }
    }
  }

  Future<void> open(Asset asset) async {
    await showAssetSheet(
      context,
      asset: asset,
      repo: widget.repo,
      roomName: asset.roomName ?? 'Sin sala',
      editable: widget.editable,
      onSaved: () {
        if (mounted) setState(() {});
      },
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        assets?.where((asset) => asset.maintenancePending).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Todos los equipos'),
        actions: [
          IconButton(
              tooltip: 'Actualizar inventario',
              onPressed: load,
              icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(builder: (context, bounds) {
          final gutter = bounds.maxWidth >= 840 ? 40.0 : 16.0;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Padding(
                padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ValueListenableBuilder(
                      valueListenable: search,
                      builder: (context, value, _) => TextField(
                        controller: search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Buscar equipo, persona, código o sala',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: value.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    search.clear();
                                    setState(() {});
                                  },
                                  tooltip: 'Limpiar búsqueda',
                                  icon: const Icon(Icons.close_rounded,
                                      size: 18),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilterChip(
                        avatar: Icon(Icons.build_outlined,
                            size: 16,
                            color: onlyPending ? maintenanceInk : inkFaint),
                        showCheckmark: false,
                        label: Text(pendingCount > 0
                            ? 'Mantenimiento pendiente · $pendingCount'
                            : 'Mantenimiento pendiente'),
                        selected: onlyPending,
                        onSelected: (value) =>
                            setState(() => onlyPending = value),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(child: _body()),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _body() {
    final text = Theme.of(context).textTheme;
    if (error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_outlined, color: inkSoft),
          const SizedBox(height: 12),
          Text('No se pudo cargar el inventario', style: text.titleMedium),
          const SizedBox(height: 6),
          Text(error!,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: inkFaint)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Reintentar'),
          ),
        ]),
      );
    }
    final all = assets;
    if (all == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final query = search.text.trim().toLowerCase();
    final filtered = all.where((asset) {
      final content =
          '${asset.name} ${asset.responsible} ${asset.code} ${asset.type} ${asset.roomName ?? ''}';
      return (!onlyPending || asset.maintenancePending) &&
          content.toLowerCase().contains(query);
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Text(
          filtered.length == all.length
              ? (all.length == 1 ? '1 equipo' : '${all.length} equipos')
              : '${filtered.length} de ${all.length} equipos',
          style: text.bodySmall?.copyWith(color: inkFaint),
        ),
      ),
      Expanded(
        child: SheetSurface(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      all.isEmpty
                          ? 'Aún no hay equipos registrados.'
                          : onlyPending && query.isEmpty
                              ? 'Ningún equipo tiene mantenimiento pendiente.'
                              : 'Ningún equipo coincide con la búsqueda.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: inkFaint),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final asset = filtered[index];
                    return AssetRow(
                      key: ValueKey(asset.id),
                      asset: asset,
                      selected: false,
                      roomName: asset.roomName ?? 'Sin sala',
                      onTap: () => open(asset),
                    );
                  },
                ),
        ),
      ),
    ]);
  }
}
