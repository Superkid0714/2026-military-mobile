import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const inspectionAudioChannel = MethodChannel('maintenance/inspection_audio');

class InspectionAudioPlayback extends StatefulWidget {
  const InspectionAudioPlayback(this.path, {super.key});
  final String path;

  @override
  State<InspectionAudioPlayback> createState() =>
      _InspectionAudioPlaybackState();
}

class _InspectionAudioPlaybackState extends State<InspectionAudioPlayback> {
  bool played = false;

  Future<void> _command(String command) async {
    try {
      await inspectionAudioChannel.invokeMethod<void>(
        command,
        command == 'play' ? {'path': widget.path} : null,
      );
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('녹음 파일을 재생하지 못했습니다.')));
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이 기기에서는 녹음을 재생할 수 없습니다.')),
        );
      }
    }
  }

  @override
  void dispose() {
    if (played) _command('stopPlayback');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      TextButton.icon(
        onPressed: () {
          setState(() => played = true);
          _command('play');
        },
        icon: const Icon(Icons.play_arrow),
        label: const Text('녹음 듣기'),
      ),
      if (played)
        TextButton(
          onPressed: () {
            _command('stopPlayback');
            setState(() => played = false);
          },
          child: const Text('재생 중지'),
        ),
    ],
  );
}
