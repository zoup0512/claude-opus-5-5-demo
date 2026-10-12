#include "pelican/assets/AssetBundle.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <new>
#include <utility>

namespace pelican::assets {
namespace {

constexpr std::size_t kHeaderSize = 96;
constexpr std::size_t kSectionSize = 32;
constexpr std::uint16_t kFormatVersion = 1;
constexpr std::uint16_t kIndexVersion = 1;
constexpr std::uint32_t kEndianTag = 0x01020304u;
constexpr std::uint32_t kMaxSections = 64;

constexpr std::uint32_t kSectionStrings = 1;
constexpr std::uint32_t kSectionBlobs = 2;
constexpr std::uint32_t kSectionGeometries = 3;
constexpr std::uint32_t kSectionTextures = 4;
constexpr std::uint32_t kSectionMaterials = 5;
constexpr std::uint32_t kSectionAssets = 6;
constexpr std::uint32_t kSectionNodes = 7;
constexpr std::uint32_t kSectionChildren = 8;
constexpr std::uint32_t kSectionNodeMaterials = 9;
constexpr std::uint32_t kSectionAnchors = 10;
constexpr std::uint32_t kSectionRoles = 11;
constexpr std::uint32_t kSectionInstances = 12;
constexpr std::uint32_t kSectionData = 13;

constexpr std::uint32_t kBlobRecordSize = 64;
constexpr std::uint32_t kGeometryRecordSize = 264;
constexpr std::uint32_t kTextureRecordSize = 96;
constexpr std::uint32_t kMaterialRecordSize = 236;
constexpr std::uint32_t kAssetRecordSize = 32;
constexpr std::uint32_t kNodeRecordSize = 104;
constexpr std::uint32_t kAnchorRecordSize = 16;
constexpr std::uint32_t kRoleRecordSize = 24;
constexpr std::uint32_t kInstanceRecordSize = 32;

bool HostIsLittleEndian() noexcept {
    const std::uint16_t value = 1;
    return *reinterpret_cast<const std::uint8_t*>(&value) == 1;
}

std::uint16_t ReadU16(const std::uint8_t* p) noexcept {
    return static_cast<std::uint16_t>(p[0]) |
        static_cast<std::uint16_t>(static_cast<std::uint16_t>(p[1]) << 8u);
}

std::uint32_t ReadU32(const std::uint8_t* p) noexcept {
    return static_cast<std::uint32_t>(p[0]) |
        (static_cast<std::uint32_t>(p[1]) << 8u) |
        (static_cast<std::uint32_t>(p[2]) << 16u) |
        (static_cast<std::uint32_t>(p[3]) << 24u);
}

std::int32_t ReadI32(const std::uint8_t* p) noexcept {
    return static_cast<std::int32_t>(ReadU32(p));
}

std::uint64_t ReadU64(const std::uint8_t* p) noexcept {
    return static_cast<std::uint64_t>(ReadU32(p)) |
        (static_cast<std::uint64_t>(ReadU32(p + 4)) << 32u);
}

float ReadF32(const std::uint8_t* p) noexcept {
    const std::uint32_t bits = ReadU32(p);
    float value = 0.0f;
    static_assert(sizeof(value) == sizeof(bits), "float32 required");
    std::memcpy(&value, &bits, sizeof(value));
    return value;
}

bool AddOverflows(std::uint64_t a, std::uint64_t b, std::uint64_t limit) noexcept {
    return a > limit || b > limit - a;
}

bool MulOverflows(std::uint64_t a, std::uint64_t b, std::uint64_t limit) noexcept {
    return a != 0 && b > limit / a;
}

std::uint32_t Crc32(ByteSpan bytes) noexcept {
    std::uint32_t crc = 0xffffffffu;
    for (std::size_t i = 0; i < bytes.size; ++i) {
        crc ^= bytes.data[i];
        for (unsigned bit = 0; bit < 8; ++bit) {
            crc = (crc >> 1u) ^ ((crc & 1u) ? 0xedb88320u : 0u);
        }
    }
    return crc ^ 0xffffffffu;
}

bool IsFinite(float value) noexcept {
    return std::isfinite(value);
}

void SetError(std::string* error, std::string message) {
    if (error != nullptr) *error = std::move(message);
}

struct SectionView {
    std::uint32_t type = 0;
    std::uint32_t recordSize = 0;
    std::uint64_t offset = 0;
    std::uint64_t length = 0;
    std::uint32_t count = 0;
    std::uint32_t crc = 0;
    const std::uint8_t* data = nullptr;
};

struct SliceRecord {
    std::uint32_t blob = kInvalidIndex;
    std::uint32_t offset = 0;
    std::uint32_t byteLength = 0;
    std::uint32_t count = 0;
    std::uint16_t itemSize = 0;
    std::uint8_t kind = 0;
    bool normalized = false;
};

SliceRecord ReadSlice(const std::uint8_t* record, std::uint32_t offset) noexcept {
    SliceRecord slice;
    slice.blob = ReadU32(record + offset + 0);
    slice.offset = ReadU32(record + offset + 4);
    slice.byteLength = ReadU32(record + offset + 8);
    slice.count = ReadU32(record + offset + 12);
    slice.itemSize = ReadU16(record + offset + 16);
    slice.kind = record[offset + 18];
    slice.normalized = record[offset + 19] != 0;
    return slice;
}

struct BindingRecord {
    std::uint32_t texture = kInvalidIndex;
    TextureSampler sampler {};
    TextureSlot slot = TextureSlot::None;
};

BindingRecord ReadBinding(const std::uint8_t* record, std::uint32_t offset) noexcept {
    BindingRecord result;
    result.texture = ReadU32(record + offset + 0);
    if (result.texture == kInvalidIndex) return result;
    result.sampler.wrapS = ReadU16(record + offset + 4);
    result.sampler.wrapT = ReadU16(record + offset + 6);
    result.sampler.minFilter = ReadU16(record + offset + 8);
    result.sampler.magFilter = ReadU16(record + offset + 10);
    result.sampler.flipY = record[offset + 12] != 0;
    result.slot = static_cast<TextureSlot>(record[offset + 13]);
    result.sampler.repeat = {ReadF32(record + offset + 16), ReadF32(record + offset + 20)};
    result.sampler.offset = {ReadF32(record + offset + 24), ReadF32(record + offset + 28)};
    result.sampler.center = {ReadF32(record + offset + 32), ReadF32(record + offset + 36)};
    result.sampler.rotation = ReadF32(record + offset + 40);
    return result;
}

bool AllFinite(const std::uint8_t* data, std::size_t bytes) noexcept {
    if (bytes % 4u != 0u) return false;
    for (std::size_t offset = 0; offset < bytes; offset += 4u) {
        if (!IsFinite(ReadF32(data + offset))) return false;
    }
    return true;
}

} // namespace

struct AssetBundle::Impl {
    ByteSpan bytes {};
    std::vector<std::uint8_t> ownedBytes;
    std::array<std::uint8_t, 32> sourceManifestSha {};
    std::vector<SectionView> sections;
    const SectionView* strings = nullptr;
    const SectionView* blobs = nullptr;
    const SectionView* geometries = nullptr;
    const SectionView* textures = nullptr;
    const SectionView* materials = nullptr;
    const SectionView* assets = nullptr;
    const SectionView* nodes = nullptr;
    const SectionView* children = nullptr;
    const SectionView* nodeMaterials = nullptr;
    const SectionView* anchors = nullptr;
    const SectionView* roles = nullptr;
    const SectionView* instances = nullptr;
    const SectionView* data = nullptr;
    BundleStats stats {};

