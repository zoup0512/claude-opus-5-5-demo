#include "pelican/assets/SceneAssetGpu.h"

#if defined(__OHOS__)
#include <GLES3/gl3.h>
#else
#define GL_GLEXT_PROTOTYPES 1
#include <GLES3/gl3.h>
#endif

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <new>
#include <utility>
#include <vector>

namespace pelican::assets {
namespace {

GLenum WrapMode(std::uint16_t value) noexcept {
    switch (value) {
        case 1000: return GL_REPEAT;
        case 1001: return GL_CLAMP_TO_EDGE;
        case 1002: return GL_MIRRORED_REPEAT;
        default: return GL_REPEAT;
    }
}

GLenum FilterMode(std::uint16_t value) noexcept {
    switch (value) {
        case 1003: return GL_NEAREST;
        case 1004: return GL_NEAREST_MIPMAP_NEAREST;
        case 1005: return GL_NEAREST_MIPMAP_LINEAR;
        case 1006: return GL_LINEAR;
        case 1007: return GL_LINEAR_MIPMAP_NEAREST;
        case 1008: return GL_LINEAR_MIPMAP_LINEAR;
        default: return GL_LINEAR;
    }
}

bool UsesMipmaps(std::uint16_t value) noexcept {
    return value == 1004 || value == 1005 || value == 1007 || value == 1008;
}

bool HasGlError(std::string* error, const char* operation) {
    const GLenum value = glGetError();
    if (value == GL_NO_ERROR) return false;
    if (error != nullptr) {
        *error = std::string(operation) + " failed with GL error 0x";
        constexpr char digits[] = "0123456789abcdef";
        for (int shift = 28; shift >= 0; shift -= 4) error->push_back(digits[(value >> shift) & 0xf]);
    }
    return true;
}

void DeleteMesh(GpuMeshHandle& mesh) noexcept {
    const GLuint buffers[] = {
        mesh.positionBuffer,
        mesh.normalBuffer,
        mesh.uvBuffer,
        mesh.colorBuffer,
        mesh.indexBuffer,
        mesh.morphPositionBuffer,
        mesh.instanceMatrixBuffer,
    };
    glDeleteBuffers(static_cast<GLsizei>(sizeof(buffers) / sizeof(buffers[0])), buffers);
    if (mesh.vertexArray != 0) glDeleteVertexArrays(1, &mesh.vertexArray);
    mesh = {};
}

bool UploadAttribute(
    GLuint vertexArray,
    GLuint& buffer,
    const FloatAttributeView& attribute,
    GLuint location,
    std::string* error) {
    if (!attribute) return true;
    glBindVertexArray(vertexArray);
    glGenBuffers(1, &buffer);
    glBindBuffer(GL_ARRAY_BUFFER, buffer);
    glBufferData(
        GL_ARRAY_BUFFER,
        static_cast<GLsizeiptr>(attribute.flat().size * sizeof(float)),
        attribute.values,
        GL_STATIC_DRAW);
    glEnableVertexAttribArray(location);
    glVertexAttribPointer(location, attribute.itemSize, GL_FLOAT, attribute.normalized ? GL_TRUE : GL_FALSE, 0, nullptr);
    return !HasGlError(error, "geometry attribute upload");
}

bool IsDescendantOf(NodeView node, NodeView root) noexcept {
    if (!node || !root) return false;
    for (NodeView current = node; current; current = current.parent()) {
        if (current.index() == root.index()) return true;
    }
    return false;
}

} // namespace

Mat4 Mat4::FromTransform(const Transform& transform) noexcept {
    const float x = transform.quaternion[0];
    const float y = transform.quaternion[1];
    const float z = transform.quaternion[2];
    const float w = transform.quaternion[3];
    const float x2 = x + x;
    const float y2 = y + y;
    const float z2 = z + z;
    const float xx = x * x2;
    const float xy = x * y2;
    const float xz = x * z2;
    const float yy = y * y2;
    const float yz = y * z2;
    const float zz = z * z2;
    const float wx = w * x2;
    const float wy = w * y2;
    const float wz = w * z2;
    const float sx = transform.scale[0];
    const float sy = transform.scale[1];
    const float sz = transform.scale[2];
    Mat4 result;
    result.value = {
        (1.0f - (yy + zz)) * sx, (xy + wz) * sx, (xz - wy) * sx, 0.0f,
        (xy - wz) * sy, (1.0f - (xx + zz)) * sy, (yz + wx) * sy, 0.0f,
        (xz + wy) * sz, (yz - wx) * sz, (1.0f - (xx + yy)) * sz, 0.0f,
        transform.position[0], transform.position[1], transform.position[2], 1.0f,
    };
    return result;
}

Mat4 Multiply(const Mat4& left, const Mat4& right) noexcept {
    Mat4 result;
    for (int column = 0; column < 4; ++column) {
        for (int row = 0; row < 4; ++row) {
            float value = 0.0f;
            for (int k = 0; k < 4; ++k) {
                value += left.value[k * 4 + row] * right.value[column * 4 + k];
            }
            result.value[column * 4 + row] = value;
        }
    }
    return result;
}

struct SceneAssetGpu::Impl {
    const AssetBundle* bundle = nullptr;
    VertexLocations locations {};
    std::vector<GpuMeshHandle> meshes;
    std::vector<GpuTextureHandle> textures;
    std::vector<Mat4> worlds;

