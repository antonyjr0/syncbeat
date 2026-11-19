import 'package:flutter/foundation.dart';

/// Only fixed phase codes and numeric counters belong in this log.
void zeppDiagnostic(String phase, {int? request}) {
  debugPrint(
    'SyncBeatZeppDiag wallMs=${DateTime.now().millisecondsSinceEpoch} '
    'layer=dart phase=$phase${request == null ? '' : ' request=$request'}',
  );
}
