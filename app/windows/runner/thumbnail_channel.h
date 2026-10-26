#ifndef RUNNER_THUMBNAIL_CHANNEL_H_
#define RUNNER_THUMBNAIL_CHANNEL_H_

#include <flutter/binary_messenger.h>

// Answers org.photolib/thumbnails for the desktop pipeline (see the .cpp).
void RegisterThumbnailChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_THUMBNAIL_CHANNEL_H_
