import 'package:flutter/material.dart';

import '../services/contact_phone.dart';
import 'app_text_field.dart';

/// The rows behind a [ContactPhonesField]: one [TextEditingController] per
/// number, never fewer than one so there is always a field to type into.
///
/// A controller rather than state inside the widget because three forms
/// (new listing, edit listing, hotel) own the save, the dirty check and the
/// step validation; they read [texts] / [normalized] the way they read a
/// plain [TextEditingController]'s `text`.
class ContactPhonesController extends ChangeNotifier {
  ContactPhonesController() : _rows = [TextEditingController()];

  final List<TextEditingController> _rows;

  List<TextEditingController> get rows => List.unmodifiable(_rows);

  /// What the host typed, row by row, blanks included.
  List<String> get texts => [for (final r in _rows) r.text];

  bool get canAdd => _rows.length < maxContactPhones;

  /// The stored list, shown in the national spelling hosts recognise.
  /// Replaces every row; an empty list leaves one blank field.
  void setStored(List<String> stored) {
    for (final r in _rows) {
      r.dispose();
    }
    _rows
      ..clear()
      ..addAll([
        for (final s in stored.take(maxContactPhones))
          TextEditingController(text: displayContactPhone(s)),
      ]);
    if (_rows.isEmpty) _rows.add(TextEditingController());
    notifyListeners();
  }

  void add() {
    if (!canAdd) return;
    _rows.add(TextEditingController());
    notifyListeners();
  }

  /// Removing the last remaining row clears it instead, so the field never
  /// disappears from the form.
  void removeAt(int index) {
    if (_rows.length == 1) {
      _rows.first.clear();
    } else {
      _rows.removeAt(index).dispose();
    }
    notifyListeners();
  }

  /// What the address row stores; throws [FormatException] like
  /// [normalizeContactPhones]. Check [error] first.
  List<String> normalized() => normalizeContactPhones(texts);

  /// Why the list cannot be saved, or null.
  String? get error => contactPhonesError(texts);

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }
}

/// "Contact phones (optional)": one field per number, a remove button on
/// each when there is more than one, and "Add another number" up to
/// [maxContactPhones]. Each field validates on its own, so the message sits
/// under the number that is wrong.
class ContactPhonesField extends StatelessWidget {
  const ContactPhonesField({
    super.key,
    required this.controller,
    this.onChanged,
  });

  final ContactPhonesController controller;

  /// Called after any edit, add or remove -- the forms' dirty / step checks.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final rows = controller.rows;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              AppTextField(
                // Keyed by controller so removing row 1 of 3 does not hand
                // row 2's text field row 1's state.
                key: ObjectKey(rows[i]),
                controller: rows[i],
                label: i == 0
                    ? 'Contact phone (optional)'
                    : 'Contact phone ${i + 1}',
                hint: 'e.g., 01711 165212',
                keyboardType: TextInputType.phone,
                validator: contactPhoneValidator,
                onChanged: (_) => onChanged?.call(),
                suffix: rows.length > 1
                    // A Tooltip does not name a control; Semantics does.
                    ? Semantics(
                        button: true,
                        label: 'Remove contact phone ${i + 1}',
                        child: IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () {
                            controller.removeAt(i);
                            onChanged?.call();
                          },
                        ),
                      )
                    : null,
              ),
            ],
            if (controller.canAdd)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    controller.add();
                    onChanged?.call();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add another number'),
                ),
              ),
          ],
        );
      },
    );
  }
}
