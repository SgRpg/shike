import 'package:flutter/material.dart';

import '../refined/design.dart';

/// The story behind Shike, shared by its two creators.
class OurStoryAboutPage extends StatelessWidget {
  const OurStoryAboutPage({super.key});

  static const version = String.fromEnvironment(
    'SHIKE_APP_VERSION',
    defaultValue: '1.0.1',
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const PaperHeader('关于拾刻'),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(30, 28, 30, 30),
        children: [
          const Text(
            '拾刻的开发包含了我和我的女朋友冉傲涵的共同努力。这个 APP 作为我们一起走过四个月的象征，此后也将见证我们未来更多的岁月。',
            style: TextStyle(fontSize: 17, height: 1.7, color: Paper.ink),
          ),
          const SizedBox(height: 22),
          const Text(
            '起初萌生开发拾刻的想法，是因为有时我无法在她的身边，就想到了要开发一个能让她记录想法和情绪的 APP。',
            style: TextStyle(fontSize: 17, height: 1.7, color: Paper.ink),
          ),
          const SizedBox(height: 22),
          const Text(
            '希望我能任何时刻都陪伴着她，感受她的感受。',
            style: TextStyle(fontSize: 17, height: 1.7, color: Paper.ink),
          ),
          const SizedBox(height: 28),
          Text(
            '这就是拾刻的意义',
            textAlign: TextAlign.center,
            style: Paper.title(18).copyWith(
              color: Paper.secondary,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 40),
          const Text(
            '版本 $version',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.5, color: Paper.faint),
          ),
        ],
      ),
    ),
  );
}
