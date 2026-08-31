import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A labelled text field used across the medicine, patient and pharmacy forms.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.sentences,
    this.numericOnly = false,
    this.decimal = false,
    this.autofocus = false,
    this.onChanged,
    this.helperText,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final bool numericOnly;
  final bool decimal;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final String? helperText;

  /// Revalidates as the user types once they have interacted, so a corrected
  /// field clears its error immediately instead of waiting for the next save.
  final AutovalidateMode autovalidateMode;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      autovalidateMode: autovalidateMode,
      maxLines: maxLines,
      autofocus: autofocus,
      onChanged: onChanged,
      textCapitalization: numericOnly ? TextCapitalization.none : textCapitalization,
      keyboardType: keyboardType ??
          (numericOnly
              ? (decimal
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.number)
              : (maxLines > 1 ? TextInputType.multiline : TextInputType.text)),
      inputFormatters: numericOnly
          ? [
              FilteringTextInputFormatter.allow(
                decimal ? RegExp(r'[0-9.]') : RegExp(r'[0-9]'),
              ),
            ]
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helperText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
        suffixIcon: suffix,
      ),
    );
  }
}

/// The dashboard search field — searches every medicine field at once.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = 'Search medicines, notes, patients…',
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search, size: 22),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
    );
  }
}
