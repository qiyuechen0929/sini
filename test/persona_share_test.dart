import 'package:flutter_test/flutter_test.dart';

import 'package:sini/models.dart';
import 'package:sini/utils/persona_share.dart';

void main() {
  test('隐私打码：手机号 / 身份证号被替换', () {
    expect(scrubPrivacy('我手机 13812345678，记得联系'),
        '我手机 [已隐去]，记得联系');
    expect(scrubPrivacy('身份证是110101199003074258别忘'),
        '身份证是[已隐去]别忘');
    expect(scrubPrivacy('普通文本不动'), '普通文本不动');
  });

  test('导出分享包：剔除称呼与声纹，保留养成数据', () {
    final p = Persona(
      id: 'p1',
      name: '小澄',
      gradientSeed: const [94, 114, 235, 56, 178, 180],
      subtitle: '温柔的发小',
      ownerName: '阿伟',
      relationship: '青梅竹马',
      description: '我的发小，手机 13812345678',
      memory: [
        PersonaMemory(
          id: 'm1',
          text: 'TA 的电话是 13812345678',
          kind: PersonaMemoryKind.fact,
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final pkg = exportPersonaPackage(p, messageCount: 1234);
    expect(pkg['kind'], kShareKind);
    expect(pkg['version'], kShareVersion);

    final stats = pkg['stats'] as Map<String, dynamic>;
    expect(stats['messageCount'], 1234);
    expect(stats['memoryCount'], 1);

    final pj = pkg['persona'] as Map<String, dynamic>;
    expect(pj.containsKey('ownerName'), isFalse); // 称呼剔除
    expect(pj.containsKey('voice'), isFalse); // 声纹剔除
    expect(pj['description'], isNot(contains('13812345678'))); // 描述打码
    final mem = (pj['memory'] as List).first as Map<String, dynamic>;
    expect(mem['text'], isNot(contains('13812345678'))); // 记忆打码
  });

  test('分享包可以编码 / 解析往返；格式不对返回 null', () {
    final pkg = exportPersonaPackage(
      Persona(
          id: 'p1',
          name: '小澄',
          subtitle: '',
          gradientSeed: const [94, 114, 235, 56, 178, 180]),
      messageCount: 0,
    );
    final round = tryParsePersonaPackage(encodePersonaPackage(pkg));
    expect(round, isNotNull);
    expect((round!['persona'] as Map)['name'], '小澄');

    expect(tryParsePersonaPackage('不是json'), isNull);
    expect(tryParsePersonaPackage('{"kind":"other"}'), isNull);
  });
}