    void Clear() noexcept {
        bytes = {};
        ownedBytes.clear();
        sourceManifestSha.fill(0);
        sections.clear();
        strings = blobs = geometries = textures = materials = assets = nodes = nullptr;
        children = nodeMaterials = anchors = roles = instances = data = nullptr;
        stats = {};
    }

    const SectionView* FindSection(std::uint32_t type) const noexcept {
        for (const SectionView& section : sections) if (section.type == type) return &section;
        return nullptr;
    }

    const std::uint8_t* Record(const SectionView* section, std::uint32_t index) const noexcept {
        if (section == nullptr || index >= section->count || section->recordSize == 0) return nullptr;
        return section->data + static_cast<std::size_t>(section->recordSize) * index;
    }

    std::string_view String(std::uint32_t offset) const noexcept {
        if (strings == nullptr || offset >= strings->length) return {};
        const char* begin = reinterpret_cast<const char*>(strings->data + offset);
        const char* end = reinterpret_cast<const char*>(strings->data + strings->length);
        const char* cursor = begin;
        while (cursor < end && *cursor != '\0') ++cursor;
        if (cursor == end) return {};
        return {begin, static_cast<std::size_t>(cursor - begin)};
    }

    ByteSpan BlobData(std::uint32_t blobIndex) const noexcept {
        const std::uint8_t* record = Record(blobs, blobIndex);
        if (record == nullptr || data == nullptr) return {};
        const std::uint64_t offset = ReadU64(record + 16);
        const std::uint64_t length = ReadU64(record + 24);
        if (AddOverflows(offset, length, data->length)) return {};
        return {data->data + static_cast<std::size_t>(offset), static_cast<std::size_t>(length)};
    }

    const float* FloatSlice(const SliceRecord& slice) const noexcept {
        if (slice.blob == kInvalidIndex) return nullptr;
        const ByteSpan blob = BlobData(slice.blob);
        if (AddOverflows(slice.offset, slice.byteLength, blob.size)) return nullptr;
        const std::uint8_t* pointer = blob.data + slice.offset;
        if ((reinterpret_cast<std::uintptr_t>(pointer) % alignof(float)) != 0u) return nullptr;
        return reinterpret_cast<const float*>(pointer);
    }

    const std::uint32_t* IndexSlice(const SliceRecord& slice) const noexcept {
        if (slice.blob == kInvalidIndex) return nullptr;
        const ByteSpan blob = BlobData(slice.blob);
        if (AddOverflows(slice.offset, slice.byteLength, blob.size)) return nullptr;
        const std::uint8_t* pointer = blob.data + slice.offset;
        if ((reinterpret_cast<std::uintptr_t>(pointer) % alignof(std::uint32_t)) != 0u) return nullptr;
        return reinterpret_cast<const std::uint32_t*>(pointer);
    }

    bool ValidateStringOffset(std::uint32_t offset) const noexcept {
        if (strings == nullptr || offset >= strings->length || (offset != 0 && strings->data[offset - 1] != 0)) return false;
        for (std::uint64_t i = offset; i < strings->length; ++i) if (strings->data[i] == 0) return true;
        return false;
    }

    bool ValidateSlice(
        const SliceRecord& slice,
        std::uint8_t expectedKind,
        std::uint16_t expectedItemSize,
        std::uint32_t expectedCount,
        bool optional,
        std::string* error,
        const char* label) const {
        if (slice.blob == kInvalidIndex) {
            if (optional) return true;
            SetError(error, std::string(label) + " is missing");
            return false;
        }
        if (slice.blob >= blobs->count || slice.kind != expectedKind || slice.itemSize != expectedItemSize ||
            slice.count != expectedCount || slice.byteLength != slice.count * slice.itemSize * 4u) {
            SetError(error, std::string(label) + " has invalid metadata");
            return false;
        }
        const ByteSpan blob = BlobData(slice.blob);
        if (blob.data == nullptr || AddOverflows(slice.offset, slice.byteLength, blob.size) || (slice.offset % 4u) != 0u) {
            SetError(error, std::string(label) + " is out of bounds or misaligned");
            return false;
        }
        return true;
    }

