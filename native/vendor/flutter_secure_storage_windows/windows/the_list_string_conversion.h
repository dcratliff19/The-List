#pragma once
#include <windows.h>
#include <string>
#include <stdexcept>
// Owned UTF-8/UTF-16 conversions using the Windows SDK, without ATL.
// Pairing identifiers are ASCII; UTF-8 also handles non-ASCII keys correctly.
class TheListWideString {
 std::wstring value_;
 public:
 explicit TheListWideString(const char* value) {
  if (!value) return;
  const int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, nullptr, 0);
  if (count == 0) throw std::runtime_error("Invalid UTF-8");
  value_.resize(count);
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value, -1, value_.data(), count);
 }
 wchar_t* data() { return value_.data(); }
 const wchar_t* data() const { return value_.c_str(); }
 operator wchar_t*() { return value_.data(); }
 operator const wchar_t*() const { return value_.c_str(); }
};
inline std::string TheListUtf8String(const wchar_t* value) {
 if (!value) return {};
 const int count = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, nullptr, 0, nullptr, nullptr);
 if (count == 0) throw std::runtime_error("Invalid UTF-16");
 std::string result(count, '\0');
 WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, result.data(), count, nullptr, nullptr);
 result.resize(count - 1);
 return result;
}
