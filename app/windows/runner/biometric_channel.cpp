#include "biometric_channel.h"

#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Security.Credentials.h>
#include <winrt/Windows.Security.Cryptography.h>
#include <winrt/Windows.Storage.Streams.h>

#include <windows.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>
#include <functional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

// Window ownership of the Hello dialog: the Windows SDK has no
// KeyCredentialManager interop header (only UserConsentVerifierInterop.h,
// which cannot create or use keys). The WindowId overloads
// (RequestCreateForWindowAsync, RequestSignForWindowAsync) need
// UniversalApiContract 19 (Windows 11 24H2) and would have to be gated with
// ApiInformation, so for now this uses the plain KeyCredentialManager calls,
// which work on every Windows 10 and 11 with Hello.

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;
using winrt::Windows::Security::Credentials::KeyCredential;
using winrt::Windows::Security::Credentials::KeyCredentialCreationOption;
using winrt::Windows::Security::Credentials::KeyCredentialManager;
using winrt::Windows::Security::Credentials::KeyCredentialStatus;
using winrt::Windows::Security::Cryptography::CryptographicBuffer;

using Result = flutter::MethodResult<EncodableValue>;

constexpr char kChannelName[] = "tildeck/biometric";
constexpr char kKeyPrefix[] = "tildeck-";

// What a call finished with, built on the worker thread and delivered to
// Flutter on the platform thread.
struct Outcome {
  bool ok = false;
  EncodableValue value;
  std::string code;
  std::string message;
};

Outcome Success(EncodableValue value) {
  Outcome outcome;
  outcome.ok = true;
  outcome.value = std::move(value);
  return outcome;
}

Outcome Error(std::string code, std::string message) {
  Outcome outcome;
  outcome.code = std::move(code);
  outcome.message = std::move(message);
  return outcome;
}

// Maps a Hello status that is not Success to the channel's error codes.
// |missing_code| is what NotFound means for this call.
Outcome FromStatus(KeyCredentialStatus status, const char* missing_code) {
  switch (status) {
    case KeyCredentialStatus::UserCanceled:
    case KeyCredentialStatus::UserPrefersPassword:
      return Error("cancelled", "The Windows Hello prompt was cancelled.");
    case KeyCredentialStatus::NotFound:
      return Error(missing_code, "The Windows Hello key was not found.");
    case KeyCredentialStatus::SecurityDeviceLocked:
      return Error("unavailable", "The Windows Hello security device is locked.");
    default:
      return Error("failed", "Windows Hello returned status " +
                                 std::to_string(static_cast<int>(status)) +
                                 ".");
  }
}

