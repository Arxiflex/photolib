// Thumbnails of files for app/lib/features/library/timeline/platform_thumbnails.dart (design 10 §3.4, T4,
// ADR-0107): the shell's thumbnail handlers (IShellItemImageFactory: its thumbnail cache, WIC's codecs and Media
// Foundation's poster frames of videos), else WIC decoding the file, upright. Decodes run on the system thread pool,
// never the platform or raster thread, and answer on the platform thread with width, height and premultiplied RGBA
// whose short side is at the tier, never larger than the source. A file neither reads is refused, which the Dart
// side passes to libvips.
#include "thumbnail_channel.h"

#include "native_log.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <shlwapi.h>
#include <shobjidl.h>
#include <wincodec.h>
#include <windows.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace {

using Microsoft::WRL::ComPtr;
using flutter::EncodableList;
using flutter::EncodableValue;
using Result = std::shared_ptr<flutter::MethodResult<EncodableValue>>;

constexpr UINT kAnswer = WM_APP + 1;
constexpr UINT64 kMaxPixels = 300000000;  // design 08 §8.2

struct Rgba {
  int width, height;
  std::vector<uint8_t> pixels;
};

std::mutex lock;
std::set<int64_t> live;  // requests in flight, which a cancel removes
std::vector<std::function<void()>> answers;
HWND window = nullptr;  // a message-only window on the platform thread
std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;

// Runs on the platform thread, from its message loop.
void Answer(std::function<void()> answer) {
  {
    std::lock_guard<std::mutex> guard(lock);
    answers.push_back(std::move(answer));
  }
  PostMessage(window, kAnswer, 0, 0);
}

LRESULT CALLBACK Proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  if (message != kAnswer) return DefWindowProc(hwnd, message, wparam, lparam);
  std::vector<std::function<void()>> ready;
  {
    std::lock_guard<std::mutex> guard(lock);
    ready.swap(answers);
  }
  for (auto& answer : ready) answer();
  return 0;
}

// [source], upright by [transform], scaled so that its short side is the tier and copied out as premultiplied RGBA;
// [hr] says why not.
std::optional<Rgba> Pixels(IWICImagingFactory* wic, IWICBitmapSource* source, int tier, HRESULT& hr,
                           WICBitmapTransformOptions transform = WICBitmapTransformRotate0) {
  UINT w = 0, h = 0;
  if (FAILED(hr = source->GetSize(&w, &h))) return std::nullopt;
  if (w == 0 || h == 0 || UINT64(w) * h > kMaxPixels) {
    hr = WINCODEC_ERR_IMAGESIZEOUTOFRANGE;
    return std::nullopt;
  }
  const double scale = std::min(1.0, double(tier) / std::min(w, h));
  const UINT sw = std::max(1u, UINT(std::lround(w * scale))), sh = std::max(1u, UINT(std::lround(h * scale)));
  ComPtr<IWICBitmapScaler> scaler;
  ComPtr<IWICBitmapFlipRotator> rotator;
  ComPtr<IWICFormatConverter> converter;
  if (FAILED(hr = wic->CreateBitmapScaler(&scaler)) ||
      FAILED(hr = scaler->Initialize(source, sw, sh, WICBitmapInterpolationModeFant)) ||
      FAILED(hr = wic->CreateBitmapFlipRotator(&rotator)) ||
      FAILED(hr = rotator->Initialize(scaler.Get(), transform)) ||
      FAILED(hr = wic->CreateFormatConverter(&converter)) ||
      FAILED(hr = converter->Initialize(rotator.Get(), GUID_WICPixelFormat32bppPRGBA, WICBitmapDitherTypeNone,
                                        nullptr, 0, WICBitmapPaletteTypeCustom))) {
    return std::nullopt;
  }
  UINT ow = 0, oh = 0;
  converter->GetSize(&ow, &oh);
  Rgba out{int(ow), int(oh), std::vector<uint8_t>(size_t(ow) * oh * 4)};
  if (FAILED(hr = converter->CopyPixels(nullptr, ow * 4, UINT(out.pixels.size()), out.pixels.data()))) {
    return std::nullopt;
  }
  return out;
}

// The shell's thumbnail, of a still or a video, up to twice the tier on its long side.
std::optional<Rgba> Shell(IWICImagingFactory* wic, const std::wstring& path, int tier, HRESULT& hr) {
  ComPtr<IShellItemImageFactory> factory;
  HBITMAP bitmap = nullptr;
  if (FAILED(hr = SHCreateItemFromParsingName(path.c_str(), nullptr, IID_PPV_ARGS(&factory))) ||
      FAILED(hr = factory->GetImage(SIZE{2 * tier, 2 * tier}, SIIGBF_THUMBNAILONLY | SIIGBF_BIGGERSIZEOK, &bitmap))) {
    return std::nullopt;
  }
  ComPtr<IWICBitmap> source;
  const bool made =
      SUCCEEDED(hr = wic->CreateBitmapFromHBITMAP(bitmap, nullptr, WICBitmapUsePremultipliedAlpha, &source));
  DeleteObject(bitmap);
  return made ? Pixels(wic, source.Get(), tier, hr) : std::nullopt;
}

