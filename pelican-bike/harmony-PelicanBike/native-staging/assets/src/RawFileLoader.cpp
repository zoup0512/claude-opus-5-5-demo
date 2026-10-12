#include "pelican/assets/RawFileLoader.h"

#if defined(__OHOS__)
#include <rawfile/raw_file.h>

#include <algorithm>
#include <cstdint>
#include <limits>

namespace pelican::assets {

bool ReadRawFile(
    NativeResourceManager* manager,
    const char* name,
    std::vector<std::uint8_t>& bytes,
    std::string* error) {
    if (error != nullptr) error->clear();
    bytes.clear();
    if (manager == nullptr || name == nullptr || name[0] == '\0') {
        if (error != nullptr) *error = "ReadRawFile requires a resource manager and non-empty name";
        return false;
    }
    RawFile64* raw = OH_ResourceManager_OpenRawFile64(manager, name);
    if (raw == nullptr) {
        if (error != nullptr) *error = std::string("OH_ResourceManager_OpenRawFile64 failed: ") + name;
        return false;
    }
    const std::int64_t size = OH_ResourceManager_GetRawFileSize64(raw);
    if (size <= 0 || static_cast<std::uint64_t>(size) > std::numeric_limits<std::size_t>::max()) {
        OH_ResourceManager_CloseRawFile64(raw);
        if (error != nullptr) *error = "rawfile has an invalid or unsupported size";
        return false;
    }
    bytes.resize(static_cast<std::size_t>(size));
    std::int64_t done = 0;
    while (done < size) {
        const std::int64_t read = OH_ResourceManager_ReadRawFile64(raw, bytes.data() + done, size - done);
        if (read <= 0) {
            OH_ResourceManager_CloseRawFile64(raw);
            bytes.clear();
            if (error != nullptr) *error = "rawfile read ended before the declared size";
            return false;
        }
        done += read;
    }
    OH_ResourceManager_CloseRawFile64(raw);
    return true;
}

bool LoadPelicanAssetsFromRawFile(
    NativeResourceManager* manager,
    AssetBundle& bundle,
    std::string* error) {
    std::vector<std::uint8_t> bytes;
    if (!ReadRawFile(manager, "pelican_assets.pak", bytes, error)) return false;
    // Use the callback path so AssetBundle takes ownership of exactly one copy.
    AssetBundle::ReadFileCallbacks callbacks;
    callbacks.GetSize = [&bytes](std::string_view, std::uint64_t& size, std::string&) {
        size = bytes.size();
        return true;
    };
    callbacks.ReadAt = [&bytes](std::string_view, std::uint64_t offset, MutableByteSpan destination, std::string& callbackError) {
        if (offset > bytes.size() || destination.size > bytes.size() - static_cast<std::size_t>(offset)) {
            callbackError = "rawfile callback range is out of bounds";
            return false;
        }
        std::copy_n(bytes.data() + static_cast<std::size_t>(offset), destination.size, destination.data);
        return true;
    };
    return bundle.LoadFromReadFile("pelican_assets.pak", callbacks, error);
}

} // namespace pelican::assets
#endif