    void Release() noexcept {
        if (bundle != nullptr) {
            for (GpuMeshHandle& mesh : meshes) DeleteMesh(mesh);
            for (GpuTextureHandle& texture : textures) if (texture.texture != 0) glDeleteTextures(1, &texture.texture);
        }
        bundle = nullptr;
        meshes.clear();
        textures.clear();
        worlds.clear();
    }
};

SceneAssetGpu::SceneAssetGpu() : impl_(new (std::nothrow) Impl()) {}
SceneAssetGpu::~SceneAssetGpu() {
    if (impl_ != nullptr) {
        impl_->Release();
        delete impl_;
    }
}
SceneAssetGpu::SceneAssetGpu(SceneAssetGpu&& other) noexcept : impl_(other.impl_) { other.impl_ = nullptr; }
SceneAssetGpu& SceneAssetGpu::operator=(SceneAssetGpu&& other) noexcept {
    if (this != &other) {
        if (impl_ != nullptr) { impl_->Release(); delete impl_; }
        impl_ = other.impl_;
        other.impl_ = nullptr;
    }
    return *this;
}

bool SceneAssetGpu::Upload(const AssetBundle& bundle, const VertexLocations& locations, std::string* error) {
    if (error != nullptr) error->clear();
    if (impl_ == nullptr) {
        if (error != nullptr) *error = "SceneAssetGpu allocation failed";
        return false;
    }
    impl_->Release();
    if (!bundle.loaded()) {
        if (error != nullptr) *error = "AssetBundle is not loaded";
        return false;
    }
    impl_->bundle = &bundle;
    impl_->locations = locations;
    impl_->meshes.resize(bundle.geometry_count());
    impl_->textures.resize(bundle.texture_count());
    impl_->worlds.resize(bundle.node_count());

    for (std::uint32_t i = 0; i < bundle.texture_count(); ++i) {
        const TextureView texture = bundle.texture(i);
        const ByteSpan pixels = texture.rgba8();
        GLuint handle = 0;
        glGenTextures(1, &handle);
        glBindTexture(GL_TEXTURE_2D, handle);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        const TextureSampler sampler = texture.sampler();
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, static_cast<GLint>(WrapMode(sampler.wrapS)));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, static_cast<GLint>(WrapMode(sampler.wrapT)));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, static_cast<GLint>(FilterMode(sampler.minFilter)));
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, static_cast<GLint>(FilterMode(sampler.magFilter)));
        const GLint internalFormat = texture.color_space() == ColorSpace::Srgb ? GL_SRGB8_ALPHA8 : GL_RGBA8;
        glTexImage2D(
            GL_TEXTURE_2D,
            0,
            internalFormat,
            static_cast<GLsizei>(texture.width()),
            static_cast<GLsizei>(texture.height()),
            0,
            GL_RGBA,
            GL_UNSIGNED_BYTE,
            pixels.data);
        if (UsesMipmaps(sampler.minFilter)) glGenerateMipmap(GL_TEXTURE_2D);
        impl_->textures[i].texture = handle;
        if (HasGlError(error, "texture upload")) { impl_->Release(); return false; }
    }

    std::vector<const float*> instanceMatrices(bundle.geometry_count(), nullptr);
    std::vector<std::uint32_t> instanceCounts(bundle.geometry_count(), 0);
    for (std::uint32_t i = 0; i < bundle.node_count(); ++i) {
        const NodeView node = bundle.node(i);
        const InstanceView instances = node.instances();
        if (!node.has_geometry() || !instances) continue;
        const std::uint32_t geometryIndex = node.geometry().index();
        const ArrayView<float> matrices = instances.matrices();
        if (instanceMatrices[geometryIndex] != nullptr && instanceMatrices[geometryIndex] != matrices.data) {
            if (error != nullptr) *error = "one geometry has multiple incompatible instance streams";
            impl_->Release();
            return false;
        }
        instanceMatrices[geometryIndex] = matrices.data;
        instanceCounts[geometryIndex] = instances.count();
    }

    for (std::uint32_t i = 0; i < bundle.geometry_count(); ++i) {
        const GeometryView geometry = bundle.geometry(i);
        GpuMeshHandle& mesh = impl_->meshes[i];
        glGenVertexArrays(1, &mesh.vertexArray);
        glBindVertexArray(mesh.vertexArray);
        if (!UploadAttribute(mesh.vertexArray, mesh.positionBuffer, geometry.position(), locations.position, error) ||
            !UploadAttribute(mesh.vertexArray, mesh.normalBuffer, geometry.normal(), locations.normal, error) ||
            !UploadAttribute(mesh.vertexArray, mesh.uvBuffer, geometry.uv(), locations.uv, error) ||
            !UploadAttribute(mesh.vertexArray, mesh.colorBuffer, geometry.color(), locations.color, error) ||
            !UploadAttribute(mesh.vertexArray, mesh.morphPositionBuffer, geometry.morph_position(), locations.morphPosition, error)) {
            impl_->Release();
            return false;
        }
        const IndexView indices = geometry.indices();
        glGenBuffers(1, &mesh.indexBuffer);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, mesh.indexBuffer);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, static_cast<GLsizeiptr>(indices.count * sizeof(std::uint32_t)), indices.values, GL_STATIC_DRAW);
        mesh.indexCount = indices.count;

        if (instanceMatrices[i] != nullptr && instanceCounts[i] > 0) {
            glGenBuffers(1, &mesh.instanceMatrixBuffer);
            glBindBuffer(GL_ARRAY_BUFFER, mesh.instanceMatrixBuffer);
            glBufferData(
                GL_ARRAY_BUFFER,
                static_cast<GLsizeiptr>(instanceCounts[i]) * 16 * sizeof(float),
                instanceMatrices[i],
                GL_DYNAMIC_DRAW);
            for (GLuint column = 0; column < 4; ++column) {
                const GLuint location = locations.instanceMatrix + column;
                glEnableVertexAttribArray(location);
                glVertexAttribPointer(
                    location,
                    4,
                    GL_FLOAT,
                    GL_FALSE,
                    16 * static_cast<GLsizei>(sizeof(float)),
                    reinterpret_cast<const void*>(static_cast<std::uintptr_t>(column * 4 * sizeof(float))));
                glVertexAttribDivisor(location, 1);
            }
            mesh.instanceCount = instanceCounts[i];
        }
        if (HasGlError(error, "mesh upload")) { impl_->Release(); return false; }
    }
    glBindVertexArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    return UpdateWorldMatrices({}, error);
}