// WIC's decode of the file's first frame, turned by its EXIF orientation.
std::optional<Rgba> Decode(IWICImagingFactory* wic, const std::wstring& path, int tier, HRESULT& hr) {
  ComPtr<IWICBitmapDecoder> decoder;
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(hr = wic->CreateDecoderFromFilename(path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand,
                                                 &decoder)) ||
      FAILED(hr = decoder->GetFrame(0, &frame))) {
    return std::nullopt;
  }
  auto transform = WICBitmapTransformRotate0;
  ComPtr<IWICMetadataQueryReader> metadata;
  PROPVARIANT orientation;
  PropVariantInit(&orientation);
  if (SUCCEEDED(frame->GetMetadataQueryReader(&metadata)) &&
      SUCCEEDED(metadata->GetMetadataByName(L"System.Photo.Orientation", &orientation)) &&
      orientation.vt == VT_UI2) {
    switch (orientation.uiVal) {
      case 2: transform = WICBitmapTransformFlipHorizontal; break;
      case 3: transform = WICBitmapTransformRotate180; break;
      case 4: transform = WICBitmapTransformFlipVertical; break;
      case 5: transform = WICBitmapTransformOptions(WICBitmapTransformRotate90 | WICBitmapTransformFlipHorizontal);
        break;
      case 6: transform = WICBitmapTransformRotate90; break;
      case 7: transform = WICBitmapTransformOptions(WICBitmapTransformRotate270 | WICBitmapTransformFlipHorizontal);
        break;
      case 8: transform = WICBitmapTransformRotate270; break;
    }
  }
  PropVariantClear(&orientation);
  return Pixels(wic, frame.Get(), tier, hr, transform);
}

std::string Hex(HRESULT hr) {
  char text[11];
  std::snprintf(text, sizeof text, "0x%08lX", static_cast<unsigned long>(hr));
  return text;
}

struct Request {
  std::wstring path;
  std::string name;
  int tier;
  int64_t id;
  Result result;
};

VOID CALLBACK Work(PTP_CALLBACK_INSTANCE, PVOID context) {
  std::unique_ptr<Request> request(static_cast<Request*>(context));
  std::optional<Rgba> rgba;
  bool wanted;
  {
    std::lock_guard<std::mutex> guard(lock);
    wanted = live.count(request->id) > 0;
  }
  HRESULT shell = S_OK, decode = S_OK;
  if (wanted && SUCCEEDED(shell = decode = CoInitializeEx(nullptr, COINIT_MULTITHREADED))) {
    ComPtr<IWICImagingFactory> wic;
    if (SUCCEEDED(shell = decode = CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
                                                    IID_PPV_ARGS(&wic)))) {
      rgba = Shell(wic.Get(), request->path, request->tier, shell);
      if (!rgba) rgba = Decode(wic.Get(), request->path, request->tier, decode);
    }
    CoUninitialize();
  }
  if (wanted && !rgba) {
    NativeLog("warning", "thumbnails", "no decoder reads it",
              {{EncodableValue("file"), EncodableValue(request->name)},
               {EncodableValue("shell"), EncodableValue(Hex(shell))},
               {EncodableValue("wic"), EncodableValue(Hex(decode))}});
  }
  Result result = request->result;
  const int64_t id = request->id;
  const std::string name = request->name;
  Answer([result, id, name, wanted, rgba = std::move(rgba)]() mutable {
    {
      std::lock_guard<std::mutex> guard(lock);
      live.erase(id);
    }
    if (!wanted) return result->Error("cancelled", name);
    if (!rgba) return result->Error("refused", name + ": no decoder reads it");
    result->Success(EncodableValue(
        EncodableList{EncodableValue(rgba->width), EncodableValue(rgba->height), EncodableValue(rgba->pixels)}));
  });
}

std::wstring Path(const std::string& uri) {
  // file:///C:/a%20b.jpg → C:\a b.jpg
  wchar_t path[MAX_PATH * 4];
  DWORD length = ARRAYSIZE(path);
  const int wide = MultiByteToWideChar(CP_UTF8, 0, uri.c_str(), -1, nullptr, 0);
  std::wstring url(wide, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, uri.c_str(), -1, url.data(), wide);
  return SUCCEEDED(PathCreateFromUrlW(url.c_str(), path, &length, 0)) ? std::wstring(path) : std::wstring();
}

}  // namespace

void RegisterThumbnailChannel(flutter::BinaryMessenger* messenger) {
  WNDCLASS type{};
  type.lpfnWndProc = Proc;
  type.hInstance = GetModuleHandle(nullptr);
  type.lpszClassName = L"PhotolibThumbnails";
  RegisterClass(&type);
  window = CreateWindowEx(0, type.lpszClassName, L"", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, type.hInstance, nullptr);
  channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "org.photolib/thumbnails", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<EncodableValue>& call, std::unique_ptr<flutter::MethodResult<EncodableValue>> reply) {
        Result result(std::move(reply));
        if (call.method_name() == "cancel") {
          std::lock_guard<std::mutex> guard(lock);
          live.erase(call.arguments()->LongValue());
          return result->Success();
        }
        if (call.method_name() != "load") return result->NotImplemented();
        const auto& args = std::get<EncodableList>(*call.arguments());
        const auto& uri = std::get<std::string>(args[0]);
        auto request = std::make_unique<Request>(
            Request{Path(uri), uri.substr(uri.find_last_of('/') + 1), std::get<int32_t>(args[1]), args[2].LongValue(),
                    result});
        if (uri.rfind("file:", 0) != 0 || request->path.empty()) return result->Error("unreadable-url", uri);
        {
          std::lock_guard<std::mutex> guard(lock);
          live.insert(request->id);
        }
        if (TrySubmitThreadpoolCallback(Work, request.get(), nullptr)) {
          request.release();
        } else {
          std::lock_guard<std::mutex> guard(lock);
          live.erase(request->id);
          result->Error("busy", "the thread pool refused the decode");
        }
      });
}
