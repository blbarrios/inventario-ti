import 'package:flutter/material.dart';

import 'inventory_theme.dart';

enum AssetStatus { unknown, operational, faulty, maintenance, offline }

/// Most urgent first: the order used in every summary, legend and tag row.
const statusesBySeverity = [
  AssetStatus.faulty,
  AssetStatus.offline,
  AssetStatus.maintenance,
  AssetStatus.operational,
  AssetStatus.unknown,
];

extension StatusView on AssetStatus {
  String get label => switch (this) {
        AssetStatus.unknown => 'Sin verificar',
        AssetStatus.operational => 'Operativo',
        AssetStatus.faulty => 'Con falla',
        AssetStatus.maintenance => 'En mantenimiento',
        AssetStatus.offline => 'Fuera de servicio',
      };

  /// Text colour: passes 4.5:1 on white.
  Color get color => switch (this) {
        AssetStatus.unknown => inkFaint,
        AssetStatus.operational => const Color(0xFF1D7148),
        AssetStatus.faulty => const Color(0xFFB4232A),
        AssetStatus.maintenance => const Color(0xFF8F5607),
        AssetStatus.offline => inkSoft,
      };

  /// LED colour, as the light on a switch port would show it.
  Color get led => switch (this) {
        AssetStatus.unknown => const Color(0xFFC3C7D0),
        AssetStatus.operational => const Color(0xFF2EA66A),
        AssetStatus.faulty => const Color(0xFFE5484D),
        AssetStatus.maintenance => const Color(0xFFF0A020),
        AssetStatus.offline => inkFaint,
      };

  /// A lit LED glows; "fuera de servicio" is a dark (hollow) LED and
  /// "sin verificar" a dim one.
  bool get lit =>
      this == AssetStatus.operational ||
      this == AssetStatus.faulty ||
      this == AssetStatus.maintenance;

  /// The string the API uses (matches the enum name).
  String get api => name;
}

AssetStatus statusFromApi(String value) => AssetStatus.values
    .firstWhere((s) => s.name == value, orElse: () => AssetStatus.unknown);

/// What a device looks like on the plan. The glyphs are outlined to match the
/// rest of the app; status gives them their colour, not identity.
enum DeviceIcon {
  generic,
  computer,
  laptop,
  server,
  networkSwitch,
  router,
  accessPoint,
  phone,
  printer,
  ups,
  patchPanel,
  camera,
  screen,
}

extension DeviceIconView on DeviceIcon {
  String get label => switch (this) {
        DeviceIcon.generic => 'Genérico',
        DeviceIcon.computer => 'Computador',
        DeviceIcon.laptop => 'Portátil',
        DeviceIcon.server => 'Servidor',
        DeviceIcon.networkSwitch => 'Switch',
        DeviceIcon.router => 'Router',
        DeviceIcon.accessPoint => 'Punto de acceso',
        DeviceIcon.phone => 'Teléfono',
        DeviceIcon.printer => 'Impresora',
        DeviceIcon.ups => 'UPS',
        DeviceIcon.patchPanel => 'Patch panel',
        DeviceIcon.camera => 'Cámara',
        DeviceIcon.screen => 'Pantalla',
      };

  IconData get data => switch (this) {
        DeviceIcon.generic => Icons.devices_other_outlined,
        DeviceIcon.computer => Icons.desktop_windows_outlined,
        DeviceIcon.laptop => Icons.laptop_mac,
        DeviceIcon.server => Icons.dns_outlined,
        DeviceIcon.networkSwitch => Icons.hub_outlined,
        DeviceIcon.router => Icons.router_outlined,
        DeviceIcon.accessPoint => Icons.wifi_rounded,
        DeviceIcon.phone => Icons.smartphone_outlined,
        DeviceIcon.printer => Icons.print_outlined,
        DeviceIcon.ups => Icons.battery_charging_full_outlined,
        DeviceIcon.patchPanel => Icons.view_week_outlined,
        DeviceIcon.camera => Icons.videocam_outlined,
        DeviceIcon.screen => Icons.tv_outlined,
      };

