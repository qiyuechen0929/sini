import 'package:flutter/material.dart';

import '../../../app_state.dart';
import '../../../core/design/tokens.dart';
import '../../../core/widgets/sini_button.dart';
import '../../../core/widgets/sini_scaffold.dart';
import '../../../models.dart';
import '../../../theme.dart';

/// 自动化管理：TA 的定时任务列表（实时更新），支持新建 / 编辑 / 删除 / 开关。
class AutomationsPage extends StatelessWidget {
  const AutomationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    return SiniScaffold(
      title: '自动化',
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final tasks = state.automations.toList()
            ..sort((a, b) {
              if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
              return (a.nextRunAt ?? a.onceAt ?? DateTime(2000))
                  .compareTo(b.nextRunAt ?? b.onceAt ?? DateTime(2000));
            });
          final personaName = (String pid) =>
              state.personas.where((x) => x.id == pid).firstOrNull?.name ?? '已删除的人格';
          return ListView(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.md, Spacing.lg, Spacing.xxl),
            children: [
              Text('TA 会按你定的时间自动执行：到点寄邮件到绑定邮箱，'
                  '或在聊天里主动发消息。也可以直接在聊天里对 TA 说'
                  '「每天早上8点给我发封信」来创建。',
                  style: TextStyle(
                      fontSize: SiniText.bodySm, color: p.textSecondary)),
              const SizedBox(height: Spacing.lg),
              SiniButton(
                label: '新建自动化',
                leadingIcon: Icons.add_alarm_rounded,
                onTap: () => _showEditDialog(context, state, p),
                height: 46,
                expand: true,
              ),
              const SizedBox(height: Spacing.lg),
              if (tasks.isEmpty)
                Container(
                  padding: const EdgeInsets.all(Spacing.xl),
                  decoration: BoxDecoration(
                    color: p.itemHover,
                    borderRadius: BorderRadius.circular(Radii.xl),
                  ),
                  child: Column(children: [
                    Icon(Icons.auto_awesome_outlined,
                        size: 34, color: p.textTertiary),
                    const SizedBox(height: Spacing.sm),
                    Text('还没有自动化任务',
                        style: TextStyle(
                            fontSize: SiniText.bodySm, color: p.textTertiary)),
                    const SizedBox(height: 4),
                    Text('在聊天里对 TA 说一句，或点上面按钮手动创建',
                        style: TextStyle(
                            fontSize: SiniText.labelMd,
                            color: p.textTertiary.withValues(alpha: .7))),
                  ]),
                )
              else
                ...tasks.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TaskCard(
                          task: t,
                          personaName: personaName(t.personaId),
                          p: p,
                          state: state),
                    )),
            ],
          );
        },
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final AutomationTask task;
  final String personaName;
  final AppPalette p;
  final AppState state;
  const _TaskCard({
    required this.task,
    required this.personaName,
    required this.p,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: p.itemHover,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
            color: task.enabled
                ? const Color(0xFF10A37F).withValues(alpha: .35)
                : p.border,
            width: task.enabled ? 1 : 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
                task.action == 'email'
                    ? Icons.mail_outline_rounded
                    : Icons.chat_bubble_outline_rounded,
                size: 17,
                color: task.enabled
                    ? const Color(0xFF10A37F)
                    : p.textTertiary),
            const SizedBox(width: 7),
            Expanded(
              child: Text(task.name,
                  style: TextStyle(
                      fontSize: SiniText.bodyMd,
                      fontWeight: FontWeight.w600,
                      color: task.enabled
                          ? p.textPrimary
                          : p.textTertiary)),
            ),
            // 开关
            SizedBox(
              height: 28,
              child: Switch(
                  value: task.enabled,
                  onChanged: (v) => state.updateAutomation(
                      task.copyWith(enabled: v))),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            '${task.scheduleLabel()} · '
            '${task.action == "email" ? "寄邮件" : "发消息"} · '
            '由「$personaName」执行',
            style: TextStyle(fontSize: 11.5, color: p.textSecondary),
          ),
          if (task.prompt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(task.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: p.textTertiary, height: 1.4)),
          ],
          const SizedBox(height: 6),
          Row(children: [
            Text(
              task.lastRunAt != null
                  ? '上次执行 ${task.lastRunAt!.month}/${task.lastRunAt!.day}'
                  : '尚未执行',
              style: TextStyle(fontSize: 10.5, color: p.textTertiary),
            ),
            const Spacer(),
            TextButton(
                onPressed: () => _showEditDialog(context, state, p,
                    existing: task),
                child: Text('编辑',
                    style: TextStyle(fontSize: 12, color: p.brand))),
            TextButton(
                onPressed: () => showDialog<bool>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        backgroundColor: p.surface,
                        title: const Text('删除这个自动化？'),
                        content: Text('「${task.name}」将不再执行。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(dctx, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: const Text('删除')),
                        ],
                      ),
                    ).then((ok) {
                      if (ok == true) state.deleteAutomation(task.id);
                    }),
                child: Text('删除',
                    style: TextStyle(
                        fontSize: 12, color: const Color(0xFFB42318)))),
          ]),
        ],
      ),
    );
  }
}

