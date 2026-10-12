#pragma once

#include "pelican/assets/AssetBundle.h"

#if defined(__OHOS__)
#include <rawfile/raw_file_manager.h>
#endif

#include <string>
#include <vector>

namespace pelican::assets {

#if defined(__OHOS__)
// Reads one HAP rawfile into caller-owned bytes. Keep bytes alive while using
// AssetBundle::LoadFromMemory({bytes.data(), bytes.size()}).
bool ReadRawFile(
    NativeResourceManager* manager,
    const char* name,
    std::vector<std::uint8_t>& bytes,
    std::string* error = nullptr);

// Convenience wrapper for the required package name "pelican_assets.pak".
bool LoadPelicanAssetsFromRawFile(
    NativeResourceManager* manager,
    AssetBundle& bundle,
    std::string* error = nullptr);
#endif

} // namespace pelican::assets
