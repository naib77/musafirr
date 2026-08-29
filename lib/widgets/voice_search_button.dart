import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../services/voice/speech_service.dart';

/// The microphone that opens voice search, sized to sit inside the search
/// pill without crowding the label.
///
/// Renders nothing where speech recognition could never work — Firefox and
/// Edge ship no Web Speech API, and iOS has no Bengali locale. Hiding it there
/// is deliberate: a mic button that cannot listen is worse than no mic button,
/// and the check is a free property lookup rather than a permission prompt, so
/// it is safe to call during build.
class VoiceSearchMicButton extends StatelessWidget {
  const VoiceSearchMicButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!VoiceSpeechService.current.maybeAvailable) {
      return const SizedBox.shrink();
    }

    return Semantics(
      button: true,
      label: 'Search by voice',
      hint: 'Say a place and the kind of stay you want',
      child: Tooltip(
        message: 'Voice search',
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            // 40x44 fills the pill's height, which is the axis a thumb
            // actually misses on.
            child: SizedBox(
              width: 40,
              height: 44,
              child: Icon(
                Icons.mic_rounded,
                size: 21,
                color: AppColors.brand,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
