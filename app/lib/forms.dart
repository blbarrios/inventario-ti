import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'inventory_data.dart';
import 'inventory_repository.dart';
import 'inventory_theme.dart';

/// Ask for a new room's name. Returns the created [Room], or null if cancelled.
Future<Room?> showAddRoomForm(BuildContext context,
        {required InventoryRepository repo, required List<Room> existing}) =>
    _showFormModal<Room>(
      context,
      builder: (_) => _AddRoomForm(repo: repo, existing: existing),
    );

/// Ask for a new asset's details. Returns the created [Asset], or null.
Future<Asset?> showAddAssetForm(BuildContext context,
        {required InventoryRepository repo, required Room room}) =>
    _showFormModal<Asset>(
      context,
      builder: (_) => _AddAssetForm(repo: repo, room: room),
    );

/// A dialog on wide screens, a bottom sheet on narrow ones. The content widget
/// renders its own header and footer so both presentations match.
Future<T?> _showFormModal<T>(BuildContext context,
    {required WidgetBuilder builder}) {
  final wide = MediaQuery.sizeOf(context).width >= 620;
  if (wide) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: builder(ctx),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: builder(ctx),
    ),
  );
}

/// Shared skeleton: pinned title + close, scrolling body, pinned primary action.
class _FormShell extends StatelessWidget {
  const _FormShell({
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.actionLabel,
    required this.onSubmit,
    this.busy = false,
  });

  final String title;
  final String subtitle;
  final List<Widget> fields;
  final String actionLabel;
  final VoidCallback onSubmit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleLarge),
                      const SizedBox(height: 2),
                      Text(subtitle, style: text.bodySmall),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Cancelar',
                icon: const Icon(Icons.close_rounded),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: fields,
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: FilledButton(
              onPressed: busy ? null : onSubmit,
              child: busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: sheet),
                    )
                  : Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled field: a small caption above an input.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.top = 16});
  final String label;
  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: inkSoft, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );
}

class _AddRoomForm extends StatefulWidget {
  const _AddRoomForm({required this.repo, required this.existing});
  final InventoryRepository repo;
  final List<Room> existing;

  @override
  State<_AddRoomForm> createState() => _AddRoomFormState();
}

class _AddRoomFormState extends State<_AddRoomForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final room = await widget.repo.createRoom(_name.text.trim());
      navigator.pop(room);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUnfocus,
        child: _FormShell(
          title: 'Agregar sala',
          subtitle: 'Un espacio donde ubicar equipos.',
          actionLabel: 'Agregar sala',
          busy: _busy,
          onSubmit: _submit,
          fields: [
            _Field(
              label: 'Nombre de la sala',
              top: 4,
              child: TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration:
                    const InputDecoration(hintText: 'Ej. Sala de servidores'),
                validator: (value) {
                  final name = (value ?? '').trim();
                  if (name.isEmpty) return 'Escribe un nombre.';
                  final taken = widget.existing.any(
                      (room) => room.name.toLowerCase() == name.toLowerCase());
                  if (taken) return 'Ya existe una sala con ese nombre.';
                  return null;
                },
              ),
            ),
          ],
        ),
      );
}

const _commonTypes = [
  'Switch',
  'Router',
  'Punto de acceso',
  'Servidor',
  'Computador',
  'Impresora',
  'UPS',
  'Patch panel',
];

class _AddAssetForm extends StatefulWidget {
  const _AddAssetForm({required this.repo, required this.room});
  final InventoryRepository repo;
  final Room room;

  @override
  State<_AddAssetForm> createState() => _AddAssetFormState();
}