    bool Parse(ByteSpan input, std::string* error) {
        Clear();
        if (!HostIsLittleEndian()) {
            SetError(error, "AssetBundle requires a little-endian host");
            return false;
        }
        if (input.data == nullptr || input.size < kHeaderSize) {
            SetError(error, "bundle is shorter than the 96-byte header");
            return false;
        }
        if ((reinterpret_cast<std::uintptr_t>(input.data) % alignof(std::uint32_t)) != 0u) {
            SetError(error, "bundle base address must be at least 4-byte aligned for zero-copy typed views");
            return false;
        }
        if (std::memcmp(input.data, "PELICAN\0", 8) != 0) {
            SetError(error, "bundle magic mismatch");
            return false;
        }
        if (ReadU16(input.data + 8) != kFormatVersion || ReadU16(input.data + 10) != kIndexVersion ||
            ReadU16(input.data + 12) != kHeaderSize || ReadU16(input.data + 14) != kSectionSize) {
            SetError(error, "unsupported bundle/index/header version");
            return false;
        }
        if (ReadU32(input.data + 16) != kEndianTag) {
            SetError(error, "endianness marker mismatch");
            return false;
        }
        const std::uint32_t sectionCount = ReadU32(input.data + 20);
        const std::uint64_t tableOffset = ReadU64(input.data + 24);
        const std::uint64_t tableLength = ReadU64(input.data + 32);
        const std::uint64_t fileSize = ReadU64(input.data + 40);
        if (sectionCount == 0 || sectionCount > kMaxSections || tableLength != sectionCount * kSectionSize ||
            fileSize != input.size || AddOverflows(tableOffset, tableLength, input.size)) {
            SetError(error, "invalid section table bounds/count or file size");
            return false;
        }
        std::array<std::uint8_t, kHeaderSize> header {};
        std::copy(input.data, input.data + kHeaderSize, header.begin());
        const std::uint32_t expectedHeaderCrc = ReadU32(input.data + 88);
        std::fill(header.begin() + 88, header.begin() + 96, static_cast<std::uint8_t>(0));
        if (Crc32({header.data(), header.size()}) != expectedHeaderCrc) {
            SetError(error, "header CRC32 mismatch");
            return false;
        }
        const std::uint32_t expectedFileCrc = ReadU32(input.data + 92);
        std::uint32_t fileCrc = 0xffffffffu;
        for (std::size_t i = 0; i < input.size; ++i) {
            std::uint8_t value = (i >= 92u && i < 96u) ? 0u : input.data[i];
            fileCrc ^= value;
            for (unsigned bit = 0; bit < 8; ++bit) {
                fileCrc = (fileCrc >> 1u) ^ ((fileCrc & 1u) ? 0xedb88320u : 0u);
            }
        }
        fileCrc ^= 0xffffffffu;
        if (fileCrc != expectedFileCrc) {
            SetError(error, "file CRC32 mismatch");
            return false;
        }
        const ByteSpan tableBytes {input.data + static_cast<std::size_t>(tableOffset), static_cast<std::size_t>(tableLength)};
        if (Crc32(tableBytes) != ReadU32(input.data + 48)) {
            SetError(error, "section table CRC32 mismatch");
            return false;
        }

        bytes = input;
        std::copy(input.data + 56, input.data + 88, sourceManifestSha.begin());
        sections.reserve(sectionCount);
        for (std::uint32_t i = 0; i < sectionCount; ++i) {
            const std::uint8_t* entry = tableBytes.data + i * kSectionSize;
            SectionView section;
            section.type = ReadU32(entry + 0);
            section.recordSize = ReadU32(entry + 4);
            section.offset = ReadU64(entry + 8);
            section.length = ReadU64(entry + 16);
            section.count = ReadU32(entry + 24);
            section.crc = ReadU32(entry + 28);
            if (section.type == 0 || section.count > std::numeric_limits<std::uint32_t>::max() || AddOverflows(section.offset, section.length, input.size) ||
                (section.recordSize != 0 &&
                    (MulOverflows(section.recordSize, section.count, std::numeric_limits<std::uint64_t>::max()) ||
                     static_cast<std::uint64_t>(section.recordSize) * section.count != section.length))) {
                SetError(error, "invalid section metadata");
                Clear();
                return false;
            }
            for (const SectionView& existing : sections) {
                if (existing.type == section.type) {
                    SetError(error, "duplicate section type");
                    Clear();
                    return false;
                }
                const std::uint64_t existingEnd = existing.offset + existing.length;
                const std::uint64_t sectionEnd = section.offset + section.length;
                if (section.length != 0 && existing.length != 0 && section.offset < existingEnd && existing.offset < sectionEnd) {
                    SetError(error, "overlapping sections");
                    Clear();
                    return false;
                }
            }
            section.data = input.data + static_cast<std::size_t>(section.offset);
            if (Crc32({section.data, static_cast<std::size_t>(section.length)}) != section.crc) {
                SetError(error, "section CRC32 mismatch");
                Clear();
                return false;
            }
            sections.push_back(section);
        }

        strings = FindSection(kSectionStrings);
        blobs = FindSection(kSectionBlobs);
        geometries = FindSection(kSectionGeometries);
        textures = FindSection(kSectionTextures);
        materials = FindSection(kSectionMaterials);
        assets = FindSection(kSectionAssets);
        nodes = FindSection(kSectionNodes);
        children = FindSection(kSectionChildren);
        nodeMaterials = FindSection(kSectionNodeMaterials);
        anchors = FindSection(kSectionAnchors);
        roles = FindSection(kSectionRoles);
        instances = FindSection(kSectionInstances);
        data = FindSection(kSectionData);
        const struct RequiredSection { const SectionView* section; std::uint32_t size; const char* name; } required[] = {
            {strings, 1, "strings"}, {blobs, kBlobRecordSize, "blobs"},
            {geometries, kGeometryRecordSize, "geometries"}, {textures, kTextureRecordSize, "textures"},
            {materials, kMaterialRecordSize, "materials"}, {assets, kAssetRecordSize, "assets"},
            {nodes, kNodeRecordSize, "nodes"}, {children, 4, "children"},
            {nodeMaterials, 4, "node materials"}, {anchors, kAnchorRecordSize, "anchors"},
            {roles, kRoleRecordSize, "roles"}, {instances, kInstanceRecordSize, "instances"},
            {data, 1, "data"},
        };
        for (const RequiredSection& item : required) {
            if (item.section == nullptr || item.section->recordSize != item.size) {
                SetError(error, std::string("missing or incompatible ") + item.name + " section");
                Clear();
                return false;
            }
        }
        if (strings->length == 0 || strings->data[0] != 0) {
            SetError(error, "string table must start with an empty string");
            Clear();
            return false;
        }

        for (std::uint32_t i = 0; i < blobs->count; ++i) {
            const std::uint8_t* record = Record(blobs, i);
            if (!ValidateStringOffset(ReadU32(record + 0)) || !ValidateStringOffset(ReadU32(record + 4))) {
                SetError(error, "invalid blob string offset"); Clear(); return false;
            }
            const std::uint64_t offset = ReadU64(record + 16);
            const std::uint64_t length = ReadU64(record + 24);
            if (AddOverflows(offset, length, data->length) || Crc32({data->data + offset, static_cast<std::size_t>(length)}) != ReadU32(record + 12)) {
                SetError(error, "blob bounds or CRC32 mismatch"); Clear(); return false;
            }
            stats.payloadBytes += length;
        }

        stats.geometryCount = geometries->count;
        for (std::uint32_t i = 0; i < geometries->count; ++i) {
            const std::uint8_t* record = Record(geometries, i);
            const std::uint32_t vertexCount = ReadU32(record + 4);
            const std::uint32_t indexCount = ReadU32(record + 8);
            const std::uint32_t triangleCount = ReadU32(record + 12);
            const std::uint32_t drawStart = ReadU32(record + 16);
            const std::uint32_t drawCount = ReadU32(record + 20);
            const std::uint16_t groupCount = ReadU16(record + 24);
            const SliceRecord position = ReadSlice(record, 28);
            const SliceRecord normal = ReadSlice(record, 48);
            const SliceRecord uv = ReadSlice(record, 68);
            const SliceRecord color = ReadSlice(record, 88);
            const SliceRecord index = ReadSlice(record, 108);
            const SliceRecord morph = ReadSlice(record, 128);
            if (!ValidateStringOffset(ReadU32(record + 0)) || vertexCount == 0 || indexCount == 0 ||
                indexCount % 3u != 0u || triangleCount != indexCount / 3u || drawStart > indexCount ||
                drawCount > indexCount - drawStart || groupCount > 6 ||
                !ValidateSlice(position, 1, 3, vertexCount, false, error, "position") ||
                !ValidateSlice(normal, 2, 3, vertexCount, false, error, "normal") ||
                !ValidateSlice(uv, 3, 2, vertexCount, true, error, "uv") ||
                !ValidateSlice(color, 4, 3, vertexCount, true, error, "color") ||
                !ValidateSlice(index, 5, 1, indexCount, false, error, "index") ||
                !ValidateSlice(morph, 6, 3, vertexCount, true, error, "morph position")) {
                Clear(); return false;
            }
            for (const SliceRecord& slice : {position, normal, uv, color, morph}) {
                if (slice.blob != kInvalidIndex) {
                    const ByteSpan blob = BlobData(slice.blob);
                    if (!AllFinite(blob.data + slice.offset, slice.byteLength)) {
                        SetError(error, "non-finite geometry attribute"); Clear(); return false;
                    }
                }
            }
            const ByteSpan indexBlob = BlobData(index.blob);
            for (std::uint32_t j = 0; j < index.count; ++j) {
                if (ReadU32(indexBlob.data + index.offset + j * 4u) >= vertexCount) {
                    SetError(error, "geometry index is out of range"); Clear(); return false;
                }
            }
            for (std::uint16_t group = 0; group < groupCount; ++group) {
                const std::uint32_t groupOffset = 188u + group * 12u;
                const std::uint32_t start = ReadU32(record + groupOffset + 0);
                const std::uint32_t count = ReadU32(record + groupOffset + 4);
                if (start > indexCount || count > indexCount - start) {
                    SetError(error, "geometry group is out of range"); Clear(); return false;
                }
            }
            if (!AllFinite(record + 148, 40) || ReadF32(record + 184) < 0.0f) {
                SetError(error, "invalid geometry bounds"); Clear(); return false;
            }
            stats.vertexCount += vertexCount;
            stats.triangleCount += triangleCount;
        }

        stats.textureCount = textures->count;
        for (std::uint32_t i = 0; i < textures->count; ++i) {
            const std::uint8_t* record = Record(textures, i);
            const std::uint32_t blob = ReadU32(record + 8);
            const std::uint32_t width = ReadU32(record + 12);
            const std::uint32_t height = ReadU32(record + 16);
            const std::uint32_t rowStride = ReadU32(record + 20);
            const ByteSpan pixels = BlobData(blob);
            if (!ValidateStringOffset(ReadU32(record + 0)) || !ValidateStringOffset(ReadU32(record + 4)) ||
                blob >= blobs->count || width == 0 || height == 0 || rowStride != width * 4u ||
                pixels.size != static_cast<std::uint64_t>(rowStride) * height || record[39] != 4 ||
                Crc32(pixels) != ReadU32(record + 24) || !AllFinite(record + 40, 28)) {
                SetError(error, "invalid texture metadata or payload"); Clear(); return false;
            }
        }

        stats.materialCount = materials->count;
        for (std::uint32_t i = 0; i < materials->count; ++i) {
            const std::uint8_t* record = Record(materials, i);
            if (!ValidateStringOffset(ReadU32(record + 0)) || !ValidateStringOffset(ReadU32(record + 4)) ||
                record[8] > static_cast<std::uint8_t>(MaterialType::MeshPhysical) ||
                !AllFinite(record + 20, 12) || !AllFinite(record + 32, 112)) {
                SetError(error, "invalid material metadata"); Clear(); return false;
            }
            for (std::uint32_t bindingOffset : {144u, 188u}) {
                const BindingRecord binding = ReadBinding(record, bindingOffset);
                if (binding.texture != kInvalidIndex &&
                    (binding.texture >= textures->count || !AllFinite(record + bindingOffset + 16, 28))) {
                    SetError(error, "invalid material texture binding"); Clear(); return false;
                }
            }
        }

        stats.assetCount = assets->count;
        stats.nodeCount = nodes->count;
        for (std::uint32_t i = 0; i < assets->count; ++i) {
            const std::uint8_t* record = Record(assets, i);
            const std::uint32_t root = ReadU32(record + 8);
            const std::uint32_t firstNode = ReadU32(record + 12);
            const std::uint32_t nodeCount = ReadU32(record + 16);
            const std::uint32_t firstAnchor = ReadU32(record + 20);
            const std::uint32_t anchorCount = ReadU32(record + 24);
            if (!ValidateStringOffset(ReadU32(record + 0)) || !ValidateStringOffset(ReadU32(record + 4)) ||
                root >= nodes->count || firstNode > nodes->count || nodeCount > nodes->count - firstNode ||
                firstAnchor > anchors->count || anchorCount > anchors->count - firstAnchor) {
                SetError(error, "invalid asset range"); Clear(); return false;
            }
        }

        for (std::uint32_t i = 0; i < nodes->count; ++i) {
            const std::uint8_t* record = Record(nodes, i);
            const std::uint32_t asset = ReadU32(record + 8);
            const std::uint32_t parent = ReadU32(record + 12);
            const std::uint32_t firstChild = ReadU32(record + 16);
            const std::uint16_t childCount = ReadU16(record + 20);
            const std::uint32_t geometry = ReadU32(record + 24);
            const std::uint32_t firstMaterial = ReadU32(record + 28);
            const std::uint16_t materialCount = ReadU16(record + 32);
            const std::uint16_t morphCount = ReadU16(record + 34);
            const std::uint32_t instance = ReadU32(record + 36);
            if (!ValidateStringOffset(ReadU32(record + 0)) || !ValidateStringOffset(ReadU32(record + 4)) ||
                asset >= assets->count || (parent != kInvalidIndex && parent >= nodes->count) ||
                firstChild > children->count || childCount > children->count - firstChild ||
                (geometry != kInvalidIndex && geometry >= geometries->count) ||
                firstMaterial > nodeMaterials->count || materialCount > nodeMaterials->count - firstMaterial ||
                morphCount > 1 || (instance != kInvalidIndex && instance >= instances->count) ||
                !AllFinite(record + 44, 44)) {
                SetError(error, "invalid node metadata"); Clear(); return false;
            }
            for (std::uint16_t child = 0; child < childCount; ++child) {
                const std::uint32_t childNode = ReadU32(children->data + (firstChild + child) * 4u);
                if (childNode >= nodes->count || ReadU32(Record(nodes, childNode) + 12) != i) {
                    SetError(error, "invalid child or parent relationship"); Clear(); return false;
                }
            }
            for (std::uint16_t material = 0; material < materialCount; ++material) {
                if (ReadU32(nodeMaterials->data + (firstMaterial + material) * 4u) >= materials->count) {
                    SetError(error, "node material index out of range"); Clear(); return false;
                }
            }
        }

        for (std::uint32_t i = 0; i < anchors->count; ++i) {
            const std::uint8_t* record = Record(anchors, i);
            if (ReadU32(record + 0) >= assets->count || !ValidateStringOffset(ReadU32(record + 4)) ||
                ReadU32(record + 8) >= nodes->count) {
                SetError(error, "invalid anchor"); Clear(); return false;
            }
        }
        for (std::uint32_t i = 0; i < roles->count; ++i) {
            const std::uint8_t* record = Record(roles, i);
            if (ReadU32(record + 0) >= assets->count || !ValidateStringOffset(ReadU32(record + 4)) ||
                ReadU32(record + 8) >= nodes->count || record[12] > 100 || !ValidateStringOffset(ReadU32(record + 16))) {
                SetError(error, "invalid stable role"); Clear(); return false;
            }
        }
        for (std::uint32_t i = 0; i < instances->count; ++i) {
            const std::uint8_t* record = Record(instances, i);
            const std::uint32_t node = ReadU32(record + 0);
            const std::uint32_t blob = ReadU32(record + 4);
            const std::uint32_t offset = ReadU32(record + 8);
            const std::uint32_t byteLength = ReadU32(record + 12);
            const std::uint32_t count = ReadU32(record + 16);
            const std::uint16_t itemSize = ReadU16(record + 20);
            const ByteSpan source = BlobData(blob);
            if (node >= nodes->count || blob >= blobs->count || itemSize != 16 || byteLength != count * 64u ||
                AddOverflows(offset, byteLength, source.size) || !AllFinite(source.data + offset, byteLength)) {
                SetError(error, "invalid instance matrices"); Clear(); return false;
            }
        }
        return true;
    }
};

AssetBundle::AssetBundle() : impl_(std::make_unique<Impl>()) {}
AssetBundle::~AssetBundle() = default;
AssetBundle::AssetBundle(AssetBundle&&) noexcept = default;
AssetBundle& AssetBundle::operator=(AssetBundle&&) noexcept = default;

bool AssetBundle::LoadFromMemory(ByteSpan bytes, std::string* error) {
    if (error != nullptr) error->clear();
    return impl_->Parse(bytes, error);
}

bool AssetBundle::LoadFromReadFile(std::string_view path, const ReadFileCallbacks& readFile, std::string* error) {
    if (error != nullptr) error->clear();
    std::string callbackError;
    std::uint64_t fileSize = 0;
    if (!readFile.GetSize || !readFile.ReadAt || !readFile.GetSize(path, fileSize, callbackError)) {
        SetError(error, callbackError.empty() ? "ReadFile GetSize callback failed" : callbackError);
        return false;
    }
    if (fileSize < kHeaderSize || fileSize > std::numeric_limits<std::size_t>::max()) {
        SetError(error, "ReadFile callback returned an unsupported file size");
        return false;
    }
    std::vector<std::uint8_t> loaded(static_cast<std::size_t>(fileSize));
    if (!readFile.ReadAt(path, 0, {loaded.data(), loaded.size()}, callbackError)) {
        SetError(error, callbackError.empty() ? "ReadFile ReadAt callback failed" : callbackError);
        return false;
    }
    if (!impl_->Parse({loaded.data(), loaded.size()}, error)) return false;
    impl_->ownedBytes = std::move(loaded);
    impl_->bytes = {impl_->ownedBytes.data(), impl_->ownedBytes.size()};
    for (SectionView& section : impl_->sections) section.data = impl_->bytes.data + section.offset;
    impl_->strings = impl_->FindSection(kSectionStrings);
    impl_->blobs = impl_->FindSection(kSectionBlobs);
    impl_->geometries = impl_->FindSection(kSectionGeometries);
    impl_->textures = impl_->FindSection(kSectionTextures);
    impl_->materials = impl_->FindSection(kSectionMaterials);
    impl_->assets = impl_->FindSection(kSectionAssets);
    impl_->nodes = impl_->FindSection(kSectionNodes);
    impl_->children = impl_->FindSection(kSectionChildren);
    impl_->nodeMaterials = impl_->FindSection(kSectionNodeMaterials);
    impl_->anchors = impl_->FindSection(kSectionAnchors);
    impl_->roles = impl_->FindSection(kSectionRoles);
    impl_->instances = impl_->FindSection(kSectionInstances);
    impl_->data = impl_->FindSection(kSectionData);
    return true;
}

void AssetBundle::Reset() noexcept { impl_->Clear(); }
bool AssetBundle::loaded() const noexcept { return impl_->bytes.data != nullptr && impl_->assets != nullptr; }
ByteSpan AssetBundle::bytes() const noexcept { return impl_->bytes; }
BundleStats AssetBundle::stats() const noexcept { return impl_->stats; }
std::array<std::uint8_t, 32> AssetBundle::source_manifest_sha256() const noexcept { return impl_->sourceManifestSha; }

std::uint32_t AssetBundle::asset_count() const noexcept { return impl_->assets ? impl_->assets->count : 0; }
AssetView AssetBundle::asset(std::uint32_t index) const noexcept { return index < asset_count() ? AssetView(this, index) : AssetView(); }
AssetView AssetBundle::find_asset(std::string_view id) const noexcept {
    for (std::uint32_t i = 0; i < asset_count(); ++i) if (asset(i).id() == id) return asset(i);
    return {};
}
std::uint32_t AssetBundle::node_count() const noexcept { return impl_->nodes ? impl_->nodes->count : 0; }
NodeView AssetBundle::node(std::uint32_t index) const noexcept { return index < node_count() ? NodeView(this, index) : NodeView(); }
NodeView AssetBundle::find_node(std::string_view id) const noexcept {
    for (std::uint32_t i = 0; i < node_count(); ++i) if (node(i).id() == id) return node(i);
    return {};
}
std::uint32_t AssetBundle::geometry_count() const noexcept { return impl_->geometries ? impl_->geometries->count : 0; }
GeometryView AssetBundle::geometry(std::uint32_t index) const noexcept { return index < geometry_count() ? GeometryView(this, index) : GeometryView(); }
GeometryView AssetBundle::find_geometry(std::string_view id) const noexcept {
    for (std::uint32_t i = 0; i < geometry_count(); ++i) if (geometry(i).id() == id) return geometry(i);
    return {};
}
std::uint32_t AssetBundle::texture_count() const noexcept { return impl_->textures ? impl_->textures->count : 0; }
TextureView AssetBundle::texture(std::uint32_t index) const noexcept { return index < texture_count() ? TextureView(this, index) : TextureView(); }
TextureView AssetBundle::find_texture(std::string_view id) const noexcept {
    for (std::uint32_t i = 0; i < texture_count(); ++i) if (texture(i).id() == id) return texture(i);
    return {};
}
std::uint32_t AssetBundle::material_count() const noexcept { return impl_->materials ? impl_->materials->count : 0; }
MaterialView AssetBundle::material(std::uint32_t index) const noexcept { return index < material_count() ? MaterialView(this, index) : MaterialView(); }
MaterialView AssetBundle::find_material(std::string_view id) const noexcept {
    for (std::uint32_t i = 0; i < material_count(); ++i) if (material(i).id() == id) return material(i);
    return {};
}
std::uint32_t AssetBundle::anchor_count() const noexcept { return impl_->anchors ? impl_->anchors->count : 0; }
AnchorView AssetBundle::anchor(std::uint32_t index) const noexcept { return index < anchor_count() ? AnchorView(this, index) : AnchorView(); }
std::uint32_t AssetBundle::role_count() const noexcept { return impl_->roles ? impl_->roles->count : 0; }
RoleView AssetBundle::role(std::uint32_t index) const noexcept { return index < role_count() ? RoleView(this, index) : RoleView(); }
std::uint32_t AssetBundle::instance_count() const noexcept { return impl_->instances ? impl_->instances->count : 0; }
InstanceView AssetBundle::instance(std::uint32_t index) const noexcept { return index < instance_count() ? InstanceView(this, index) : InstanceView(); }

GeometryView::operator bool() const noexcept { return bundle_ != nullptr && index_ < bundle_->geometry_count(); }
std::string_view GeometryView::id() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->geometries, index_) : nullptr; return r ? bundle_->impl_->String(ReadU32(r + 0)) : std::string_view{}; }
std::uint32_t GeometryView::vertex_count() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->geometries, index_) : nullptr; return r ? ReadU32(r + 4) : 0; }
std::uint32_t GeometryView::index_count() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->geometries, index_) : nullptr; return r ? ReadU32(r + 8) : 0; }
std::uint32_t GeometryView::triangle_count() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->geometries, index_) : nullptr; return r ? ReadU32(r + 12) : 0; }
std::uint32_t GeometryView::draw_start() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->geometries, index_) : nullptr; return r ? ReadU32(r + 16) : 0; }
std::uint32_t GeometryView::draw_count() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->geometries, index_) : nullptr; return r ? ReadU32(r + 20) : 0; }
FloatAttributeView GeometryView::position() const noexcept { if (!bundle_) return {}; const auto* r = bundle_->impl_->Record(bundle_->impl_->geometries, index_); if (!r) return {}; const SliceRecord s = ReadSlice(r, 28); return {bundle_->impl_->FloatSlice(s), s.count, s.itemSize, s.normalized}; }
FloatAttributeView GeometryView::normal() const noexcept { if (!bundle_) return {}; const auto* r = bundle_->impl_->Record(bundle_->impl_->geometries, index_); if (!r) return {}; const SliceRecord s = ReadSlice(r, 48); return {bundle_->impl_->FloatSlice(s), s.count, s.itemSize, s.normalized}; }
FloatAttributeView GeometryView::uv() const noexcept { if (!bundle_) return {}; const auto* r = bundle_->impl_->Record(bundle_->impl_->geometries, index_); if (!r) return {}; const SliceRecord s = ReadSlice(r, 68); return {bundle_->impl_->FloatSlice(s), s.count, s.itemSize, s.normalized}; }
FloatAttributeView GeometryView::color() const noexcept { if (!bundle_) return {}; const auto* r = bundle_->impl_->Record(bundle_->impl_->geometries, index_); if (!r) return {}; const SliceRecord s = ReadSlice(r, 88); return {bundle_->impl_->FloatSlice(s), s.count, s.itemSize, s.normalized}; }
IndexView GeometryView::indices() const noexcept { if (!bundle_) return {}; const auto* r = bundle_->impl_->Record(bundle_->impl_->geometries, index_); if (!r) return {}; const SliceRecord s = ReadSlice(r, 108); return {bundle_->impl_->IndexSlice(s), s.count}; }
std::uint32_t GeometryView::morph_target_count() const noexcept { return morph_position() ? 1u : 0u; }
FloatAttributeView GeometryView::morph_position(std::uint32_t target) const noexcept { if (!bundle_ || target != 0) return {}; const auto* r = bundle_->impl_->Record(bundle_->impl_->geometries, index_); if (!r) return {}; const SliceRecord s = ReadSlice(r, 128); return {bundle_->impl_->FloatSlice(s), s.count, s.itemSize, s.normalized}; }
bool GeometryView::morph_targets_relative() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->geometries, index_) : nullptr; return r && ReadU16(r + 26) != 0; }
std::uint32_t GeometryView::group_count() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->geometries, index_) : nullptr; return r ? ReadU16(r + 24) : 0; }
GeometryGroup GeometryView::group(std::uint32_t groupIndex) const noexcept { GeometryGroup g; const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->geometries, index_) : nullptr; if (!r || groupIndex >= group_count()) return g; const auto o = 188u + groupIndex * 12u; g.start = ReadU32(r + o); g.count = ReadU32(r + o + 4); g.materialIndex = ReadU16(r + o + 8); return g; }
Bounds GeometryView::bounds() const noexcept { Bounds b; const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->geometries, index_) : nullptr; if (!r) return b; for (int i = 0; i < 3; ++i) { b.minimum[i] = ReadF32(r + 148 + i * 4); b.maximum[i] = ReadF32(r + 160 + i * 4); b.sphereCenter[i] = ReadF32(r + 172 + i * 4); } b.sphereRadius = ReadF32(r + 184); return b; }

