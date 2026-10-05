import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';

/// 模型选择器：模仿 ChatGPT 顶部那行「GPT-4o ▾」。
class ModelPickerButton extends StatelessWidget {
  const ModelPickerButton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    final model = state.activeModel;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(context, state),
        hoverColor: p.itemHover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                model.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 18, color: p.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, AppState state) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette(isDark: Theme.of(context).brightness == Brightness.dark).surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return _ModelPickerSheet(currentId: state.activeModelId, onPick: (id) {
          state.selectModel(id);
          Navigator.of(sheetContext).pop();
        });
      },
    );
  }
}

class _ModelPickerSheet extends StatelessWidget {
  final String currentId;
  final ValueChanged<String> onPick;
  const _ModelPickerSheet({required this.currentId, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = AppPalette(isDark: Theme.of(context).brightness == Brightness.dark);
    final state = AppStateScope.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Text(
                '选择人格版本',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
            ),
            for (final m in state.models) _modelTile(m, m.id == currentId, p, onPick),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _modelTile(ModelOption m, bool selected, AppPalette p, ValueChanged<String> onPick) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onPick(m.id),
          hoverColor: p.itemHover,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: p.brand.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.auto_awesome, size: 16, color: p.brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        m.description,
                        style: TextStyle(fontSize: 12, color: p.textSecondary, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 18,
                  color: selected ? p.brand : p.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