void SceneAssetGpu::Release() noexcept { if (impl_ != nullptr) impl_->Release(); }
bool SceneAssetGpu::uploaded() const noexcept { return impl_ != nullptr && impl_->bundle != nullptr; }
const AssetBundle* SceneAssetGpu::bundle() const noexcept { return impl_ != nullptr ? impl_->bundle : nullptr; }

bool SceneAssetGpu::UpdateWorldMatrices(
    const std::function<bool(NodeView node, Transform& local)>& localOverrides,
    std::string* error) {
    if (error != nullptr) error->clear();
    if (!uploaded()) {
        if (error != nullptr) *error = "SceneAssetGpu is not uploaded";
        return false;
    }
    std::vector<std::uint8_t> state(impl_->bundle->node_count(), 0);
    std::function<bool(std::uint32_t)> visit = [&](std::uint32_t index) {
        if (state[index] == 2) return true;
        if (state[index] == 1) {
            if (error != nullptr) *error = "node hierarchy contains a cycle";
            return false;
        }
        state[index] = 1;
        const NodeView node = impl_->bundle->node(index);
        Transform local = node.local_transform();
        if (localOverrides) localOverrides(node, local);
        Mat4 world = Mat4::FromTransform(local);
        const NodeView parent = node.parent();
        if (parent) {
            if (!visit(parent.index())) return false;
            world = Multiply(impl_->worlds[parent.index()], world);
        }
        impl_->worlds[index] = world;
        state[index] = 2;
        return true;
    };
    for (std::uint32_t i = 0; i < impl_->bundle->node_count(); ++i) if (!visit(i)) return false;
    return true;
}