TextureView::operator bool() const noexcept { return bundle_ != nullptr && index_ < bundle_->texture_count(); }
std::string_view TextureView::id() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->textures, index_) : nullptr; return r ? bundle_->impl_->String(ReadU32(r + 0)) : std::string_view{}; }
std::string_view TextureView::name() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->textures, index_) : nullptr; return r ? bundle_->impl_->String(ReadU32(r + 4)) : std::string_view{}; }
std::uint32_t TextureView::width() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->textures, index_) : nullptr; return r ? ReadU32(r + 12) : 0; }
std::uint32_t TextureView::height() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->textures, index_) : nullptr; return r ? ReadU32(r + 16) : 0; }
std::uint32_t TextureView::row_stride() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->textures, index_) : nullptr; return r ? ReadU32(r + 20) : 0; }
ColorSpace TextureView::color_space() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->textures, index_) : nullptr; return r ? static_cast<ColorSpace>(r[36]) : ColorSpace::Linear; }
bool TextureView::flip_y() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->textures, index_) : nullptr; return r && r[37] != 0; }
bool TextureView::premultiply_alpha() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->textures, index_) : nullptr; return r && r[38] != 0; }
TextureSampler TextureView::sampler() const noexcept { TextureSampler s; const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->textures, index_) : nullptr; if (!r) return s; s.wrapS=ReadU16(r+28);s.wrapT=ReadU16(r+30);s.minFilter=ReadU16(r+32);s.magFilter=ReadU16(r+34);s.flipY=r[37]!=0;s.repeat={ReadF32(r+40),ReadF32(r+44)};s.offset={ReadF32(r+48),ReadF32(r+52)};s.center={ReadF32(r+56),ReadF32(r+60)};s.rotation=ReadF32(r+64);return s; }
ByteSpan TextureView::rgba8() const noexcept { const auto* r = bundle_ ? bundle_->impl_->Record(bundle_->impl_->textures, index_) : nullptr; return r ? bundle_->impl_->BlobData(ReadU32(r + 8)) : ByteSpan{}; }

