import 'package:flutter/material.dart';

import 'app_state.dart';
import 'chat_view.dart';
import 'home_shell.dart';
import 'persona_lab_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import '../features/persona/pages/create_persona_page.dart';
import '../features/persona/pages/persona_detail_page.dart';
import '../features/persona/pages/persona_editor_page.dart';
import '../features/persona/pages/import_chat_page.dart';
import '../features/persona/pages/persona_list_page.dart';
import '../features/persona/pages/moments_page.dart';
import '../features/persona/pages/weekly_stories_page.dart';
import '../widgets/persona_import_sheet.dart' show PersonaImportPage;
import '../features/memory/pages/memory_list_page.dart';
import '../features/voice/pages/voice_chat_page.dart';
import '../features/voice/pages/voice_clone_page.dart';
import '../features/avatar/pages/video_call_page.dart';
import '../features/settings/pages/consent_page.dart';
import '../features/settings/pages/auth_page.dart';
import '../features/settings/pages/model_manage_page.dart';
import '../features/settings/pages/model_edit_page.dart';
import '../features/settings/pages/usage_page.dart';
import '../features/settings/pages/connectors_page.dart';
import '../features/settings/pages/automations_page.dart';
import '../features/auth/pages/welcome_page.dart';
import '../data/llm_provider.dart';

class AppRoutes {
  AppRoutes._();

  static const home = '/';
  static const personaList = '/personas';
  static const personaNew = '/persona/new';
  static const personaDetail = '/persona/detail';
  static const personaEdit = '/persona/edit';
  static const personaImport = '/persona/import';
  static const personaImportCard = '/persona/import-card';
  static const lab = '/lab';
  static const settings = '/settings';
  static const consent = '/settings/consent';
  static const auth = '/settings/auth';
  static const models = '/settings/models';
  static const usage = '/settings/usage';
  static const connectors = '/settings/connectors';
  static const automations = '/settings/automations';
  static const modelEdit = '/settings/model/edit';
  static const memory = '/memory';
  static const moments = '/moments';
  static const weeklyStories = '/weekly-stories';
  static const voiceChat = '/voice';
  static const voiceClone = '/voice/clone';
  static const videoCall = '/call';
  static const welcome = '/welcome';
}

Route<dynamic>? appRouter(RouteSettings settings) => onGenerateRoute(settings);

Route<dynamic>? onGenerateRoute(RouteSettings settings) {
  final name = settings.name ?? '';
  // 带 query 的路由（如 /voice/clone?persona=x）switch 精确匹配不到，
  // 在这里按前缀拦截解析。
  if (name.startsWith(AppRoutes.voiceClone)) {
    final uri = Uri.tryParse(name);
    final personaId = uri?.queryParameters['persona'];
    final create = uri?.queryParameters['create'] == '1';
    return MaterialPageRoute(
      builder: (_) => VoiceClonePage(
        targetPersonaId: personaId,
        createMode: create,
      ),
    );
  }
  switch (settings.name) {
    case AppRoutes.welcome:
      return MaterialPageRoute(builder: (_) => const WelcomePage());
    case AppRoutes.personaList:
      return MaterialPageRoute(builder: (_) => const PersonaListPage());
    case AppRoutes.personaNew:
      return MaterialPageRoute(builder: (_) => const CreatePersonaPage());
    case AppRoutes.personaDetail:
      return MaterialPageRoute(builder: (_) => const PersonaDetailPage());
    case AppRoutes.personaEdit:
      return MaterialPageRoute(builder: (_) => const PersonaEditorPage());
    case AppRoutes.personaImport:
      return MaterialPageRoute(
        builder: (_) => ImportChatPage(createMode: settings.arguments == 'create'),
      );
    case AppRoutes.personaImportCard:
      return MaterialPageRoute(builder: (_) => const PersonaImportPage());
    case AppRoutes.lab:
      return MaterialPageRoute(builder: (_) => const PersonaLabPage());
    case AppRoutes.settings:
      return MaterialPageRoute(builder: (_) => const SettingsPage());
    case AppRoutes.consent:
      return MaterialPageRoute(builder: (_) => const ConsentPage());
    case AppRoutes.auth:
      return MaterialPageRoute(
        builder: (_) => AuthPage(
          startWithRegister: settings.arguments == 'register',
        ),
      );
    case AppRoutes.models:
      return MaterialPageRoute(builder: (_) => const ModelManagePage());
    case AppRoutes.usage:
      return MaterialPageRoute(builder: (_) => const UsagePage());
    case AppRoutes.connectors:
      return MaterialPageRoute(builder: (_) => const ConnectorsPage());
    case AppRoutes.automations:
      return MaterialPageRoute(builder: (_) => const AutomationsPage());
    case AppRoutes.modelEdit:
      return MaterialPageRoute(
        builder: (_) => ModelEditPage(initial: settings.arguments as ModelConfig?),
      );
    case AppRoutes.memory:
      return MaterialPageRoute(builder: (_) => const MemoryListPage());
    case AppRoutes.moments:
      return MaterialPageRoute(builder: (_) => const MomentsPage());
    case AppRoutes.weeklyStories:
      return MaterialPageRoute(builder: (_) => const WeeklyStoriesPage());
    case AppRoutes.voiceChat:
      return MaterialPageRoute(builder: (_) => const VoiceChatPage());
    case AppRoutes.videoCall:
      return MaterialPageRoute(builder: (_) => const VideoCallPage());
    case AppRoutes.home:
    default:
      return MaterialPageRoute(builder: (_) => const HomeShell());
  }
}