Mat4 SceneAssetGpu::world_matrix(std::uint32_t nodeIndex) const noexcept {
    return uploaded() && nodeIndex < impl_->worlds.size() ? impl_->worlds[nodeIndex] : Mat4::Identity();
}
Mat4 SceneAssetGpu::world_matrix(NodeView node) const noexcept { return node ? world_matrix(node.index()) : Mat4::Identity(); }

bool SceneAssetGpu::UpdateInstanceMatrices(NodeView node, ArrayView<float> matrices, std::string* error) {
    if (error != nullptr) error->clear();
    if (!uploaded() || !node || !node.has_geometry() || node.instances().count() == 0) {
        if (error != nullptr) *error = "node is not an uploaded InstancedMesh";
        return false;
    }
    const std::uint32_t count = node.instances().count();
    if (matrices.data == nullptr || matrices.size != static_cast<std::size_t>(count) * 16u) {
        if (error != nullptr) *error = "instance matrix array must contain count * 16 floats";
        return false;
    }
    GpuMeshHandle& gpu = impl_->meshes[node.geometry().index()];
    if (gpu.instanceMatrixBuffer == 0) {
        if (error != nullptr) *error = "instance matrix buffer was not created";
        return false;
    }
    glBindBuffer(GL_ARRAY_BUFFER, gpu.instanceMatrixBuffer);
    glBufferSubData(
        GL_ARRAY_BUFFER,
        0,
        static_cast<GLsizeiptr>(matrices.size * sizeof(float)),
        matrices.data);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    return !HasGlError(error, "instance matrix update");
}

