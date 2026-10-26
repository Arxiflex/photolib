/// On-device ML, natively (ADR-0254, ADR-0278): models downloaded and checked,
/// and run in the data isolate on the device's photos.
library;

export 'src/faces_native.dart';
export 'src/ml_native.dart';
export 'src/models.dart';
export 'src/open_native.dart'
    show
        MlSetup,
        holdMl,
        reportInteraction,
        reportUploads,
        startFaces,
        startMl,
        startOcr,
        stopFaces,
        stopMl,
        stopOcr;