// The plain KeyCredentialManager calls open the Hello dialog without an
// owner window, so it can come up behind the app. While a request is open,
// this finds the dialog's window and brings it to the front; it stops when
// the request ends, or after a while.
class HelloToFront {
 public:
  HelloToFront() : done_(std::make_shared<std::atomic<bool>>(false)) {
    // The app is in the foreground (the user just asked): let the dialog's
    // process take it.
    AllowSetForegroundWindow(ASFW_ANY);
    std::thread([done = done_] {
      for (int i = 0; i < 100 && !done->load(); ++i) {
        HWND dialog = FindWindowW(L"Credential Dialog Xaml Host", nullptr);
        if (dialog != nullptr) {
          SetForegroundWindow(dialog);
          BringWindowToTop(dialog);
          return;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
      }
    }).detach();
  }
  ~HelloToFront() { done_->store(true); }
  HelloToFront(const HelloToFront&) = delete;
  HelloToFront& operator=(const HelloToFront&) = delete;

 private:
  std::shared_ptr<std::atomic<bool>> done_;
};

winrt::hstring KeyName(const std::string& vault_id) {
  return winrt::to_hstring(kKeyPrefix + vault_id);
}

bool IsSupported() {
  return KeyCredentialManager::IsSupportedAsync().get();
}

Outcome Unsupported() {
  return Error("unavailable", "Windows Hello is not set up on this device.");
}

// Signs |challenge| with |credential|; Hello asks the user to verify first.
Outcome Sign(const KeyCredential& credential,
             const std::vector<uint8_t>& challenge,
             const char* missing_code) {
  auto data = CryptographicBuffer::CreateFromByteArray(
      winrt::array_view<const uint8_t>(challenge.data(),
                                       challenge.data() + challenge.size()));
  HelloToFront to_front;
  auto signed_result = credential.RequestSignAsync(data).get();
  if (signed_result.Status() != KeyCredentialStatus::Success) {
    return FromStatus(signed_result.Status(), missing_code);
  }
  winrt::com_array<uint8_t> bytes;
  CryptographicBuffer::CopyToByteArray(signed_result.Result(), bytes);
  return Success(EncodableValue(std::vector<uint8_t>(bytes.begin(), bytes.end())));
}

Outcome Enroll(const std::string& vault_id,
               const std::vector<uint8_t>& challenge) {
  if (!IsSupported()) {
    return Unsupported();
  }
  HelloToFront to_front;
  auto created = KeyCredentialManager::RequestCreateAsync(
                     KeyName(vault_id),
                     KeyCredentialCreationOption::ReplaceExisting)
                     .get();
  if (created.Status() != KeyCredentialStatus::Success) {
    // NotFound while creating means there is no Hello to create a key with.
    return FromStatus(created.Status(), "unavailable");
  }
  return Sign(created.Credential(), challenge, "failed");
}

Outcome Obtain(const std::string& vault_id,
               const std::vector<uint8_t>& challenge) {
  if (!IsSupported()) {
    return Unsupported();
  }
  auto opened = KeyCredentialManager::OpenAsync(KeyName(vault_id)).get();
  if (opened.Status() != KeyCredentialStatus::Success) {
    return FromStatus(opened.Status(), "not_found");
  }
  return Sign(opened.Credential(), challenge, "not_found");
}

Outcome Remove(const std::string& vault_id) {
  try {
    KeyCredentialManager::DeleteAsync(KeyName(vault_id)).get();
    return Success(EncodableValue());
  } catch (const winrt::hresult_error& error) {
    const HRESULT code = error.code();
    if (code == NTE_NO_KEY || code == HRESULT_FROM_WIN32(ERROR_NOT_FOUND)) {
      return Success(EncodableValue());
    }
    // Some other failure: it is still a success if there is no key left.
    auto opened = KeyCredentialManager::OpenAsync(KeyName(vault_id)).get();
    if (opened.Status() == KeyCredentialStatus::NotFound) {
      return Success(EncodableValue());
    }
    return Error("failed", winrt::to_string(error.message()));
  }
}

// Runs |work| on a new thread in the multithreaded apartment, where blocking
// on WinRT async operations is allowed, and posts its outcome to |window|.
void RunOffPlatformThread(HWND window,
                          std::shared_ptr<Result> result,
                          std::function<Outcome()> work) {
  std::thread([window, result = std::move(result),
               work = std::move(work)]() mutable {
    Outcome outcome;
    {
      winrt::init_apartment(winrt::apartment_type::multi_threaded);
      try {
        outcome = work();
      } catch (const winrt::hresult_error& error) {
        outcome = Error("failed", winrt::to_string(error.message()));
      } catch (...) {
        outcome = Error("failed", "Windows Hello failed unexpectedly.");
      }
      winrt::uninit_apartment();
    }
    auto* deliver = new std::function<void()>(
        [result = std::move(result), outcome = std::move(outcome)]() {
          if (outcome.ok) {
            result->Success(outcome.value);
          } else {
            result->Error(outcome.code, outcome.message);
          }
        });
    if (!::PostMessage(window, BiometricChannel::kResultMessage, 0,
                       reinterpret_cast<LPARAM>(deliver))) {
      // The window is gone, and the engine with it. The closure is leaked on
      // purpose: destroying an unanswered result would reply through the
      // engine from this thread.
    }
  }).detach();
}

const std::string* GetString(const EncodableMap& args, const char* key) {
  auto it = args.find(EncodableValue(key));
  return it == args.end() ? nullptr : std::get_if<std::string>(&it->second);
}

const std::vector<uint8_t>* GetBytes(const EncodableMap& args,
                                     const char* key) {
  auto it = args.find(EncodableValue(key));
  return it == args.end() ? nullptr
                          : std::get_if<std::vector<uint8_t>>(&it->second);
}

}  // namespace

BiometricChannel::BiometricChannel(flutter::BinaryMessenger* messenger,
                                   HWND window)
    : window_(window),
      channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}

BiometricChannel::~BiometricChannel() {
  channel_->SetMethodCallHandler(nullptr);
}

bool BiometricChannel::HandleWindowMessage(UINT message, WPARAM wparam,
                                           LPARAM lparam) {
  if (message != kResultMessage) {
    return false;
  }
  std::unique_ptr<std::function<void()>> deliver(
      reinterpret_cast<std::function<void()>*>(lparam));
  (*deliver)();
  return true;
}

void BiometricChannel::HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<Result> result) {
  const std::string& method = call.method_name();
  std::shared_ptr<Result> shared(std::move(result));

  if (method == "support") {
    RunOffPlatformThread(window_, shared, []() {
      return Success(EncodableValue(IsSupported() ? "available" : "none"));
    });
    return;
  }

  if (method != "enroll" && method != "obtain" && method != "remove") {
    shared->NotImplemented();
    return;
  }

  const auto* args = std::get_if<EncodableMap>(call.arguments());
  const std::string* vault_id = args ? GetString(*args, "vaultId") : nullptr;
  if (!vault_id || vault_id->empty()) {
    shared->Error("failed", "Missing vaultId.");
    return;
  }

  if (method == "remove") {
    RunOffPlatformThread(window_, shared,
                         [id = *vault_id]() { return Remove(id); });
    return;
  }

  const std::vector<uint8_t>* challenge = GetBytes(*args, "challenge");
  if (!challenge || challenge->empty()) {
    shared->Error("failed", "Missing challenge.");
    return;
  }
  if (method == "enroll") {
    RunOffPlatformThread(
        window_, shared,
        [id = *vault_id, data = *challenge]() { return Enroll(id, data); });
  } else {
    RunOffPlatformThread(
        window_, shared,
        [id = *vault_id, data = *challenge]() { return Obtain(id, data); });
  }
}