std::vector<DrawItem> SceneAssetGpu::BuildDrawList(AssetView asset, const Mat4& assetRoot) const {
    std::vector<DrawItem> items;
    if (!uploaded() || !asset) return items;
    const NodeView root = asset.root();
    for (std::uint32_t localIndex = 0; localIndex < asset.node_count(); ++localIndex) {
        const NodeView node = asset.node(localIndex);
        if (!node.visible() || !node.has_geometry() || !IsDescendantOf(node, root)) continue;
        const GeometryView geometry = node.geometry();
        const GpuMeshHandle gpuMesh = mesh(geometry.index());
        const Mat4 world = Multiply(assetRoot, world_matrix(node));
        const std::uint32_t groupCount = geometry.group_count();
        const std::uint32_t drawParts = groupCount == 0 ? 1u : groupCount;
        for (std::uint32_t part = 0; part < drawParts; ++part) {
            GeometryGroup group;
            group.start = geometry.draw_start();
            group.count = geometry.draw_count();
            group.materialIndex = 0;
            if (groupCount != 0) group = geometry.group(part);
            if (group.materialIndex >= node.material_count()) continue;
            const MaterialView material = node.material(group.materialIndex);
            const MaterialProperties properties = material.properties();
            const TextureBindingView map = material.map();
            const TextureBindingView bump = material.bump_map();
            DrawItem item;
            item.nodeIndex = node.index();
            item.geometryIndex = geometry.index();
            item.materialIndex = material.index();
            item.groupStart = group.start;
            item.groupCount = group.count;
            item.renderOrder = node.render_order();
            item.world = world;
            item.mesh = gpuMesh;
            item.material = material;
            item.baseColorTexture = map.texture();
            item.bumpTexture = bump.texture();
            item.baseColorGpu = item.baseColorTexture ? texture(item.baseColorTexture.index()) : GpuTextureHandle{};
            item.bumpGpu = item.bumpTexture ? texture(item.bumpTexture.index()) : GpuTextureHandle{};
            item.morphInfluence = node.morph_influence();
            item.transparent = properties.transparent || properties.opacity < 1.0f;
            item.doubleSided = properties.side == 2;
            items.push_back(item);
        }
    }
    std::stable_sort(items.begin(), items.end(), [](const DrawItem& left, const DrawItem& right) {
        if (left.renderOrder != right.renderOrder) return left.renderOrder < right.renderOrder;
        if (left.transparent != right.transparent) return !left.transparent;
        if (left.materialIndex != right.materialIndex) return left.materialIndex < right.materialIndex;
        return left.geometryIndex < right.geometryIndex;
    });
    return items;
}

void SceneAssetGpu::DrawBatch(const std::vector<DrawItem>& items, const DrawUniforms& uniforms) const {
    if (!uploaded()) return;
    for (const DrawItem& item : items) {
        if (uniforms.beforeDraw) uniforms.beforeDraw(item);
        const MaterialProperties properties = item.material.properties();
        if (properties.depthTest) glEnable(GL_DEPTH_TEST); else glDisable(GL_DEPTH_TEST);
        glDepthMask(properties.depthWrite ? GL_TRUE : GL_FALSE);
        if (item.transparent) {
            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        } else {
            glDisable(GL_BLEND);
        }
        if (item.doubleSided) glDisable(GL_CULL_FACE); else glEnable(GL_CULL_FACE);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, item.baseColorGpu.texture);
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, item.bumpGpu.texture);
        glBindVertexArray(item.mesh.vertexArray);
        const void* offset = reinterpret_cast<const void*>(static_cast<std::uintptr_t>(item.groupStart) * sizeof(std::uint32_t));
        if (item.mesh.instanceCount > 0) {
            glDrawElementsInstanced(
                GL_TRIANGLES,
                static_cast<GLsizei>(item.groupCount),
                GL_UNSIGNED_INT,
                offset,
                static_cast<GLsizei>(item.mesh.instanceCount));
        } else {
            glDrawElements(GL_TRIANGLES, static_cast<GLsizei>(item.groupCount), GL_UNSIGNED_INT, offset);
        }
    }
    glBindVertexArray(0);
    glActiveTexture(GL_TEXTURE0);
}

GpuMeshHandle SceneAssetGpu::mesh(std::uint32_t geometryIndex) const noexcept {
    return uploaded() && geometryIndex < impl_->meshes.size() ? impl_->meshes[geometryIndex] : GpuMeshHandle{};
}
GpuTextureHandle SceneAssetGpu::texture(std::uint32_t textureIndex) const noexcept {
    return uploaded() && textureIndex < impl_->textures.size() ? impl_->textures[textureIndex] : GpuTextureHandle{};
}

} // namespace pelican::assets
