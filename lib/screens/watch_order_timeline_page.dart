import 'package:flutter/material.dart';

import '../services/watch_order_service.dart';

/// The whole universe in order, as the "Watch Order" add-on (u/demon-myth)
/// lists it. Tap a line to open that title.
class WatchOrderTimelinePage extends StatefulWidget {
  const WatchOrderTimelinePage({
    super.key,
    required this.universeId,
    required this.title,
    required this.onOpen,
  });

  final String universeId;
  final String title;
  final void Function(WatchOrderTimelineItem item) onOpen;

  @override
  State<WatchOrderTimelinePage> createState() => _WatchOrderTimelinePageState();
}

class _WatchOrderTimelinePageState extends State<WatchOrderTimelinePage> {
  late Future<List<WatchOrderTimelineItem>> _items;

  @override
  void initState() {
    super.initState();
    _items = WatchOrderService.instance.timeline(widget.universeId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<List<WatchOrderTimelineItem>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('Could not load the timeline.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: items.length + 1,
            itemBuilder: (context, i) {
              if (i == items.length) {
                return const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'Watch order data: the Watch Order add-on by u/demon-myth.',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                );
              }
              final item = items[i];
              return ListTile(
                leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                title: Text(item.title),
                subtitle: item.year == null ? null : Text(item.year!),
                onTap: item.canOpen ? () => widget.onOpen(item) : null,
                trailing: item.canOpen
                    ? const Icon(Icons.chevron_right_rounded)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
