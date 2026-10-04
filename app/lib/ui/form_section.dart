import 'package:flutter/material.dart';

import '../theme.dart';

/// The small heading that starts a part of a long form: what follows
/// belongs together (where, who signs in, the terminal).
class FormSectionTitle extends StatelessWidget {
  const FormSectionTitle(this.title, {super.key, this.first = false});

  final String title;

  /// The form's first part: no room above it.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 26, bottom: 12),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(color: c.muted, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.3),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(height: 1, color: c.line)),
        ],
      ),
    );
  }
}

/// The bar under a form, always in reach however long the form is.
class FormFooter extends StatelessWidget {
  const FormFooter({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (final (i, child) in children.indexed) ...[if (i > 0) const SizedBox(width: 10), child],
            ],
          ),
        ),
      ),
    );
  }
}
