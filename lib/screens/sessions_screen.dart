import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/session.dart';
import '../widgets/dialogs.dart';
import '../widgets/exercise_summary.dart';
import 'running_screen.dart';
import 'session_editor_screen.dart';
import 'settings_screen.dart';

/// Home screen: every saved session.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  @override
  void initState() {
    super.initState();
    // Check once on launch so a sideloaded APK still gets notified of new
    // releases - see UpdateService.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).updates.checkOnLaunch(context);
    });
  }

  void _open(Session session) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SessionEditorScreen(sessionId: session.id),
        ),
      );

  Future<void> _create() async {
    final name = await showTextInputDialog(
      context,
      title: 'New session',
      hintText: 'e.g. Knee rehab - morning',
      confirmLabel: 'Create',
    );
    if (name == null || !mounted) return;
    final session = await AppScope.of(context).sessions.create(name);
    if (mounted) _open(session);
  }

  Future<void> _rename(Session session) async {
    final name = await showTextInputDialog(
      context,
      title: 'Rename session',
      initialValue: session.name,
      confirmLabel: 'Rename',
    );
    if (name != null && mounted) {
      await AppScope.of(context).sessions.update(session.copyWith(name: name));
    }
  }

  Future<void> _delete(Session session) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete session?',
      message: '"${session.name}" and its exercises will be deleted.',
      confirmLabel: 'Delete',
    );
    if (confirmed && mounted) {
      await AppScope.of(context).sessions.delete(session.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).sessions;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tonaros'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New session'),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final sessions = store.sessions;
          if (sessions.isEmpty) return const _EmptyState();
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
            itemCount: sessions.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _SessionCard(
              session: sessions[i],
              onTap: () => _open(sessions[i]),
              onStart: () => RunningScreen.open(context, sessions[i]),
              onRename: () => _rename(sessions[i]),
              onDuplicate: () => store.duplicate(sessions[i]),
              onDelete: () => _delete(sessions[i]),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', width: 96, height: 96),
            const SizedBox(height: 16),
            Text('No sessions yet', style: textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Create a session, then add your exercises.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

enum _SessionAction { rename, duplicate, delete }

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onTap,
    required this.onStart,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Session session;
  final VoidCallback onTap;
  final VoidCallback onStart;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final count = session.exercises.length;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        minVerticalPadding: 14,
        title: Text(session.name),
        subtitle: Text(count == 0
            ? 'No exercises'
            : '${count == 1 ? '1 exercise' : '$count exercises'} · '
                '${sessionDurationLabel(session)}'),
        onTap: onTap,
        leading: IconButton.filled(
          tooltip: 'Start',
          iconSize: 32,
          style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
          onPressed: count == 0 ? null : onStart,
          // Explicit color: ListTile's leading icon theme would win otherwise.
          icon: Icon(Icons.play_arrow,
              color: count == 0 ? null : Theme.of(context).colorScheme.onPrimary),
        ),
        trailing: PopupMenuButton<_SessionAction>(
          tooltip: 'More',
          onSelected: (a) => switch (a) {
            _SessionAction.rename => onRename(),
            _SessionAction.duplicate => onDuplicate(),
            _SessionAction.delete => onDelete(),
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: _SessionAction.rename, child: Text('Rename')),
            PopupMenuItem(
                value: _SessionAction.duplicate, child: Text('Duplicate')),
            PopupMenuItem(value: _SessionAction.delete, child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
