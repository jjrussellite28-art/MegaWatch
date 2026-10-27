import 'package:flutter/material.dart';

/// Shows the categories that look non-English and asks before hiding them.
/// Returns true to hide. Controller-friendly: the Hide button is focused first.
Future<bool> confirmHideNonEnglish(BuildContext context, List<String> names) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Hide ${names.length} non-English categor${names.length == 1 ? 'y' : 'ies'}?'),
      content: SizedBox(
        width: 460,
        height: 300,
        child: names.isEmpty
            ? const Center(child: Text('No non-English categories found.'))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'These look like another language. They stop loading and showing up '
                    '(list, search, guide). Nothing is deleted — you can show them again '
                    'in Settings › IPTV › Hidden categories.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.builder(
                      itemCount: names.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• ${names[i]}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        if (names.isNotEmpty)
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hide them'),
          ),
      ],
    ),
  );
  return result == true;
}
