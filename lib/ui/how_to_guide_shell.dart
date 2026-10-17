import 'package:flutter/material.dart';

import '../theme/memory_hues.dart';

/// In-app how-to — one calm scroll through mark → shoot → confirm → vault.
class HowToGuideShell extends StatelessWidget {
  const HowToGuideShell({
    super.key,
    this.onBack,
  });

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: MemoryHues.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: onBack,
                  ),
                  const Spacer(),
                  Text(
                    'Guide',
                    style: textTheme.labelMedium?.copyWith(
                      color: MemoryHues.inkMuted,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HeroIntro(textTheme: textTheme),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _StepBlock(
                            index: '01',
                            title: 'Mark the page',
                            body:
                                'Draw one symbol in the meta zone — ∼ fleeting, '
                                '◇ permanent, J journal, △ mindmap, · daily. '
                                'On the camera, drag the glyph box over that ink '
                                '(no stickers). Chip △ forces the diagram path.',
                            accent: MemoryHues.ink,
                          ),
                          _StepBlock(
                            index: '02',
                            title: 'Shoot & confirm',
                            body:
                                'Gemini Flash classifies; text uses Mistral OCR, '
                                'maps use Gemini → .canvas. Type a required title '
                                '— that exact name is the filename (no date suffix). '
                                '△ labels edit in the list only, never on the photo.',
                            accent: MemoryHues.accent,
                          ),
                          _StepBlock(
                            index: '03',
                            title: 'Files appear',
                            body:
                                'Save writes only Obsidian-friendly files: '
                                '.md notes, .canvas mindmaps, and the page photo. '
                                'No companion JSON sidecars.',
                            accent: MemoryHues.recall,
                          ),
                          const SizedBox(height: 8),
                          _FolderMapBand(textTheme: textTheme),
                          const SizedBox(height: 20),
                          _FeatureBand(
                            title: 'Links in Obsidian',
                            body:
                                'hue-memory does not auto-suggest [[wikilinks]]. '
                                'Add connections yourself in Obsidian after save.',
                            glyph: '[[ ]]',
                          ),
                          _FeatureBand(
                            title: 'Hierarchical tags',
                            body:
                                'Mindmap branches become nested Obsidian tags. '
                                'A hub Psychology → Memory → Encoding lands as '
                                '#psychology/memory/encoding on the canvas tags '
                                'card so Graph and search stay tidy.',
                            glyph: '# /',
                          ),
                          _FeatureBand(
                            title: 'Promote ritual',
                            body:
                                'Weekly, open Promote from home. Rewrite a ∼ '
                                'fleeting note in your own words — the gate keeps '
                                'OCR shallow — then save as ◇ permanent with a '
                                'link back.',
                            glyph: '∼ → ◇',
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Paper first. Confirm second. Vault last.',
                            textAlign: TextAlign.center,
                            style: textTheme.titleLarge?.copyWith(
                              color: MemoryHues.inkMuted,
                              fontStyle: FontStyle.italic,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroIntro extends StatelessWidget {
  const _HeroIntro({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE8F0EE),
            MemoryHues.paperElevated,
            Color(0xFFF3EDE0),
          ],
        ),
        border: Border.all(color: MemoryHues.rule.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'hue-memory',
            style: textTheme.headlineLarge?.copyWith(
              fontSize: 34,
              height: 1.05,
              color: MemoryHues.ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Paper → confirm → Obsidian.',
            style: textTheme.titleLarge?.copyWith(
              color: MemoryHues.accent,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'A quiet loop for capturing what you already wrote by hand — '
            'then filing it where your second brain lives.',
            style: textTheme.bodyLarge?.copyWith(
              color: MemoryHues.inkMuted,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepBlock extends StatelessWidget {
  const _StepBlock({
    required this.index,
    required this.title,
    required this.body,
    required this.accent,
  });

  final String index;
  final String title;
  final String body;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              index,
              style: textTheme.labelMedium?.copyWith(
                color: accent,
                fontSize: 13,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.headlineMedium?.copyWith(
                  fontSize: 22,
                  height: 1.15,
                )),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: textTheme.bodyLarge?.copyWith(
                    color: MemoryHues.inkMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Concise Zettelkasten + GTD map for Mitch’s default pack.
class _FolderMapBand extends StatelessWidget {
  const _FolderMapBand({required this.textTheme});

  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE8F0EE),
            MemoryHues.paperElevated,
            Color(0xFFF3EDE0),
          ],
        ),
        border: Border.all(color: MemoryHues.rule.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your folders',
            style: textTheme.titleLarge?.copyWith(color: MemoryHues.ink),
          ),
          const SizedBox(height: 6),
          Text(
            'Default Zettelkasten ink + a GTD daily lane. Change any path in '
            'Settings → Vault folders (nested OK).',
            style: textTheme.bodyMedium?.copyWith(
              color: MemoryHues.inkMuted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          _FolderRow(glyph: '○', name: 'inbox', role: 'Quick catch — sort later'),
          _FolderRow(glyph: '∼', name: 'fleeting', role: 'Rough notes → promote weekly'),
          _FolderRow(glyph: '≡', name: 'literature', role: 'Source / book captures'),
          _FolderRow(glyph: '◇', name: 'permanent', role: 'Own-words lasting notes'),
          _FolderRow(glyph: '△', name: 'mindmaps', role: 'Diagram → .canvas + photo'),
          _FolderRow(glyph: 'J', name: 'journal', role: 'Journal entries (OCR → .md)'),
          _FolderRow(
            glyph: '·',
            name: 'Organising/Daily',
            role: 'GTD tasks appended to today’s note',
          ),
        ],
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.glyph,
    required this.name,
    required this.role,
  });

  final String glyph;
  final String name;
  final String role;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              glyph,
              style: textTheme.titleMedium?.copyWith(color: MemoryHues.accent),
            ),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: textTheme.bodyMedium?.copyWith(
                  color: MemoryHues.ink,
                  height: 1.35,
                ),
                children: [
                  TextSpan(
                    text: name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: ' — $role',
                    style: TextStyle(color: MemoryHues.inkMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureBand extends StatelessWidget {
  const _FeatureBand({
    required this.title,
    required this.body,
    required this.glyph,
  });

  final String title;
  final String body;
  final String glyph;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: MemoryHues.accent.withValues(alpha: 0.45), width: 3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(title, style: textTheme.titleLarge),
                  ),
                  Text(
                    glyph,
                    style: textTheme.labelMedium?.copyWith(
                      color: MemoryHues.accent,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                body,
                style: textTheme.bodyMedium?.copyWith(
                  color: MemoryHues.inkMuted,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