class _AddAssetFormState extends State<_AddAssetForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _type = TextEditingController();
  final _responsible = TextEditingController();

  // The icon follows the type until the user picks one by hand.
  DeviceIcon _icon = DeviceIcon.generic;
  bool _iconChosen = false;
  bool _busy = false;

  void _syncIconToType(String type) {
    if (!_iconChosen) _icon = deviceIconForType(type);
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _type.dispose();
    _responsible.dispose();
    super.dispose();
  }

  /// Spread new markers over the plan instead of stacking them at one spot.
  Offset _nextPosition() {
    final n = widget.room.assets.length;
    final col = n % 4;
    final row = (n ~/ 4) % 4;
    return Offset((0.16 + col * 0.22).clamp(0.0, 1.0),
        (0.18 + row * 0.2).clamp(0.0, 1.0));
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final asset = await widget.repo.createAsset(
        widget.room,
        code: _code.text.trim(),
        name: _name.text.trim(),
        type: _type.text.trim(),
        icon: _icon,
        position: _nextPosition(),
        responsible: _responsible.text.trim(),
      );
      navigator.pop(asset);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUnfocus,
        child: _FormShell(
          title: 'Agregar equipo',
          subtitle: 'En ${widget.room.name}.',
          actionLabel: 'Agregar equipo',
          busy: _busy,
          onSubmit: _submit,
          fields: [
            _Field(
              label: 'Nombre del equipo',
              top: 4,
              child: TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    hintText: 'Ej. Switch principal Cisco'),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Escribe un nombre.' : null,
              ),
            ),
            _Field(
              label: 'Código',
              child: TextFormField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                style: monoStyle(size: 14, color: ink),
                decoration: const InputDecoration(hintText: 'Ej. SW-R1-03'),
                validator: (value) {
                  final code = (value ?? '').trim();
                  if (code.isEmpty) return 'Escribe un código.';
                  final taken = widget.room.assets
                      .any((a) => a.code.toLowerCase() == code.toLowerCase());
                  if (taken) {
                    return 'Ya hay un equipo con ese código en esta sala.';
                  }
                  return null;
                },
              ),
            ),
            _Field(
              label: 'Tipo',
              child: TextFormField(
                controller: _type,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onChanged: (value) => setState(() => _syncIconToType(value)),
                onFieldSubmitted: (_) => _submit(),
                decoration:
                    const InputDecoration(hintText: 'Ej. Switch, Router…'),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Indica el tipo.' : null,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in _commonTypes)
                  _SuggestionChip(
                    label: type,
                    onTap: () => setState(() {
                      _type.text = type;
                      _syncIconToType(type);
                    }),
                  ),
              ],
            ),
            _Field(
              label: 'Responsable (opcional)',
              child: TextFormField(
                controller: _responsible,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(hintText: 'Ej. Soporte TI'),
              ),
            ),
            _Field(
              label: 'Ícono',
              child: IconPicker(
                value: _icon,
                onChanged: (icon) => setState(() {
                  _icon = icon;
                  _iconChosen = true;
                }),
              ),
            ),
          ],
        ),
      );
}

/// Edit an existing asset's name, type and responsible. Returns true if saved.
Future<bool?> showEditAssetForm(BuildContext context,
        {required InventoryRepository repo, required Asset asset}) =>
    _showFormModal<bool>(
      context,
      builder: (_) => _EditAssetForm(repo: repo, asset: asset),
    );

class _EditAssetForm extends StatefulWidget {
  const _EditAssetForm({required this.repo, required this.asset});
  final InventoryRepository repo;
  final Asset asset;

  @override
  State<_EditAssetForm> createState() => _EditAssetFormState();
}

class _EditAssetFormState extends State<_EditAssetForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.asset.name);
  late final _type = TextEditingController(text: widget.asset.type);
  late final _responsible =
      TextEditingController(text: widget.asset.responsible);
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _type.dispose();
    _responsible.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.repo.updateAsset(
        widget.asset,
        name: _name.text.trim(),
        type: _type.text.trim(),
        responsible: _responsible.text.trim(),
      );
      navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUnfocus,
        child: _FormShell(
          title: 'Editar equipo',
          subtitle: 'Código ${widget.asset.code} (no se puede cambiar).',
          actionLabel: 'Guardar cambios',
          busy: _busy,
          onSubmit: _submit,
          fields: [
            _Field(
              label: 'Nombre del equipo',
              top: 4,
              child: TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Escribe un nombre.' : null,
              ),
            ),
            _Field(
              label: 'Tipo',
              child: TextFormField(
                controller: _type,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Indica el tipo.' : null,
              ),
            ),
            _Field(
              label: 'Responsable (opcional)',
              child: TextFormField(
                controller: _responsible,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(hintText: 'Ej. Soporte TI'),
              ),
            ),
          ],
        ),
      );
}

/// A quick-pick chip that fills a field; reads as a suggestion, not a toggle.
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: well,
        borderRadius: BorderRadius.circular(radiusControl),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radiusControl),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: inkSoft)),
          ),
        ),
      );
}
