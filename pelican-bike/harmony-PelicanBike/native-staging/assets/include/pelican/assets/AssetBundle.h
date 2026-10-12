#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace pelican::assets {

constexpr std::uint32_t kInvalidIndex = 0xffffffffu;

struct ByteSpan {
    const std::uint8_t* data = nullptr;
    std::size_t size = 0;

    constexpr bool empty() const noexcept { return size == 0; }
    constexpr explicit operator bool() const noexcept { return data != nullptr || size == 0; }
};

struct MutableByteSpan {
    std::uint8_t* data = nullptr;
    std::size_t size = 0;
};

template <typename T>
struct ArrayView {
    const T* data = nullptr;
    std::size_t size = 0;

    constexpr bool empty() const noexcept { return size == 0; }
    constexpr const T& operator[](std::size_t index) const noexcept { return data[index]; }
    constexpr const T* begin() const noexcept { return data; }
    constexpr const T* end() const noexcept { return data + size; }
};

struct FloatAttributeView {
    const float* values = nullptr;
    std::uint32_t count = 0;
    std::uint16_t itemSize = 0;
    bool normalized = false;

    constexpr bool empty() const noexcept { return values == nullptr || count == 0; }
    constexpr explicit operator bool() const noexcept { return values != nullptr; }
    constexpr ArrayView<float> flat() const noexcept {
        return {values, static_cast<std::size_t>(count) * itemSize};
    }
};

struct IndexView {
    const std::uint32_t* values = nullptr;
    std::uint32_t count = 0;

    constexpr bool empty() const noexcept { return values == nullptr || count == 0; }
    constexpr explicit operator bool() const noexcept { return values != nullptr; }
};

struct GeometryGroup {
    std::uint32_t start = 0;
    std::uint32_t count = 0;
    std::uint16_t materialIndex = 0;
};

struct Transform {
    std::array<float, 3> position {0.0f, 0.0f, 0.0f};
    std::array<float, 4> quaternion {0.0f, 0.0f, 0.0f, 1.0f};
    std::array<float, 3> scale {1.0f, 1.0f, 1.0f};
};

struct Bounds {
    std::array<float, 3> minimum {};
    std::array<float, 3> maximum {};
    std::array<float, 3> sphereCenter {};
    float sphereRadius = 0.0f;
};

enum class NodeType : std::uint8_t {
    Unknown = 0,
    Group = 1,
    Mesh = 2,
    InstancedMesh = 3,
    Object3D = 4,
    SpotLight = 5,
};

enum class MaterialType : std::uint8_t {
    Unknown = 0,
    MeshBasic = 1,
    MeshStandard = 2,
    MeshPhysical = 3,
};

enum class ColorSpace : std::uint8_t {
    Linear = 0,
    Srgb = 1,
};

enum class TextureSlot : std::uint8_t {
    None = 0,
    Map = 1,
    BumpMap = 2,
};

struct TextureSampler {
    std::uint16_t wrapS = 0;
    std::uint16_t wrapT = 0;
    std::uint16_t minFilter = 0;
    std::uint16_t magFilter = 0;
    bool flipY = false;
    std::array<float, 2> repeat {1.0f, 1.0f};
    std::array<float, 2> offset {0.0f, 0.0f};
    std::array<float, 2> center {0.0f, 0.0f};
    float rotation = 0.0f;
};

struct MaterialProperties {
    MaterialType type = MaterialType::Unknown;
    bool transparent = false;
    bool depthTest = true;
    bool depthWrite = true;
    bool vertexColors = false;
    bool flatShading = false;
    bool wireframe = false;
    std::uint8_t side = 0;
    std::uint16_t blending = 0;
    std::array<float, 3> color {1.0f, 1.0f, 1.0f};
    std::array<float, 3> emissive {};
    float emissiveIntensity = 1.0f;
    float opacity = 1.0f;
    float alphaTest = 0.0f;
    float roughness = 1.0f;
    float metalness = 0.0f;
    float clearcoat = 0.0f;
    float clearcoatRoughness = 0.0f;
    float ior = 1.5f;
    float reflectivity = 0.5f;
    float transmission = 0.0f;
    float thickness = 0.0f;
    float attenuationDistance = -1.0f;
    std::array<float, 3> attenuationColor {1.0f, 1.0f, 1.0f};
    float sheen = 0.0f;
    float sheenRoughness = 1.0f;
    std::array<float, 3> sheenColor {};
    float bumpScale = 1.0f;
    float displacementScale = 1.0f;
    float displacementBias = 0.0f;
    float polygonOffsetFactor = 0.0f;
    float polygonOffsetUnits = 0.0f;
};

struct BundleStats {
    std::uint32_t assetCount = 0;
    std::uint32_t nodeCount = 0;
    std::uint32_t geometryCount = 0;
    std::uint32_t materialCount = 0;
    std::uint32_t textureCount = 0;
    std::uint64_t vertexCount = 0;
    std::uint64_t triangleCount = 0;
    std::uint64_t payloadBytes = 0;
};

class AssetBundle;
class GeometryView;
class TextureView;
class TextureBindingView;
class MaterialView;
class NodeView;
class AssetView;
class AnchorView;
class RoleView;
class InstanceView;