  /// Stable key stored in the database.
  String get key => this == DeviceIcon.networkSwitch ? 'switch' : name;
}

DeviceIcon deviceIconFromKey(String key) {
  if (key == 'switch') return DeviceIcon.networkSwitch;
  return DeviceIcon.values
      .firstWhere((d) => d.name == key, orElse: () => DeviceIcon.generic);
}

/// Best-guess icon from a free-text type, so new devices start sensibly.
DeviceIcon deviceIconForType(String type) {
  final t = type.toLowerCase();
  bool has(String s) => t.contains(s);
  if (has('switch')) return DeviceIcon.networkSwitch;
  if (has('router')) return DeviceIcon.router;
  if (has('acceso') || has('wifi') || has('wi-fi') || has('access')) {
    return DeviceIcon.accessPoint;
  }
  if (has('servidor') || has('server') || has('nas')) return DeviceIcon.server;
  if (has('patch')) return DeviceIcon.patchPanel;
  if (has('ups')) return DeviceIcon.ups;
  if (has('portát') || has('portat') || has('laptop')) return DeviceIcon.laptop;
  if (has('comput') || has('desktop') || has('pc') || has('cpu')) {
    return DeviceIcon.computer;
  }
  if (has('tel') ||
      has('phone') ||
      has('celular') ||
      has('móvil') ||
      has('movil')) {
    return DeviceIcon.phone;
  }
  if (has('impres') || has('print')) return DeviceIcon.printer;
  if (has('cámara') || has('camara') || has('cam')) return DeviceIcon.camera;
  if (has('pantalla') ||
      has('monitor') ||
      has('tv') ||
      has('videobeam') ||
      has('proyector')) {
    return DeviceIcon.screen;
  }
  return DeviceIcon.generic;
}

class StatusChange {
  const StatusChange(this.previous, this.current, this.note, this.at);
  final AssetStatus previous;
  final AssetStatus current;
  final String note;
  final DateTime at;
}

class Asset {
  Asset(this.code, this.name, this.type, this.position,
      {this.status = AssetStatus.unknown,
      DeviceIcon? icon,
      String? id,
      this.statusVersion = 1,
      this.hasPosition = true})
      : id = id ?? code,
        icon = icon ?? deviceIconForType(type);

  factory Asset.fromJson(Map<String, dynamic> json) {
    final x = (json['x'] as num?)?.toDouble();
    final y = (json['y'] as num?)?.toDouble();
    return Asset(
      json['code'] as String,
      json['name'] as String,
      json['type'] as String,
      Offset(x ?? 0.5, y ?? 0.5),
      id: json['id'] as String,
      status: statusFromApi(json['status'] as String? ?? 'unknown'),
      statusVersion: (json['status_version'] as num?)?.toInt() ?? 1,
      icon: deviceIconFromKey(json['icon'] as String? ?? 'generic'),
      hasPosition: x != null && y != null,
    );
  }

  /// Server id (a uuid from the API, or the code for demo/local data).
  final String id;
  final String code, name, type;
  Offset position;

  /// Whether the server has a saved position; false until a layout is saved.
  bool hasPosition;
  AssetStatus status;

  /// Optimistic-concurrency token for status updates.
  int statusVersion;

  /// How the device is drawn on the plan; colour still comes from [status].
  DeviceIcon icon;

  final history = <StatusChange>[];

  void updateStatus(AssetStatus next, String note) {
    if (next == status) return;
    history.insert(0, StatusChange(status, next, note.trim(), DateTime.now()));
    status = next;
  }
}

class Room {
  Room(this.name, this.assets, {String? id, this.layoutVersion = 1})
      : id = id ?? name;

  factory Room.fromJson(Map<String, dynamic> json) => Room(
        json['name'] as String,
        [
          for (final asset in (json['assets'] as List? ?? const []))
            Asset.fromJson(asset as Map<String, dynamic>),
        ],
        id: json['id'] as String,
        layoutVersion: (json['layout_version'] as num?)?.toInt() ?? 1,
      );

