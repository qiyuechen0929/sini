import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../app_state.dart';
import '../../../theme.dart';
import '../../../utils/weekly_story.dart' show WeeklyStory;

/// 每周故事：按周翻阅「这一周我们的故事」
class WeeklyStoriesPage extends StatefulWidget {
  const WeeklyStoriesPage({super.key});

  @override
  State<WeeklyStoriesPage> createState() => _WeeklyStoriesPageState();
}

class _WeeklyStoriesPageState extends State<WeeklyStoriesPage> {
  bool _busy = false;

  Future<void> _generate() async {
    setState(() => _busy = true);
    final ok = await AppStateScope.read(context).generateWeeklyStoryNow();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '本周故事已生成 ✨' : '生成失败：没有可用模型，或本周素材还不够'),
        duration: const Duration(seconds: 2200),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    final persona = state.activePersona;
    if (persona == null) {
      return SiniScaffold(
        title: '每周故事',
        body: Center(
          child: Text('请先选择一个人物', style: TextStyle(color: p.textTertiary)),
        ),
      );
    }
    final stories = state.storiesOf(persona.id);

    return SiniScaffold(
      title: '每周故事',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '每周日晚 18 点后会自动生成；也可以点这里手动写一篇。',
                    style: TextStyle(fontSize: 12.5, color: p.textSecondary, height: 1.5),
                  ),
                ),
                const SizedBox(width: 10),
                SiniButton(
                  label: _busy ? '写作中…' : '写本周',
                  onTap: _busy ? null : _generate,
                  height: 40,
                  expand: false,
                ),
              ],
            ),
          ),
          Expanded(
            child: stories.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Text(
                        '还没有故事\n和 TA 聊聊这一周发生的事，\n周日晚或点「写本周」生成',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13.5, color: p.textTertiary, height: 1.7),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                    itemCount: stories.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final s = stories[i];
                      return _StoryCard(story: s, p: p);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  final WeeklyStory story;
  final AppPalette p;
  const _StoryCard({required this.story, required this.p});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.brand.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: p.brand.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            p.isDark ? const Color(0xFF0F1630) : p.surface,
            p.isDark ? const Color(0xFF151C36) : p.itemHover,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_note_rounded, size: 16, color: p.brand),
              const SizedBox(width: 6),
              Text(
                story.title,
                style: TextStyle(fontSize: 12.5, color: p.brand, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            story.body,
            style: TextStyle(fontSize: 14.5, height: 1.8, color: p.textPrimary),
          ),
          const SizedBox(height: 10),
          Text(
            '${story.createdAt.month}/${story.createdAt.day} 写下',
            style: TextStyle(fontSize: 11, color: p.textTertiary),
          ),
        ],
      ),
    );
  }
}
