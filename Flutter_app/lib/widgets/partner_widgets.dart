// =============================================================================
// PartnerWidgets - Partner search and request tiles
// =============================================================================

import 'package:flutter/material.dart';
import '../models/models.dart';

class PartnerUserTile extends StatelessWidget {
  final User user;
  final VoidCallback onSendRequest;

  const PartnerUserTile({
    super.key,
    required this.user,
    required this.onSendRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(user.username),
        subtitle: Text('#${user.code}'),
        trailing: FilledButton(
          onPressed: onSendRequest,
          child: const Text('Richiedi'),
        ),
      ),
    );
  }
}

class PartnerRequestTile extends StatelessWidget {
  final User user;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const PartnerRequestTile({
    super.key,
    required this.user,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(user.username),
        subtitle: Text('#${user.code}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              onPressed: onAccept,
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: onReject,
            ),
          ],
        ),
      ),
    );
  }
}
