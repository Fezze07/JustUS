// =============================================================================
// PartnerScreen - Partner search and request management
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/partner_state.dart';
import 'homepage_screen.dart';
import '../widgets/partner_widgets.dart';

class PartnerScreen extends StatefulWidget {
  const PartnerScreen({super.key});

  @override
  State<PartnerScreen> createState() => _PartnerScreenState();
}

class _PartnerScreenState extends State<PartnerScreen> {
  final _usernameController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<PartnerState>().fetchPartnership();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Partner'),
        centerTitle: true,
      ),
      body: Consumer<PartnerState>(
        builder: (context, state, _) {
          // Show messages
          if (state.message != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message!)),
              );
              state.clearMessage();
            });
          }

          // If has partner, navigate to homepage
          if (state.partner != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const HomepageScreen()),
              );
            });
          }

          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () => state.fetchPartnership(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Search section
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Cerca partner',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) => state.setUsernameQuery(value),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _codeController,
                            decoration: const InputDecoration(
                              labelText: 'Codice',
                              prefixIcon: Icon(Icons.tag),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) => state.setCodeQuery(value),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Search results
                  if (state.suggestedUsers.isNotEmpty) ...[
                    Text(
                      'Risultati',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...state.suggestedUsers.map((user) => PartnerUserTile(
                          user: user,
                          onSendRequest: () => state.sendPartnerRequest(
                            user.username,
                            user.code,
                          ),
                        )),
                    const SizedBox(height: 24),
                  ],

                  // Received requests
                  if (state.receivedRequests.isNotEmpty) ...[
                    Text(
                      'Richieste ricevute',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...state.receivedRequests.map((user) => PartnerRequestTile(
                          user: user,
                          onAccept: () => state.acceptPartner(user.id),
                          onReject: () => state.rejectPartner(user.id),
                        )),
                    const SizedBox(height: 24),
                  ],

                  // Sent requests
                  if (state.sentRequests.isNotEmpty) ...[
                    Text(
                      'Richieste inviate',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...state.sentRequests.map((user) => Card(
                          child: ListTile(
                            leading:
                                const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(user.username),
                            subtitle: Text('#${user.code}'),
                            trailing: const Icon(Icons.hourglass_empty),
                          ),
                        )),
                  ],

                  // Empty state
                  if (state.receivedRequests.isEmpty &&
                      state.sentRequests.isEmpty &&
                      state.suggestedUsers.isEmpty) ...[
                    const SizedBox(height: 48),
                    const Text(
                      '💑',
                      style: TextStyle(fontSize: 64),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Cerca il tuo partner usando\nusername e codice',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
