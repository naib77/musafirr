import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/utils/responsive.dart';
import '../../models/listing.dart';
import '../../models/listing_unit.dart';
import '../../models/property.dart';
import '../../models/rental_plan.dart';
import '../../models/room_labels.dart';
import '../../repositories/musafir_repository.dart';
import '../../services/verification/publish_gate.dart';
import '../../state/auth_state.dart';
import '../../widgets/app_network_image.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/host/trade_licence_card.dart';
import '../../widgets/modern_banner.dart';
import 'create_listing_screen.dart';
import 'edit_listing_screen.dart';
import 'property_form_screen.dart';

/// One hotel and its room types (plan §8): the hotel's facts, each room
/// type with its rooms by name, and the actions a host takes on them later
/// -- add rooms, retire one, move one to another type, duplicate or delete a
/// type, delete the whole hotel.
///
/// Rooms are written only through 153's RPCs, so every refusal here comes
/// back as a hint and is worded by [propertyRefusalMessage].
class PropertyDashboardScreen extends StatefulWidget {
  const PropertyDashboardScreen({
    super.key,
    required this.repository,
    required this.authState,
    required this.property,
    this.promptFirstRoomType = false,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final Property property;

  /// Straight from creating the hotel: open the room-type wizard at once,
  /// since a hotel with no room type is not shown to guests.
  final bool promptFirstRoomType;

  @override
  State<PropertyDashboardScreen> createState() =>
      _PropertyDashboardScreenState();
}

class _PropertyDashboardScreenState extends State<PropertyDashboardScreen> {
  late Property _property = widget.property;
  List<Listing> _types = const [];
  Map<String, List<ListingUnit>> _units = const {};
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.promptFirstRoomType && _types.isEmpty && mounted) {
        _addRoomType();
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final property =
          await widget.repository.fetchProperty(_property.id) ?? _property;
      final types = await widget.repository.propertyRoomTypes(_property.id);
      final units = <String, List<ListingUnit>>{};
      for (final t in types) {
        units[t.id] = await widget.repository.listingUnits(t.id);
      }
      if (!mounted) return;
      setState(() {
        _property = property;
        _types = types;
        _units = units;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ListingUnit> _active(String listingId) =>
      (_units[listingId] ?? const []).where((u) => u.isActive).toList();

  /// Through PublishGate like every other create entry point
  /// (shell-and-navigation.md): a room type is a listing.
  Future<void> _addRoomType({Listing? duplicateFrom}) async {
    if (!await PublishGate.ensure(context, widget.authState)) return;
    if (!mounted) return;
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateListingScreen(
          repository: widget.repository,
          authState: widget.authState,
          property: _property,
          duplicateFrom: duplicateFrom,
        ),
      ),
    );
    if (added == true) await _load();
  }

  Future<void> _editHotel() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PropertyFormScreen(
          repository: widget.repository,
          authState: widget.authState,
          property: _property,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _editType(Listing type) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            EditListingScreen(repository: widget.repository, listing: type),
      ),
    );
    await _load();
  }

  /// Runs one room write and reports a refusal by its hint. True on success.
  Future<bool> _roomWrite(Future<void> Function() write, String done) async {
    try {
      await write();
      if (mounted) ModernBanner.showSuccess(context, done);
      await _load();
      return true;
    } on PostgrestException catch (e) {
      if (mounted) {
        ModernBanner.showError(
          context,
          // A rename is a plain UPDATE: no hint, only the constraint's code.
          e.hint == null
              ? roomRenameRefusalMessage(e.code)
              : propertyRefusalMessage(e.hint),
        );
      }
      return false;
    } catch (_) {
      if (mounted) {
        ModernBanner.showError(context, propertyRefusalMessage(null));
      }
      return false;
    }
  }

  Future<void> _addRooms(Listing type) async {
    final labels = await showDialog<List<String>>(
      context: context,
      builder: (_) => _AddRoomsDialog(typeName: type.title),
    );
    if (labels == null || labels.isEmpty) return;
    await _roomWrite(
      // nameUnnamed: a type made with a bare count has "Room N" rooms the
      // host now wants to name -- name those before making more.
      () =>
          widget.repository.addListingUnits(type.id, labels, nameUnnamed: true),
      'Rooms added',
    );
  }

