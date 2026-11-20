import 'package:material_ui/material_ui.dart';

import '../theme/memory_hues.dart';
import '../todoist/todoist_client.dart';
import '../todoist/todoist_settings.dart';
import '../todoist/unmatched_done_store.dart';

/// Todoist settings — API token + unmatched "done" items from · daily sync.
class TodoistSettingsShell extends StatefulWidget {
  const TodoistSettingsShell({
    super.key,
    required this.initial,
    required this.onSave,
    required this.unmatchedStore,
    this.onVerifyToken,
    this.onBack,
  });

  final TodoistSettings initial;
  final Future<void> Function(TodoistSettings settings) onSave;
  final UnmatchedDoneStore unmatchedStore;

  /// Live Todoist probe. Returns readable success/failure message.
  final Future<TodoistConnectionResult> Function(String apiToken)? onVerifyToken;
  final VoidCallback? onBack;

  @override
  State<TodoistSettingsShell> createState() => _TodoistSettingsShellState();
}

class _TodoistSettingsShellState extends State<TodoistSettingsShell> {
  late final TextEditingController _tokenController;
  bool _saving = false;
  bool _testing = false;
  bool _obscure = true;
  String? _status;
  bool _statusOk = false;
  List<UnmatchedDoneItem> _unmatched = const [];
  bool _loadingUnmatched = true;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.initial.apiToken);
    _loadUnmatched();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadUnmatched() async {
    final items = await widget.unmatchedStore.read();
    if (!mounted) return;
    setState(() {
      _unmatched = items;
      _loadingUnmatched = false;
    });
  }

  Future<TodoistConnectionResult?> _runVerify() async {
    final verify = widget.onVerifyToken;
    final token = _tokenController.text.trim();
    if (verify == null) return null;
    if (token.isEmpty) {
      return const TodoistConnectionResult(
        ok: false,
        message: 'Enter a Todoist API token first',
      );
    }
    setState(() {
      _testing = true;
      _status = 'Testing Todoist…';
      _statusOk = false;
    });
    try {
      final result = await verify(token);
      if (!mounted) return result;
      setState(() {
        _testing = false;
        _status = result.message;
        _statusOk = result.ok;
      });
      return result;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _testing = false;
        _status = 'Test failed: $e';
        _statusOk = false;
      });
      return TodoistConnectionResult(ok: false, message: '$e');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final next = TodoistSettings(apiToken: _tokenController.text.trim());
    try {
      await widget.onSave(next);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next.hasToken
                ? 'Todoist token saved — · daily syncs to Inbox'
                : 'Todoist token cleared',
          ),
          backgroundColor: MemoryHues.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $e'),
          backgroundColor: MemoryHues.danger,
        ),
      );
    }
  }

  Future<void> _dismissUnmatched(int index) async {
    await widget.unmatchedStore.removeAt(index);
    await _loadUnmatched();
  }

  Future<void> _clearUnmatched() async {
    await widget.unmatchedStore.clear();
    await _loadUnmatched();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      appBar: AppBar(
        title: const Text('Todoist'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _saving ? null : widget.onBack,
        ),
        actions: [
          TextButton(
            onPressed: _saving || _testing ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('API token', style: textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Personal REST API token from Todoist Settings → Integrations. '
            'Stored like Gemini / Mistral keys. · daily pages sync to Inbox.',
            style: textTheme.labelMedium?.copyWith(
              color: MemoryHues.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenController,
            enabled: !_saving,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: 'Todoist API token',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton(
                onPressed: _saving || _testing ? null : () async {
                  await _runVerify();
                },
                child: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Test Todoist'),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(
              _status!,
              style: textTheme.bodyMedium?.copyWith(
                color: _statusOk ? MemoryHues.accent : MemoryHues.danger,
              ),
            ),
          ],
          const SizedBox(height: 28),
          Text('Could not find in Todoist', style: textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Done items from · daily that did not match any open Inbox task. '
            'Check spelling or complete them manually in Todoist.',
            style: textTheme.labelMedium?.copyWith(
              color: MemoryHues.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingUnmatched)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_unmatched.isEmpty)
            Text(
              'No unmatched done items.',
              style: textTheme.bodyMedium?.copyWith(
                color: MemoryHues.inkMuted,
              ),
            )
          else ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _clearUnmatched,
                child: const Text('Clear all'),
              ),
            ),
            for (var i = 0; i < _unmatched.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: MemoryHues.paperElevated,
                child: ListTile(
                  title: Text(_unmatched[i].content),
                  subtitle: Text(
                    'Could not find this task in Todoist',
                    style: textTheme.labelMedium?.copyWith(
                      color: MemoryHues.danger,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Dismiss',
                    onPressed: () => _dismissUnmatched(i),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