class GeometryView {
public:
    GeometryView() = default;
    explicit operator bool() const noexcept;
    std::uint32_t index() const noexcept { return index_; }
    std::string_view id() const noexcept;
    std::uint32_t vertex_count() const noexcept;
    std::uint32_t index_count() const noexcept;
    std::uint32_t triangle_count() const noexcept;
    std::uint32_t draw_start() const noexcept;
    std::uint32_t draw_count() const noexcept;
    FloatAttributeView position() const noexcept;
    FloatAttributeView normal() const noexcept;
    FloatAttributeView uv() const noexcept;
    FloatAttributeView color() const noexcept;
    IndexView indices() const noexcept;
    std::uint32_t morph_target_count() const noexcept;
    FloatAttributeView morph_position(std::uint32_t target = 0) const noexcept;
    bool morph_targets_relative() const noexcept;
    std::uint32_t group_count() const noexcept;
    GeometryGroup group(std::uint32_t groupIndex) const noexcept;
    Bounds bounds() const noexcept;

private:
    friend class AssetBundle;
    friend class NodeView;
    GeometryView(const AssetBundle* bundle, std::uint32_t index) : bundle_(bundle), index_(index) {}
    const AssetBundle* bundle_ = nullptr;
    std::uint32_t index_ = kInvalidIndex;
};

class TextureView {
public:
    TextureView() = default;
    explicit operator bool() const noexcept;
    std::uint32_t index() const noexcept { return index_; }
    std::string_view id() const noexcept;
    std::string_view name() const noexcept;
    std::uint32_t width() const noexcept;
    std::uint32_t height() const noexcept;
    std::uint32_t row_stride() const noexcept;
    ColorSpace color_space() const noexcept;
    bool flip_y() const noexcept;
    bool premultiply_alpha() const noexcept;
    TextureSampler sampler() const noexcept;
    ByteSpan rgba8() const noexcept;

private:
    friend class AssetBundle;
    friend class TextureBindingView;
    TextureView(const AssetBundle* bundle, std::uint32_t index) : bundle_(bundle), index_(index) {}
    const AssetBundle* bundle_ = nullptr;
    std::uint32_t index_ = kInvalidIndex;
};

class TextureBindingView {
public:
    TextureBindingView() = default;
    explicit operator bool() const noexcept;
    TextureSlot slot() const noexcept;
    TextureView texture() const noexcept;
    TextureSampler sampler() const noexcept;

private:
    friend class MaterialView;
    TextureBindingView(const AssetBundle* bundle, std::uint32_t materialIndex, std::uint32_t relativeOffset)
        : bundle_(bundle), materialIndex_(materialIndex), relativeOffset_(relativeOffset) {}
    const AssetBundle* bundle_ = nullptr;
    std::uint32_t materialIndex_ = kInvalidIndex;
    std::uint32_t relativeOffset_ = 0;
};

class MaterialView {
public:
    MaterialView() = default;
    explicit operator bool() const noexcept;
    std::uint32_t index() const noexcept { return index_; }
    std::string_view id() const noexcept;
    std::string_view name() const noexcept;
    MaterialProperties properties() const noexcept;
    TextureBindingView map() const noexcept;
    TextureBindingView bump_map() const noexcept;

private:
    friend class AssetBundle;
    friend class NodeView;
    MaterialView(const AssetBundle* bundle, std::uint32_t index) : bundle_(bundle), index_(index) {}
    const AssetBundle* bundle_ = nullptr;
    std::uint32_t index_ = kInvalidIndex;
};

class InstanceView {
public:
    InstanceView() = default;
    explicit operator bool() const noexcept;
    std::uint32_t index() const noexcept { return index_; }
    std::uint32_t count() const noexcept;
    ArrayView<float> matrices() const noexcept;
    NodeView node() const noexcept;

private:
    friend class AssetBundle;
    friend class NodeView;
    InstanceView(const AssetBundle* bundle, std::uint32_t index) : bundle_(bundle), index_(index) {}
    const AssetBundle* bundle_ = nullptr;
    std::uint32_t index_ = kInvalidIndex;
};

class NodeView {
public:
    NodeView() = default;
    explicit operator bool() const noexcept;
    std::uint32_t index() const noexcept { return index_; }
    std::string_view id() const noexcept;
    std::string_view name() const noexcept;
    NodeType type() const noexcept;
    bool visible() const noexcept;
    bool cast_shadow() const noexcept;
    bool receive_shadow() const noexcept;
    std::int32_t render_order() const noexcept;
    std::uint32_t asset_index() const noexcept;
    NodeView parent() const noexcept;
    std::uint32_t child_count() const noexcept;
    NodeView child(std::uint32_t childIndex) const noexcept;
    bool has_geometry() const noexcept;
    GeometryView geometry() const noexcept;
    std::uint32_t material_count() const noexcept;
    MaterialView material(std::uint32_t materialIndex) const noexcept;
    Transform local_transform() const noexcept;
    std::uint32_t morph_influence_count() const noexcept;
    float morph_influence(std::uint32_t target = 0) const noexcept;
    InstanceView instances() const noexcept;

private:
    friend class AssetBundle;
    friend class AssetView;
    friend class AnchorView;
    friend class RoleView;
    friend class InstanceView;
    NodeView(const AssetBundle* bundle, std::uint32_t index) : bundle_(bundle), index_(index) {}
    const AssetBundle* bundle_ = nullptr;
    std::uint32_t index_ = kInvalidIndex;
};