TextureBindingView::operator bool() const noexcept { if (!bundle_) return false; const auto* r=bundle_->impl_->Record(bundle_->impl_->materials,materialIndex_); return r && ReadU32(r+relativeOffset_)!=kInvalidIndex; }
TextureSlot TextureBindingView::slot() const noexcept { if (!bundle_) return TextureSlot::None; const auto* r=bundle_->impl_->Record(bundle_->impl_->materials,materialIndex_); return r?ReadBinding(r,relativeOffset_).slot:TextureSlot::None; }
TextureView TextureBindingView::texture() const noexcept { if (!bundle_) return {}; const auto* r=bundle_->impl_->Record(bundle_->impl_->materials,materialIndex_); if(!r)return{};return bundle_->texture(ReadBinding(r,relativeOffset_).texture); }
TextureSampler TextureBindingView::sampler() const noexcept { if (!bundle_) return {}; const auto* r=bundle_->impl_->Record(bundle_->impl_->materials,materialIndex_); return r?ReadBinding(r,relativeOffset_).sampler:TextureSampler{}; }

MaterialView::operator bool() const noexcept { return bundle_ != nullptr && index_ < bundle_->material_count(); }
std::string_view MaterialView::id() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->materials,index_):nullptr;return r?bundle_->impl_->String(ReadU32(r)):std::string_view{}; }
std::string_view MaterialView::name() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->materials,index_):nullptr;return r?bundle_->impl_->String(ReadU32(r+4)):std::string_view{}; }
MaterialProperties MaterialView::properties() const noexcept { MaterialProperties p; const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->materials,index_):nullptr;if(!r)return p;p.type=static_cast<MaterialType>(r[8]);p.transparent=r[9]!=0;p.depthTest=r[10]!=0;p.depthWrite=r[11]!=0;p.vertexColors=r[12]!=0;p.flatShading=r[13]!=0;p.wireframe=r[14]!=0;p.side=r[15];p.blending=ReadU16(r+16);for(int i=0;i<3;++i){p.color[i]=ReadF32(r+20+i*4);p.emissive[i]=ReadF32(r+32+i*4);p.attenuationColor[i]=ReadF32(r+92+i*4);p.sheenColor[i]=ReadF32(r+112+i*4);}p.emissiveIntensity=ReadF32(r+44);p.opacity=ReadF32(r+48);p.alphaTest=ReadF32(r+52);p.roughness=ReadF32(r+56);p.metalness=ReadF32(r+60);p.clearcoat=ReadF32(r+64);p.clearcoatRoughness=ReadF32(r+68);p.ior=ReadF32(r+72);p.reflectivity=ReadF32(r+76);p.transmission=ReadF32(r+80);p.thickness=ReadF32(r+84);p.attenuationDistance=ReadF32(r+88);p.sheen=ReadF32(r+104);p.sheenRoughness=ReadF32(r+108);p.bumpScale=ReadF32(r+124);p.displacementScale=ReadF32(r+128);p.displacementBias=ReadF32(r+132);p.polygonOffsetFactor=ReadF32(r+136);p.polygonOffsetUnits=ReadF32(r+140);return p; }
TextureBindingView MaterialView::map() const noexcept { return *this?TextureBindingView(bundle_,index_,144):TextureBindingView{}; }
TextureBindingView MaterialView::bump_map() const noexcept { return *this?TextureBindingView(bundle_,index_,188):TextureBindingView{}; }

