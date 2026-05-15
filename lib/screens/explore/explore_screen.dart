import 'package:flutter/material.dart';

import '../../models/listing.dart';
import '../../models/listing_type.dart';
import '../../models/search_filters.dart';
import '../../repositories/musafir_repository.dart';
import '../../state/auth_state.dart';
import '../../state/favorites_state.dart';
import '../../state/search_state.dart';
import '../../widgets/category_scroll.dart';
import '../../widgets/listing_card_modern.dart';
import 'listing_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    required this.repository,
    required this.authState,
    required this.favoritesState,
    required this.searchState,
  });

  final MusafirRepository repository;
  final AuthStateNotifier authState;
  final FavoritesStateNotifier favoritesState;
  final SearchStateNotifier searchState;

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  ListingType? _selectedType;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Listing> get _filteredListings {
    var listings = widget.searchState.results;
    if (listings.isEmpty) {
      listings = widget.repository.listings.where((l) => l.available).toList();
    }
    if (_selectedType != null) {
      listings = listings.where((l) => l.type == _selectedType).toList();
    }
    return listings;
  }

  void _openListingDetail(Listing listing) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ListingDetailScreen(
          listing: listing,
          repository: widget.repository,
          authState: widget.authState,
          favoritesState: widget.favoritesState,
        ),
      ),
    );
  }

  void _openSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SearchSheet(
        searchController: _searchController,
        searchState: widget.searchState,
        onSearch: () {
          Navigator.pop(context);
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: _openSearch,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.searchState.filters.location ??
                                  'Where to?',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _getSearchSubtitle(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.searchState.filters.hasActiveFilters)
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            widget.searchState.clearFilters();
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant,
                            ),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(
                            Icons.tune,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // Category scroll
            CategoryScroll(
              selectedType: _selectedType,
              onTypeSelected: (type) {
                setState(() => _selectedType = type);
              },
            ),

            const Divider(height: 1),

            // Listings grid
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  widget.repository,
                  widget.favoritesState,
                  widget.searchState,
                ]),
                builder: (context, _) {
                  final listings = _filteredListings;

                  if (listings.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No listings found',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try adjusting your filters',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 24,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.65,
                    ),
                    itemCount: listings.length,
                    itemBuilder: (context, index) {
                      final listing = listings[index];
                      return ListingCardModern(
                        listing: listing,
                        isFavorite:
                            widget.favoritesState.isFavorite(listing.id),
                        onTap: () => _openListingDetail(listing),
                        onFavoriteTap: () {
                          widget.favoritesState.toggleFavorite(listing.id);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getSearchSubtitle() {
    final filters = widget.searchState.filters;
    final parts = <String>[];

    // Property type
    if (filters.propertyTypes.isNotEmpty) {
      if (filters.propertyTypes.length == 1) {
        parts.add(filters.propertyTypes.first.title);
      } else {
        parts.add('${filters.propertyTypes.length} types');
      }
    }

    // Date/time
    if (filters.dateMode == SearchDateMode.dateRange) {
      if (filters.checkIn != null && filters.checkOut != null) {
        parts.add(
            '${_formatDate(filters.checkIn!)} - ${_formatDate(filters.checkOut!)}');
      } else {
        parts.add('Any week');
      }
    } else {
      if (filters.singleDate != null) {
        var dateStr = _formatDate(filters.singleDate!);
        if (filters.startTime != null && filters.endTime != null) {
          dateStr += ' ${_formatTime(filters.startTime!)} - ${_formatTime(filters.endTime!)}';
        }
        parts.add(dateStr);
      } else {
        parts.add('Any day');
      }
    }

    parts
        .add('${filters.guestCount} guest${filters.guestCount > 1 ? 's' : ''}');

    return parts.join(' · ');
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour$period';
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({
    required this.searchController,
    required this.searchState,
    required this.onSearch,
  });

  final TextEditingController searchController;
  final SearchStateNotifier searchState;
  final VoidCallback onSearch;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  late int _guestCount;
  DateTimeRange? _dateRange;
  List<ListingType> _selectedTypes = [];
  SearchDateMode _dateMode = SearchDateMode.dateRange;
  DateTime? _singleDate;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;

  @override
  void initState() {
    super.initState();
    final filters = widget.searchState.filters;
    _guestCount = filters.guestCount;
    _selectedTypes = List.from(filters.propertyTypes);
    _dateMode = filters.dateMode;
    widget.searchController.text = filters.location ?? '';

    if (filters.checkIn != null && filters.checkOut != null) {
      _dateRange = DateTimeRange(
        start: filters.checkIn!,
        end: filters.checkOut!,
      );
    }

    _singleDate = filters.singleDate;
    _startTime = filters.startTime;
    _endTime = filters.endTime;
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  Future<void> _selectSingleDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _singleDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _singleDate = picked);
    }
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked != null) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime ?? const TimeOfDay(hour: 17, minute: 0),
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  void _togglePropertyType(ListingType type) {
    setState(() {
      if (_selectedTypes.contains(type)) {
        _selectedTypes.remove(type);
      } else {
        _selectedTypes.add(type);
      }
    });
  }

  void _applySearch() {
    widget.searchState.updateFilters(
      widget.searchState.filters.copyWith(
        location: widget.searchController.text.isEmpty
            ? null
            : widget.searchController.text,
        checkIn: _dateMode == SearchDateMode.dateRange ? _dateRange?.start : null,
        checkOut: _dateMode == SearchDateMode.dateRange ? _dateRange?.end : null,
        guestCount: _guestCount,
        propertyTypes: _selectedTypes,
        dateMode: _dateMode,
        singleDate: _dateMode == SearchDateMode.singleDateWithTime ? _singleDate : null,
        startTime: _dateMode == SearchDateMode.singleDateWithTime ? _startTime : null,
        endTime: _dateMode == SearchDateMode.singleDateWithTime ? _endTime : null,
        clearLocation: widget.searchController.text.isEmpty,
        clearDates: _dateMode == SearchDateMode.dateRange && _dateRange == null,
        clearTime: _dateMode == SearchDateMode.dateRange,
      ),
    );
    widget.onSearch();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            Text(
              'Search',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),

            // Property Type Filter
            Text(
              'Property Type',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: _selectedTypes.isEmpty,
                  onSelected: (_) {
                    setState(() => _selectedTypes.clear());
                  },
                ),
                ...ListingType.values.map((type) => FilterChip(
                  label: Text(type.title),
                  selected: _selectedTypes.contains(type),
                  onSelected: (_) => _togglePropertyType(type),
                )),
              ],
            ),
            const SizedBox(height: 20),

            // Location
            TextField(
              controller: widget.searchController,
              decoration: InputDecoration(
                labelText: 'Where',
                hintText: 'Search destinations',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Date Mode Toggle
            Text(
              'When',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<SearchDateMode>(
              segments: const [
                ButtonSegment(
                  value: SearchDateMode.dateRange,
                  label: Text('Date Range'),
                  icon: Icon(Icons.date_range),
                ),
                ButtonSegment(
                  value: SearchDateMode.singleDateWithTime,
                  label: Text('Single Day'),
                  icon: Icon(Icons.schedule),
                ),
              ],
              selected: {_dateMode},
              onSelectionChanged: (selected) {
                setState(() => _dateMode = selected.first);
              },
            ),
            const SizedBox(height: 16),

            // Date Range Selection (shown when dateRange mode)
            if (_dateMode == SearchDateMode.dateRange) ...[
              GestureDetector(
                onTap: _selectDateRange,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Check-in - Check-out',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              _dateRange != null
                                  ? '${_formatDate(_dateRange!.start)} - ${_formatDate(_dateRange!.end)}'
                                  : 'Select dates',
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      if (_dateRange != null)
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _dateRange = null),
                        ),
                    ],
                  ),
                ),
              ),
            ],

            // Single Date with Time Selection
            if (_dateMode == SearchDateMode.singleDateWithTime) ...[
              // Date picker
              GestureDetector(
                onTap: _selectSingleDate,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              _singleDate != null
                                  ? _formatDate(_singleDate!)
                                  : 'Select date',
                              style: theme.textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      if (_singleDate != null)
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _singleDate = null),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Time range row
              Row(
                children: [
                  // Start time
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectStartTime,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Time',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _startTime != null
                                      ? _formatTime(_startTime!)
                                      : 'Select',
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // End time
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectEndTime,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End Time',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.access_time, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  _endTime != null
                                      ? _formatTime(_endTime!)
                                      : 'Select',
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),

            // Guests
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.people),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Who',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '$_guestCount guest${_guestCount > 1 ? 's' : ''}',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _guestCount > 1
                            ? () => setState(() => _guestCount--)
                            : null,
                      ),
                      Text(
                        '$_guestCount',
                        style: theme.textTheme.titleMedium,
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _guestCount < 16
                            ? () => setState(() => _guestCount++)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Search button
            FilledButton(
              onPressed: _applySearch,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search),
                  SizedBox(width: 8),
                  Text('Search'),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}