/// 新建 / 编辑对话框
Future<void> _showEditDialog(
  BuildContext context,
  AppState state,
  AppPalette p, {
  AutomationTask? existing,
}) async {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final promptCtrl = TextEditingController(text: existing?.prompt ?? '');
  bool daily = existing?.daily ?? true;
  TimeOfDay time = TimeOfDay(
    hour: int.tryParse(existing?.timeHHmm.split(':').first ?? '') ?? 8,
    minute: int.tryParse(existing?.timeHHmm.split(':').last ?? '') ?? 0,
  );
  DateTime onceAt =
      existing?.onceAt ?? DateTime.now().add(const Duration(days: 1));
  String action = existing?.action ?? 'email';
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setDlg) => AlertDialog(
        backgroundColor: p.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(existing == null ? '新建自动化' : '编辑自动化',
            style: TextStyle(
                color: p.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(fontSize: 13.5, color: p.textPrimary),
                decoration: InputDecoration(
                  labelText: '名称',
                  labelStyle: TextStyle(fontSize: 12, color: p.textTertiary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 12),
              // 执行频率
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('每天')),
                  ButtonSegment(value: false, label: Text('单次')),
                ],
                selected: {daily},
                onSelectionChanged: (s) => setDlg(() => daily = s.first),
                showSelectedIcon: false,
              ),
              const SizedBox(height: 12),
              Row(children: [
                InkWell(
                  onTap: () async {
                    final t = await showTimePicker(
                        context: dctx, initialTime: time);
                    if (t != null) setDlg(() => time = t);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: p.itemHover,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: p.border, width: 1),
                    ),
                    child: Row(children: [
                      Icon(Icons.schedule_rounded,
                          size: 16, color: p.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                              fontSize: 13.5, color: p.textPrimary)),
                    ]),
                  ),
                ),
                if (!daily) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: dctx,
                        initialDate: onceAt,
                        firstDate: DateTime.now(),
                        lastDate:
                            DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) setDlg(() => onceAt = d);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: p.itemHover,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: p.border, width: 1),
                      ),
                      child: Row(children: [
                        Icon(Icons.event_rounded,
                            size: 16, color: p.textSecondary),
                        const SizedBox(width: 6),
                        Text('${onceAt.month}/${onceAt.day}',
                            style: TextStyle(
                                fontSize: 13.5, color: p.textPrimary)),
                      ]),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              Text('到点做什么',
                  style: TextStyle(fontSize: 12.5, color: p.textSecondary)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'email', label: Text('寄邮件')),
                  ButtonSegment(value: 'message', label: Text('发消息')),
                ],
                selected: {action},
                onSelectionChanged: (s) => setDlg(() => action = s.first),
                showSelectedIcon: false,
              ),
              if (action == 'email' && !state.emailConnectorReady)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('⚠️ 还未绑定邮箱，请先到「连接器」绑定',
                      style: TextStyle(
                          fontSize: 11, color: const Color(0xFFB42318))),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: promptCtrl,
                maxLines: 3,
                style: TextStyle(fontSize: 13, color: p.textPrimary),
                decoration: InputDecoration(
                  labelText: '执行指令（到点后 TA 按这个行事）',
                  labelStyle: TextStyle(fontSize: 12, color: p.textTertiary),
                  hintText: '例如：给用户写一封温暖的早安信，聊聊今天的心情',
                  hintStyle: TextStyle(fontSize: 12, color: p.textTertiary),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: Text('取消', style: TextStyle(color: p.textSecondary))),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('保存')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final timeStr =
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  final prompt = promptCtrl.text.trim();
  final name = nameCtrl.text.trim().isEmpty ? '自动化' : nameCtrl.text.trim();
  if (existing == null) {
    var task = AutomationTask(
      id: 'auto_${DateTime.now().microsecondsSinceEpoch}',
      personaId: state.activePersona?.id ?? '',
      name: name,
      daily: daily,
      timeHHmm: timeStr,
      onceAt: daily ? null : onceAt,
      action: action,
      prompt: prompt,
    );
    task = task.copyWith(nextRunAt: task.computeNextRun());
    await state.addAutomation(task);
  } else {
    var task = existing.copyWith(
      name: name,
      daily: daily,
      timeHHmm: timeStr,
      onceAt: onceAt,
      clearOnceAt: daily,
      action: action,
      prompt: prompt,
      nextRunAt: null,
    );
    task = task.copyWith(nextRunAt: task.computeNextRun());
    await state.updateAutomation(task);
  }
}
