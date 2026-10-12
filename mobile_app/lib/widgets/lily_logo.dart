import 'package:flutter/material.dart';

class LilyLogo extends StatelessWidget {
  const LilyLogo({super.key});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset('assets/branding/lily_cloud.png',
                width: 40,
                height: 40,
                semanticLabel: 'Lily smiling cloud',
                fit: BoxFit.cover)),
        const SizedBox(width: 10),
        const Text('Lily',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .5)),
      ]);
}
