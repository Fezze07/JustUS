// =============================================================================
// PartnerWidgets - Partner search and request tiles
// =============================================================================

import 'package:flutter/material.dart';
import 'package:justus/all_imports.dart';

abstract class PartnerWidgets {}

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
        trailing: FilledButton(
          onPressed: onSendRequest,
          child: Text(context.loc.partner_requestButton),
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
