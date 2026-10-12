import 'dart:io';

/// Regenerates icon assets while retaining the existing Xcode configuration.
/// flutter_launcher_icons 0.14.4 also rewrites unrelated ASSETCATALOG settings.
Future<void> main() async {
  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  final originalProject = await project.readAsBytes();
  try {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'flutter_launcher_icons'],
    );
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    exitCode = result.exitCode;
  } finally {
    await project.writeAsBytes(originalProject);
  }
}
