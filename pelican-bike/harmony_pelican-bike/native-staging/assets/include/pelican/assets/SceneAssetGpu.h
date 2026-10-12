#pragma once

#include "pelican/assets/AssetBundle.h"

#include <array>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace pelican::assets {

struct Mat4 {
    std::array<float, 16> value {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f,
    };

    static Mat4 Identity() noexcept { return {}; }
    static Mat4 FromTransform(const Transform& transform) noexcept;
};

Mat4 Multiply(const Mat4& left, const Mat4& right) noexcept;

struct GpuMeshHandle {
    std::uint32_t vertexArray = 0;
    std::uint32_t positionBuffer = 0;
    std::uint32_t normalBuffer = 0;
    std::uint32_t uvBuffer = 0;
    std::uint32_t colorBuffer = 0;
    std::uint32_t indexBuffer = 0;
    std::uint32_t morphPositionBuffer = 0;
    std::uint32_t instanceMatrixBuffer = 0;
    std::uint32_t indexCount = 0;
    std::uint32_t instanceCount = 0;
};

struct GpuTextureHandle {
    std::uint32_t texture = 0;
};

struct DrawItem {
    std::uint32_t nodeIndex = kInvalidIndex;
    std::uint32_t geometryIndex = kInvalidIndex;
    std::uint32_t materialIndex = kInvalidIndex;
    std::uint32_t groupStart = 0;
    std::uint32_t groupCount = 0;
    std::int32_t renderOrder = 0;
    Mat4 world {};
    GpuMeshHandle mesh {};
    MaterialView material {};
    TextureView baseColorTexture {};
    TextureView bumpTexture {};
    GpuTextureHandle baseColorGpu {};
    GpuTextureHandle bumpGpu {};
    float morphInfluence = 0.0f;
    bool transparent = false;
    bool doubleSided = false;
};

struct DrawUniforms {
    Mat4 viewProjection {};
    std::function<void(const DrawItem& item)> beforeDraw;
};

struct VertexLocations {
    std::uint32_t position = 0;
    std::uint32_t normal = 1;
    std::uint32_t uv = 2;
    std::uint32_t color = 3;
    std::uint32_t morphPosition = 4;
    std::uint32_t instanceMatrix = 8;
};

class SceneAssetGpu {
public:
    SceneAssetGpu();
    ~SceneAssetGpu();
    SceneAssetGpu(SceneAssetGpu&&) noexcept;
    SceneAssetGpu& operator=(SceneAssetGpu&&) noexcept;
    SceneAssetGpu(const SceneAssetGpu&) = delete;
    SceneAssetGpu& operator=(const SceneAssetGpu&) = delete;

    // Must be called with the destination OpenGL ES 3 context current.
    bool Upload(
        const AssetBundle& bundle,
        const VertexLocations& locations = {},
        std::string* error = nullptr);
    // Must be called while the same GL context/share-group is current.
    void Release() noexcept;

    bool uploaded() const noexcept;
    const AssetBundle* bundle() const noexcept;

    // Rebuilds cached column-major world matrices from the bundle hierarchy.
    // localOverrides may mutate each node's local transform; its bool return is ignored.
    bool UpdateWorldMatrices(
        const std::function<bool(NodeView node, Transform& local)>& localOverrides = {},
        std::string* error = nullptr);

    Mat4 world_matrix(std::uint32_t nodeIndex) const noexcept;
    Mat4 world_matrix(NodeView node) const noexcept;

    // Updates an uploaded InstancedMesh stream, e.g. bicycle chain matrices.
    bool UpdateInstanceMatrices(
        NodeView node,
        ArrayView<float> matrices,
        std::string* error = nullptr);

    std::vector<DrawItem> BuildDrawList(
        AssetView asset,
        const Mat4& assetRoot = Mat4::Identity()) const;

    // Issues glDrawElements/glDrawElementsInstanced. The integration callback owns
    // shader/program/uniform state; SceneAssetGpu owns VAO/VBO/EBO/texture binding.
    void DrawBatch(const std::vector<DrawItem>& items, const DrawUniforms& uniforms = {}) const;

    GpuMeshHandle mesh(std::uint32_t geometryIndex) const noexcept;
    GpuTextureHandle texture(std::uint32_t textureIndex) const noexcept;

private:
    struct Impl;
    Impl* impl_ = nullptr;
};

} // namespace pelican::assets