  Future<void> _renameRoom(ListingUnit unit, List<ListingUnit> rooms) async {
    final controller = TextEditingController(text: unit.label ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rename ${listingUnitName(unit, rooms)}'),
        content: AppTextField(
          controller: controller,
          label: 'Room name',
          hint: 'e.g., 204',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null) return;
    await _roomWrite(
      () => widget.repository
          .renameListingUnit(unit.id, normalizeRoomLabel(name)),
      'Room renamed',
    );
  }

  Future<void> _moveRoom(ListingUnit unit, Listing from) async {
    final others = _types.where((t) => t.id != from.id).toList();
    final to = await showDialog<Listing>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Move ${listingUnitName(unit, _active(from.id))} to'),
        children: [
          for (final t in others)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, t),
              child: Text(t.title),
            ),
        ],
      ),
    );
    if (to == null) return;
    await _roomWrite(
      () => widget.repository.moveListingUnit(unit.id, to.id),
      'Room moved to ${to.title}',
    );
  }

  Future<void> _removeRoom(ListingUnit unit, Listing from) async {
    final name = listingUnitName(unit, _active(from.id));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove room $name?'),
        content: const Text(
            'Guests can no longer book it. Past bookings keep it. You can '
            'add it back later under the same name.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _roomWrite(
      () => widget.repository.deactivateListingUnit(unit.id),
      'Room $name removed',
    );
  }

  /// Asks before a delete; the body says what goes with it.
  Future<bool> _confirmDelete(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteType(Listing type) async {
    final ok = await _confirmDelete(
      'Delete ${type.title}?',
      'Its rooms, photos and rates go with it. This cannot be undone. A room '
          'type with upcoming bookings cannot be deleted -- hide it instead '
          'from Edit.',
    );
    if (!ok) return;
    // Refusals (live bookings, paid history) come back as 156's hints.
    await _roomWrite(
      () => widget.repository.deleteRoomType(type.id),
      '${type.title} deleted',
    );
  }

  Future<void> _deleteHotel() async {
    final n = _types.length;
    final ok = await _confirmDelete(
      'Delete ${_property.name}?',
      'The hotel${n == 0 ? '' : ' and its $n room ${n == 1 ? 'type' : 'types'}'} '
          'will be removed for good. A hotel with upcoming bookings cannot be '
          'deleted.',
    );
    if (!ok) return;
    try {
      await widget.repository.deleteProperty(_property.id);
      if (!mounted) return;
      ModernBanner.showSuccess(context, '${_property.name} deleted');
      // Nothing left to show here; the hotel list refreshes off the
      // repository's notify.
      Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (mounted) {
        ModernBanner.showError(context, propertyRefusalMessage(e.hint));
      }
    } catch (_) {
      if (mounted) {
        ModernBanner.showError(context, propertyRefusalMessage(null));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _property;
    final stars = p.hotelDetails.starRating;
    final totalRooms = _types.fold<int>(0, (n, t) => n + _active(t.id).length);

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            tooltip: 'Edit hotel',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editHotel,
          ),
          PopupMenuButton<String>(
            tooltip: 'More hotel actions',
            onSelected: (v) {
              if (v == 'delete') _deleteHotel();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete hotel')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _addRoomType(),
        icon: const Icon(Icons.add),
        label: const Text('Add room type'),
      ),
      body: ResponsiveCenter(
        maxWidth: 860,
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(
                [
                  if (stars != null) '$stars-star',
                  if (p.publicAddress.isNotEmpty) p.publicAddress,
                ].join(' · '),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_types.length} room '
                '${_types.length == 1 ? 'type' : 'types'} · $totalRooms '
                '${totalRooms == 1 ? 'room' : 'rooms'}',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              if (_loading && _types.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (_loadError != null)
                Text(
                  'Could not load the room types. Pull to retry.',
                  style: TextStyle(color: theme.colorScheme.error),
                )
              else if (_types.isEmpty)
                _EmptyTypes(onAdd: () => _addRoomType())
              else
                for (final t in _types)
                  _RoomTypeCard(
                    type: t,
                    rooms: _active(t.id),
                    canMove: _types.length > 1,
                    onEdit: () => _editType(t),
                    onDuplicate: () => _addRoomType(duplicateFrom: t),
                    onDelete: () => _deleteType(t),
                    onAddRooms: () => _addRooms(t),
                    onRename: (u) => _renameRoom(u, _active(t.id)),
                    onMove: (u) => _moveRoom(u, t),
                    onRemove: (u) => _removeRoom(u, t),
                  ),
              // The licence is filed on one room type and verified for the
              // whole hotel (153's listing_licence_verified), so it lives
              // here once rather than on every type's edit screen.
              if (_types.isNotEmpty) ...[
                const SizedBox(height: 16),
                TradeLicenceCard(listingId: _types.first.id),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTypes extends StatelessWidget {
  const _EmptyTypes({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.bed_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              'Add your first room type',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Guests see the hotel once it has a room type. Add each kind '
              'of room — Deluxe, Super Deluxe, Sea Front — with its rooms.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAdd, child: const Text('Add room type')),
          ],
        ),
      ),
    );
  }
}

class _RoomTypeCard extends StatelessWidget {
  const _RoomTypeCard({
    required this.type,
    required this.rooms,
    required this.canMove,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    required this.onAddRooms,
    required this.onRename,
    required this.onMove,
    required this.onRemove,
  });

  final Listing type;
  final List<ListingUnit> rooms;
  final bool canMove;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onAddRooms;
  final ValueChanged<ListingUnit> onRename;
  final ValueChanged<ListingUnit> onMove;
  final ValueChanged<ListingUnit> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = type.cheapestPlan;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Each type has its own photos (Edit → Photos); the
                // thumbnail is what tells the host which is which.
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: type.primaryImage == null
                      ? Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.bed_outlined,
                              color: theme.colorScheme.onSurfaceVariant),
                        )
                      : AppNetworkImage(
                          url: type.primaryImage!,
                          width: 56,
                          height: 56,
                          decodeWidth: 168,
                          borderRadius: BorderRadius.circular(8),
                        ),
                ),
                Expanded(
                  child: Text(
                    type.title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (!type.available)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Chip(label: Text('Hidden')),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Room type actions',
                  onSelected: (v) => switch (v) {
                    'edit' => onEdit(),
                    'duplicate' => onDuplicate(),
                    'delete' => onDelete(),
                    _ => null,
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'edit', child: Text('Edit details & photos')),
                    PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            Text(
              [
                if (plan != null)
                  '${type.displayPriceMoney.format(showDecimal: false)}'
                      '/${plan.shortUnit}',
                '${type.maxGuests} guests',
                '${rooms.length} ${rooms.length == 1 ? 'room' : 'rooms'}',
              ].join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final u in rooms)
                  _RoomChip(
                    name: listingUnitName(u, rooms),
                    // The last room cannot go (unit_count_range); hiding
                    // the action beats offering a refusal.
                    canRemove: rooms.length > 1,
                    canMove: canMove,
                    onRename: () => onRename(u),
                    onMove: () => onMove(u),
                    onRemove: () => onRemove(u),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add rooms'),
                  onPressed: onAddRooms,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomChip extends StatelessWidget {
  const _RoomChip({
    required this.name,
    required this.canRemove,
    required this.canMove,
    required this.onRename,
    required this.onMove,
    required this.onRemove,
  });

  final String name;
  final bool canRemove;
  final bool canMove;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Room $name',
      onSelected: (v) => switch (v) {
        'rename' => onRename(),
        'move' => onMove(),
        'remove' => onRemove(),
        _ => null,
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        if (canMove)
          const PopupMenuItem(
              value: 'move', child: Text('Move to another room type')),
        if (canRemove)
          const PopupMenuItem(value: 'remove', child: Text('Remove')),
      ],
      child: Semantics(
        button: true,
        label: 'Room $name',
        child: Chip(label: Text(name)),
      ),
    );
  }
}

/// Room names to add, with the same parser and feedback as the wizard.
class _AddRoomsDialog extends StatefulWidget {
  const _AddRoomsDialog({required this.typeName});

  final String typeName;

  @override
  State<_AddRoomsDialog> createState() => _AddRoomsDialogState();
}

class _AddRoomsDialogState extends State<_AddRoomsDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = parseRoomLabels(_controller.text);
    return AlertDialog(
      title: Text('Add rooms to ${widget.typeName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _controller,
            label: 'Room numbers',
            hint: 'e.g., 301-308, 401',
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          if (parsed.labels.isNotEmpty)
            Text('${parsed.labels.length} '
                '${parsed.labels.length == 1 ? 'room' : 'rooms'}'),
          for (final e in parsed.errors)
            Text(e,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: parsed.isValid && parsed.labels.isNotEmpty
              ? () => Navigator.pop(context, parsed.labels)
              : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