InstanceView::operator bool() const noexcept { return bundle_ != nullptr && index_ < bundle_->instance_count(); }
std::uint32_t InstanceView::count() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->instances,index_):nullptr;return r?ReadU32(r+16):0; }
ArrayView<float> InstanceView::matrices() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->instances,index_):nullptr;if(!r)return{};const ByteSpan b=bundle_->impl_->BlobData(ReadU32(r+4));const auto off=ReadU32(r+8);if(!b.data||off>b.size)return{};return{reinterpret_cast<const float*>(b.data+off),static_cast<std::size_t>(count())*16u}; }
NodeView InstanceView::node() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->instances,index_):nullptr;return r?bundle_->node(ReadU32(r)):NodeView{}; }

NodeView::operator bool() const noexcept { return bundle_ != nullptr && index_ < bundle_->node_count(); }
std::string_view NodeView::id() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r?bundle_->impl_->String(ReadU32(r)):std::string_view{}; }
std::string_view NodeView::name() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r?bundle_->impl_->String(ReadU32(r+4)):std::string_view{}; }
NodeType NodeView::type() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r?static_cast<NodeType>(r[22]):NodeType::Unknown; }
bool NodeView::visible() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r&&(r[23]&1u)!=0; }
bool NodeView::cast_shadow() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r&&(r[23]&2u)!=0; }
bool NodeView::receive_shadow() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r&&(r[23]&4u)!=0; }
std::int32_t NodeView::render_order() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r?ReadI32(r+40):0; }
std::uint32_t NodeView::asset_index() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r?ReadU32(r+8):kInvalidIndex; }
NodeView NodeView::parent() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r?bundle_->node(ReadU32(r+12)):NodeView{}; }
std::uint32_t NodeView::child_count() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r?ReadU16(r+20):0; }
NodeView NodeView::child(std::uint32_t childIndex) const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;if(!r||childIndex>=child_count())return{};const auto first=ReadU32(r+16);return bundle_->node(ReadU32(bundle_->impl_->children->data+(first+childIndex)*4u)); }
bool NodeView::has_geometry() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r&&ReadU32(r+24)!=kInvalidIndex; }
GeometryView NodeView::geometry() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r?bundle_->geometry(ReadU32(r+24)):GeometryView{}; }
std::uint32_t NodeView::material_count() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r?ReadU16(r+32):0; }
MaterialView NodeView::material(std::uint32_t materialIndex) const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;if(!r||materialIndex>=material_count())return{};const auto first=ReadU32(r+28);return bundle_->material(ReadU32(bundle_->impl_->nodeMaterials->data+(first+materialIndex)*4u)); }
Transform NodeView::local_transform() const noexcept { Transform t;const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;if(!r)return t;for(int i=0;i<3;++i){t.position[i]=ReadF32(r+44+i*4);t.scale[i]=ReadF32(r+72+i*4);}for(int i=0;i<4;++i)t.quaternion[i]=ReadF32(r+56+i*4);return t; }
std::uint32_t NodeView::morph_influence_count() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r?ReadU16(r+34):0; }
float NodeView::morph_influence(std::uint32_t target) const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r&&target==0&&morph_influence_count()?ReadF32(r+84):0.0f; }
InstanceView NodeView::instances() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->nodes,index_):nullptr;return r?bundle_->instance(ReadU32(r+36)):InstanceView{}; }

