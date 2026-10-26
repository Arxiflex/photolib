#ifndef RUNNER_NATIVE_LOG_H_
#define RUNNER_NATIVE_LOG_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>

#include <string>

// Opens org.photolib/log for app/lib/core/logging.dart's listenToNativeLog (ADR-0115), on the platform thread.
void RegisterNativeLog(flutter::BinaryMessenger* messenger);

// Logs from any thread; [level] is debug, info, warning or error. Records wait, at most 1000, until the app asks with
// `listen`, which they answer; later ones go one at a time as `log` on the platform thread.
void NativeLog(const std::string& level, const std::string& logger, const std::string& message,
               flutter::EncodableMap fields = {});

#endif  // RUNNER_NATIVE_LOG_H_