class AnchorView {
public:
    AnchorView() = default;
    explicit operator bool() const noexcept;
    std::string_view name() const noexcept;
    std::uint32_t asset_index() const noexcept;
    NodeView node() const noexcept;

private:
    friend class AssetBundle;
    friend class AssetView;
    AnchorView(const AssetBundle* bundle, std::uint32_t index) : bundle_(bundle), index_(index) {}
    const AssetBundle* bundle_ = nullptr;
    std::uint32_t index_ = kInvalidIndex;
};

class RoleView {
public:
    RoleView() = default;
    explicit operator bool() const noexcept;
    std::string_view name() const noexcept;
    std::string_view basis() const noexcept;
    std::uint8_t confidence() const noexcept;
    std::uint32_t asset_index() const noexcept;
    NodeView node() const noexcept;

private:
    friend class AssetBundle;
    friend class AssetView;
    RoleView(const AssetBundle* bundle, std::uint32_t index) : bundle_(bundle), index_(index) {}
    const AssetBundle* bundle_ = nullptr;
    std::uint32_t index_ = kInvalidIndex;
};

class AssetView {
public:
    AssetView() = default;
    explicit operator bool() const noexcept;
    std::uint32_t index() const noexcept { return index_; }
    std::string_view id() const noexcept;
    std::string_view name() const noexcept;
    NodeView root() const noexcept;
    std::uint32_t node_count() const noexcept;
    NodeView node(std::uint32_t localIndex) const noexcept;
    std::uint32_t anchor_count() const noexcept;
    AnchorView anchor(std::uint32_t anchorIndex) const noexcept;
    AnchorView find_anchor(std::string_view anchorName) const noexcept;
    RoleView find_role(std::string_view roleName) const noexcept;

private:
    friend class AssetBundle;
    AssetView(const AssetBundle* bundle, std::uint32_t index) : bundle_(bundle), index_(index) {}
    const AssetBundle* bundle_ = nullptr;
    std::uint32_t index_ = kInvalidIndex;
};

class AssetBundle {
public:
    struct ReadFileCallbacks {
        std::function<bool(std::string_view path, std::uint64_t& size, std::string& error)> GetSize;
        std::function<bool(
            std::string_view path,
            std::uint64_t offset,
            MutableByteSpan destination,
            std::string& error)> ReadAt;
    };

    AssetBundle();
    ~AssetBundle();
    AssetBundle(AssetBundle&&) noexcept;
    AssetBundle& operator=(AssetBundle&&) noexcept;
    AssetBundle(const AssetBundle&) = delete;
    AssetBundle& operator=(const AssetBundle&) = delete;

    // The caller owns memory passed here and must keep it alive until Reset/destruction.
    bool LoadFromMemory(ByteSpan bytes, std::string* error = nullptr);
    // Reads once through the callback and owns that byte vector for the bundle lifetime.
    bool LoadFromReadFile(
        std::string_view path,
        const ReadFileCallbacks& readFile,
        std::string* error = nullptr);
    void Reset() noexcept;

    bool loaded() const noexcept;
    ByteSpan bytes() const noexcept;
    BundleStats stats() const noexcept;
    std::array<std::uint8_t, 32> source_manifest_sha256() const noexcept;

    std::uint32_t asset_count() const noexcept;
    AssetView asset(std::uint32_t index) const noexcept;
    AssetView find_asset(std::string_view id) const noexcept;

    std::uint32_t node_count() const noexcept;
    NodeView node(std::uint32_t index) const noexcept;
    NodeView find_node(std::string_view id) const noexcept;

    std::uint32_t geometry_count() const noexcept;
    GeometryView geometry(std::uint32_t index) const noexcept;
    GeometryView find_geometry(std::string_view id) const noexcept;

    std::uint32_t texture_count() const noexcept;
    TextureView texture(std::uint32_t index) const noexcept;
    TextureView find_texture(std::string_view id) const noexcept;

    std::uint32_t material_count() const noexcept;
    MaterialView material(std::uint32_t index) const noexcept;
    MaterialView find_material(std::string_view id) const noexcept;

    std::uint32_t anchor_count() const noexcept;
    AnchorView anchor(std::uint32_t index) const noexcept;
    std::uint32_t role_count() const noexcept;
    RoleView role(std::uint32_t index) const noexcept;
    std::uint32_t instance_count() const noexcept;
    InstanceView instance(std::uint32_t index) const noexcept;

private:
    friend class GeometryView;
    friend class TextureView;
    friend class TextureBindingView;
    friend class MaterialView;
    friend class NodeView;
    friend class AssetView;
    friend class AnchorView;
    friend class RoleView;
    friend class InstanceView;

    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace pelican::assets