AnchorView::operator bool() const noexcept { return bundle_ != nullptr && index_ < bundle_->anchor_count(); }
std::string_view AnchorView::name() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->anchors,index_):nullptr;return r?bundle_->impl_->String(ReadU32(r+4)):std::string_view{}; }
std::uint32_t AnchorView::asset_index() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->anchors,index_):nullptr;return r?ReadU32(r):kInvalidIndex; }
NodeView AnchorView::node() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->anchors,index_):nullptr;return r?bundle_->node(ReadU32(r+8)):NodeView{}; }

RoleView::operator bool() const noexcept { return bundle_ != nullptr && index_ < bundle_->role_count(); }
std::string_view RoleView::name() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->roles,index_):nullptr;return r?bundle_->impl_->String(ReadU32(r+4)):std::string_view{}; }
std::string_view RoleView::basis() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->roles,index_):nullptr;return r?bundle_->impl_->String(ReadU32(r+16)):std::string_view{}; }
std::uint8_t RoleView::confidence() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->roles,index_):nullptr;return r?r[12]:0; }
std::uint32_t RoleView::asset_index() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->roles,index_):nullptr;return r?ReadU32(r):kInvalidIndex; }
NodeView RoleView::node() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->roles,index_):nullptr;return r?bundle_->node(ReadU32(r+8)):NodeView{}; }

