#ifndef RUNNER_BIOMETRIC_CHANNEL_H_
#define RUNNER_BIOMETRIC_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

// The "tildeck/biometric" method channel: Windows Hello keys through
// KeyCredentialManager, one key per vault (see docs/security-model.md,
// "Biometric unlock").
//
// The Hello calls are asynchronous and show modal UI, so they run on a worker
// thread. Their results are posted back to |window| as kResultMessage and
// delivered to Flutter on the platform thread by HandleWindowMessage.
class BiometricChannel {
 public:
  // The window message that carries a finished call back to the platform
  // thread. Its LPARAM owns a heap-allocated std::function<void()>.
  static constexpr UINT kResultMessage = WM_APP + 1;

  BiometricChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~BiometricChannel();

  BiometricChannel(const BiometricChannel&) = delete;
  BiometricChannel& operator=(const BiometricChannel&) = delete;

  // Runs a posted result. Returns true when |message| was kResultMessage.
  static bool HandleWindowMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_BIOMETRIC_CHANNEL_H_