  final String id;
  final String name;
  final List<Asset> assets;

  /// Optimistic-concurrency token for layout (position) updates.
  int layoutVersion;

  int count(AssetStatus status) =>
      assets.where((asset) => asset.status == status).length;
}

List<Room> demoRooms() => [
      Room('Sala de sistemas 1', [
        Asset('SW-R1-01', 'Switch principal Cisco', 'Switch',
            const Offset(.12, .22)),
        Asset('SW-R1-02', 'Switch de acceso Cisco', 'Switch',
            const Offset(.80, .22)),
        Asset('RTR-R1-01', 'Router fibra', 'Router', const Offset(.12, .70)),
        Asset('RTR-R1-02', 'Router Starlink', 'Router', const Offset(.80, .70)),
      ]),
      Room('Sala de sistemas 2', [
        Asset('SW-R2-01', 'Switch 3Com', 'Switch', const Offset(.2, .2)),
        Asset('SW-R2-02', 'Switch HP', 'Switch', const Offset(.6, .6)),
      ]),
      Room('Sala de bienestar', [
        Asset('AP-R4-01', 'Punto de acceso', 'Punto de acceso Wi-Fi',
            const Offset(.4, .4)),
      ]),
    ];

/// The status indicator used everywhere: a small port LED.
class StatusLed extends StatelessWidget {
  const StatusLed(this.status, {super.key, this.size = 8});
  final AssetStatus status;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: status == AssetStatus.offline ? null : status.led,
            border: status == AssetStatus.offline
                ? Border.all(color: status.led, width: size < 9 ? 1.5 : 2)
                : null,
            boxShadow: status.lit
                ? [
                    BoxShadow(
                        color: status.led.withValues(alpha: .28),
                        spreadRadius: size * .3),
                  ]
                : null,
          ),
        ),
      );
}

/// A device drawn as its icon, coloured by status. This is the per-device
/// indicator on the plan and in lists (the LED stays for status legends).
class DeviceGlyph extends StatelessWidget {
  const DeviceGlyph(this.icon, this.status, {super.key, this.size = 20});
  final DeviceIcon icon;
  final AssetStatus status;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(icon.data, size: size, color: status.color);
}

/// A grid of device icons to choose from.
class IconPicker extends StatelessWidget {
  const IconPicker({super.key, required this.value, required this.onChanged});
  final DeviceIcon value;
  final ValueChanged<DeviceIcon> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final icon in DeviceIcon.values)
            _IconTile(
              icon: icon,
              selected: icon == value,
              onTap: () => onChanged(icon),
            ),
        ],
      );
}

class _IconTile extends StatelessWidget {
  const _IconTile(
      {required this.icon, required this.selected, required this.onTap});
  final DeviceIcon icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: icon.label,
        child: Semantics(
          button: true,
          selected: selected,
          inMutuallyExclusiveGroup: true,
          label: icon.label,
          child: Material(
            color: selected ? selectedFill : well,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusControl),
              side: BorderSide(
                  color: selected ? ink : Colors.transparent,
                  width: selected ? 1.5 : 1),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radiusControl),
              child: SizedBox.square(
                dimension: 46,
                child:
                    Icon(icon.data, size: 22, color: selected ? ink : inkSoft),
              ),
            ),
          ),
        ),
      );
}

/// LED plus label (and optional count), no fill: "● 4 Sin verificar".
class StatusTag extends StatelessWidget {
  const StatusTag(this.status, {super.key, this.count, this.strong = false});
  final AssetStatus status;

  /// When set, shown before the label for legends.
  final int? count;

  /// Use the status colour for the label (detail views) instead of ink.
  final bool strong;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusLed(status),
          const SizedBox(width: 7),
          if (count != null) ...[
            Text('$count', style: monoStyle(size: 12.5, color: ink)),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              status.label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: strong ? status.color : inkSoft,
              ),
            ),
          ),
        ],
      );
}