AssetView::operator bool() const noexcept { return bundle_ != nullptr && index_ < bundle_->asset_count(); }
std::string_view AssetView::id() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->assets,index_):nullptr;return r?bundle_->impl_->String(ReadU32(r)):std::string_view{}; }
std::string_view AssetView::name() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->assets,index_):nullptr;return r?bundle_->impl_->String(ReadU32(r+4)):std::string_view{}; }
NodeView AssetView::root() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->assets,index_):nullptr;return r?bundle_->node(ReadU32(r+8)):NodeView{}; }
std::uint32_t AssetView::node_count() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->assets,index_):nullptr;return r?ReadU32(r+16):0; }
NodeView AssetView::node(std::uint32_t localIndex) const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->assets,index_):nullptr;if(!r||localIndex>=node_count())return{};return bundle_->node(ReadU32(r+12)+localIndex); }
std::uint32_t AssetView::anchor_count() const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->assets,index_):nullptr;return r?ReadU32(r+24):0; }
AnchorView AssetView::anchor(std::uint32_t anchorIndex) const noexcept { const auto* r=bundle_?bundle_->impl_->Record(bundle_->impl_->assets,index_):nullptr;if(!r||anchorIndex>=anchor_count())return{};return bundle_->anchor(ReadU32(r+20)+anchorIndex); }
AnchorView AssetView::find_anchor(std::string_view anchorName) const noexcept { for(std::uint32_t i=0;i<anchor_count();++i)if(anchor(i).name()==anchorName)return anchor(i);return{}; }
RoleView AssetView::find_role(std::string_view roleName) const noexcept { if(!bundle_)return{};for(std::uint32_t i=0;i<bundle_->role_count();++i){const RoleView r=bundle_->role(i);if(r.asset_index()==index_&&r.name()==roleName)return r;}return{}; }

} // namespace pelican::assets
