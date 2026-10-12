#include "asset_character_renderer.h"

#include "engine_types.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>
#include <sstream>
#include <string_view>
#include <utility>

#if defined(PELICAN_SCENE_MOCK_GLES)
#include "host/MockGles3.h"
#else
#include <GLES3/gl3.h>
#endif

namespace pelican::integration {
namespace {

constexpr const char* kAssetVertexShader = R"GLSL(#version 300 es
precision highp float;
layout(location=0) in vec3 aPosition;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec2 aUv;
layout(location=3) in vec3 aColor;
layout(location=4) in vec3 aMorphPosition;
layout(location=8) in vec4 iM0;
layout(location=9) in vec4 iM1;
layout(location=10) in vec4 iM2;
layout(location=11) in vec4 iM3;
uniform mat4 uModel;
uniform mat4 uViewProjection;
uniform float uMorph;
uniform int uInstanced;
out vec3 vWorld;
out vec3 vNormal;
out vec3 vColor;
out vec2 vUv;
void main() {
    vec3 position = aPosition + aMorphPosition * uMorph;
    mat4 instanceMatrix = uInstanced != 0 ? mat4(iM0, iM1, iM2, iM3) : mat4(1.0);
    mat4 model = uModel * instanceMatrix;
    vec4 world = model * vec4(position, 1.0);
    vWorld = world.xyz;
    vNormal = normalize(mat3(model) * aNormal);
    vColor = aColor;
    vUv = aUv;
    gl_Position = uViewProjection * world;
}
)GLSL";

constexpr const char* kAssetFragmentShader = R"GLSL(#version 300 es
precision highp float;
in vec3 vWorld;
in vec3 vNormal;
in vec3 vColor;
in vec2 vUv;
layout(location=0) out vec4 fragColor;
uniform vec3 uCamera;
uniform vec3 uSunDir;
uniform vec3 uSunColor;
uniform vec3 uFogColor;
uniform vec3 uBaseColor;
uniform vec3 uEmissive;
uniform float uAmbient;
uniform float uRoughness;
uniform float uFogDensity;
uniform float uOpacity;
uniform int uUseTexture;
uniform int uFlipY;
uniform sampler2D uTexture;
void main() {
    vec3 normal = normalize(vNormal);
    vec3 viewDirection = normalize(uCamera - vWorld);
    vec3 lightDirection = normalize(uSunDir);
    float diffuse = max(dot(normal, lightDirection), 0.0);
    vec3 halfVector = normalize(lightDirection + viewDirection);
    float specularPower = mix(96.0, 8.0, clamp(uRoughness, 0.0, 1.0));
    float specular = pow(max(dot(normal, halfVector), 0.0), specularPower) *
                     (1.0 - clamp(uRoughness, 0.0, 1.0)) * 0.35;
    vec2 uv = vec2(vUv.x, uFlipY != 0 ? 1.0 - vUv.y : vUv.y);
    vec4 texel = uUseTexture != 0 ? texture(uTexture, uv) : vec4(1.0);
    vec3 vertexColor = max(vColor, vec3(0.0001));
    vec3 base = vertexColor * uBaseColor * texel.rgb;
    vec3 color = base * (uAmbient + diffuse * uSunColor) + uSunColor * specular + uEmissive;
    float distanceToCamera = length(vWorld - uCamera);
    float fog = 1.0 - exp(-pow(max(distanceToCamera * uFogDensity, 0.0), 1.35));
    color = mix(color, uFogColor, clamp(fog, 0.0, 1.0));
    fragColor = vec4(clamp(color, 0.0, 48.0), clamp(uOpacity * texel.a, 0.0, 1.0));
}
)GLSL";

GLuint CompileShader(GLenum type, const char* source, std::string* error)
{
    GLuint shader = glCreateShader(type);
    if (shader == 0) {
        if (error != nullptr) *error = "glCreateShader failed";
        return 0;
    }
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint compiled = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compiled);
    if (compiled == GL_TRUE) return shader;
    GLint length = 0;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);
    std::string log(static_cast<std::size_t>(std::max(length, 1)), '\0');
    GLsizei written = 0;
    glGetShaderInfoLog(shader, static_cast<GLsizei>(log.size()), &written, log.data());
    if (error != nullptr) *error = log;
    glDeleteShader(shader);
    return 0;
}

assets::Mat4 ToAssetMatrix(const scene::Mat4& matrix) noexcept
{
    assets::Mat4 result;
    result.value = matrix.m;
    return result;
}

assets::Mat4 RootMatrix(float scale = 1.8F) noexcept
{
    scene::Mat4 root = scene::Mat4::scale({scale, scale, scale});
    return ToAssetMatrix(root);
}

void MultiplyQuaternion(std::array<float, 4>& value, float x, float y, float z, float w) noexcept
{
    const float ax = value[0];
    const float ay = value[1];
    const float az = value[2];
    const float aw = value[3];
    value = {
        aw * x + ax * w + ay * z - az * y,
        aw * y - ax * z + ay * w + az * x,
        aw * z + ax * y - ay * x + az * w,
        aw * w - ax * x - ay * y - az * z,
    };
}

void RotateX(assets::Transform& transform, float angle) noexcept
{
    const float half = angle * 0.5F;
    MultiplyQuaternion(transform.quaternion, std::sin(half), 0.0F, 0.0F, std::cos(half));
}

void RotateY(assets::Transform& transform, float angle) noexcept
{
    const float half = angle * 0.5F;
    MultiplyQuaternion(transform.quaternion, 0.0F, std::sin(half), 0.0F, std::cos(half));
}

void RotateZ(assets::Transform& transform, float angle) noexcept
{
    const float half = angle * 0.5F;
    MultiplyQuaternion(transform.quaternion, 0.0F, 0.0F, std::sin(half), std::cos(half));
}

GLint Uniform(GLuint program, const char* name) noexcept
{
    return glGetUniformLocation(program, name);
}

void SetMat4(GLuint program, const char* name, const assets::Mat4& matrix) noexcept
{
    const GLint location = Uniform(program, name);
    if (location >= 0) glUniformMatrix4fv(location, 1, GL_FALSE, matrix.value.data());
}

void SetVec3(GLuint program, const char* name, float x, float y, float z) noexcept
{
    const GLint location = Uniform(program, name);
    if (location >= 0) glUniform3f(location, x, y, z);
}

void SetFloat(GLuint program, const char* name, float value) noexcept
{
    const GLint location = Uniform(program, name);
    if (location >= 0) glUniform1f(location, value);
}

void SetInt(GLuint program, const char* name, int value) noexcept
{
    const GLint location = Uniform(program, name);
    if (location >= 0) glUniform1i(location, value);
}

std::uint32_t RoleNodeIndex(assets::AssetView asset, std::string_view name) noexcept
{
    const assets::RoleView role = asset.find_role(name);
    return role ? role.node().index() : assets::kInvalidIndex;
}

} // namespace

AssetCharacterRenderer::AssetCharacterRenderer() = default;

AssetCharacterRenderer::~AssetCharacterRenderer()
{
    // GPU release must be explicit while the owning EGL context is current.
    DestroyProgram();
}

bool AssetCharacterRenderer::LoadPak(const std::vector<std::uint8_t>& bytes, std::string* error)
{
    assets::AssetBundle::ReadFileCallbacks reader;
    reader.GetSize = [&bytes](std::string_view path, std::uint64_t& size, std::string& callbackError) {
        if (path != "pelican_assets.pak" || bytes.empty()) {
            callbackError = "pelican_assets.pak bytes are unavailable";
            return false;
        }
        size = bytes.size();
        return true;
    };
    reader.ReadAt = [&bytes](std::string_view path, std::uint64_t offset,
                             assets::MutableByteSpan destination, std::string& callbackError) {
        if (path != "pelican_assets.pak" || offset > bytes.size() ||
            destination.size > bytes.size() - static_cast<std::size_t>(offset)) {
            callbackError = "pelican_assets.pak read range is invalid";
            return false;
        }
        std::memcpy(destination.data, bytes.data() + static_cast<std::size_t>(offset), destination.size);
        return true;
    };
    return LoadPakWithReader(reader, error);
}

bool AssetCharacterRenderer::LoadPakWithReader(
    const assets::AssetBundle::ReadFileCallbacks& reader, std::string* error)
{
    lastError_.clear();
    bundle_.Reset();
    pakBytes_ = 0;
    std::string loadError;
    if (!bundle_.LoadFromReadFile("pelican_assets.pak", reader, &loadError)) {
        lastError_ = loadError.empty() ? "AssetBundle load failed" : loadError;
        if (error != nullptr) *error = lastError_;
        return false;
    }
    pakBytes_ = bundle_.bytes().size;
    if (!ResolveAssetsAndRoles(&loadError)) {
        bundle_.Reset();
        lastError_ = loadError;
        if (error != nullptr) *error = lastError_;
        return false;
    }
    if (error != nullptr) error->clear();
    return true;
}

void AssetCharacterRenderer::ResetBundle() noexcept
{
    bicycleDraws_.clear();
    pelicanDraws_.clear();
    fishDraws_.clear();
    fishWorldBases_.clear();
    bicycle_ = {};
    pelican_ = {};
    fish_ = {};
    roles_ = {};
    pakBytes_ = 0;
    bundle_.Reset();
}

bool AssetCharacterRenderer::ResolveAssetsAndRoles(std::string* error)
{
    bicycle_ = bundle_.find_asset("bicycle");
    pelican_ = bundle_.find_asset("pelican");
    fish_ = bundle_.find_asset("fish");
    if (!bicycle_ || !pelican_ || !fish_) {
        if (error != nullptr) *error = "PAK must contain bicycle, pelican and fish assets";
        return false;
    }

    roles_.bicycleRoot = bicycle_.root().index();
    roles_.rearWheel = RoleNodeIndex(bicycle_, "wheel.rear.spin");
    roles_.frontWheel = RoleNodeIndex(bicycle_, "wheel.front.spin");
    roles_.frontSteer = RoleNodeIndex(bicycle_, "front.steer");
    roles_.crank = RoleNodeIndex(bicycle_, "crank");
    roles_.pedalLeft = RoleNodeIndex(bicycle_, "pedal.left");
    roles_.pedalRight = RoleNodeIndex(bicycle_, "pedal.right");
    roles_.pelicanRoot = pelican_.root().index();
    roles_.body = RoleNodeIndex(pelican_, "body");
    roles_.head = RoleNodeIndex(pelican_, "head");
    roles_.jaw = RoleNodeIndex(pelican_, "jaw");
    roles_.pouch = RoleNodeIndex(pelican_, "pouch");
    roles_.wingLeftShoulder = RoleNodeIndex(pelican_, "wing.left.shoulder");
    roles_.wingLeftElbow = RoleNodeIndex(pelican_, "wing.left.elbow");
    roles_.wingLeftWrist = RoleNodeIndex(pelican_, "wing.left.wrist");
    roles_.wingRightShoulder = RoleNodeIndex(pelican_, "wing.right.shoulder");
    roles_.wingRightElbow = RoleNodeIndex(pelican_, "wing.right.elbow");
    roles_.wingRightWrist = RoleNodeIndex(pelican_, "wing.right.wrist");
    roles_.legLeftThigh = RoleNodeIndex(pelican_, "leg.left.thigh");
    roles_.legLeftKnee = RoleNodeIndex(pelican_, "leg.left.knee");
    roles_.legLeftShin = RoleNodeIndex(pelican_, "leg.left.shin");
    roles_.legLeftAnkle = RoleNodeIndex(pelican_, "leg.left.ankle");
    roles_.legLeftFoot = RoleNodeIndex(pelican_, "leg.left.foot");
    roles_.legRightThigh = RoleNodeIndex(pelican_, "leg.right.thigh");
    roles_.legRightKnee = RoleNodeIndex(pelican_, "leg.right.knee");
    roles_.legRightShin = RoleNodeIndex(pelican_, "leg.right.shin");
    roles_.legRightAnkle = RoleNodeIndex(pelican_, "leg.right.ankle");
    roles_.legRightFoot = RoleNodeIndex(pelican_, "leg.right.foot");

    const std::array<std::uint32_t, 10> required{{
        roles_.rearWheel, roles_.frontWheel, roles_.frontSteer, roles_.crank,
        roles_.body, roles_.head, roles_.jaw,
        roles_.wingLeftShoulder, roles_.wingRightShoulder, roles_.legLeftThigh,
    }};
    if (std::any_of(required.begin(), required.end(),
                    [](std::uint32_t value) { return value == assets::kInvalidIndex; })) {
        if (error != nullptr) *error = "PAK stable role table is incomplete";
        return false;
    }
    return true;
}

bool AssetCharacterRenderer::Upload(std::string* error)
{
    lastError_.clear();
    if (!bundle_.loaded()) {
        lastError_ = "AssetBundle is not loaded";
        if (error != nullptr) *error = lastError_;
        return false;
    }
    ReleaseGpu();
    assets::VertexLocations locations;
    locations.position = 0;
    locations.normal = 1;
    locations.uv = 2;
    locations.color = 3;
    locations.morphPosition = 4;
    locations.instanceMatrix = 8;
    std::string uploadError;
    if (!gpu_.Upload(bundle_, locations, &uploadError)) {
        lastError_ = uploadError;
        if (error != nullptr) *error = lastError_;
        return false;
    }
    if (!CreateProgram(&uploadError)) {
        gpu_.Release();
        lastError_ = uploadError;
        if (error != nullptr) *error = lastError_;
        return false;
    }
    if (!UpdateWorldMatrices(&uploadError)) {
        ReleaseGpu();
        lastError_ = uploadError;
        if (error != nullptr) *error = lastError_;
        return false;
    }
    bicycleDraws_ = gpu_.BuildDrawList(bicycle_, RootMatrix());
    pelicanDraws_ = gpu_.BuildDrawList(pelican_, RootMatrix());
    fishDraws_ = gpu_.BuildDrawList(fish_, assets::Mat4::Identity());
    fishWorldBases_.clear();
    fishWorldBases_.reserve(fishDraws_.size());
    for (const assets::DrawItem& item : fishDraws_) {
        fishWorldBases_.push_back(item.world);
    }
    if (bicycleDraws_.empty() || pelicanDraws_.empty() || fishDraws_.empty()) {
        ReleaseGpu();
        lastError_ = "PAK GPU draw lists are empty";
        if (error != nullptr) *error = lastError_;
        return false;
    }
    if (error != nullptr) error->clear();
    return true;
}

void AssetCharacterRenderer::ReleaseGpu() noexcept
{
    bicycleDraws_.clear();
    pelicanDraws_.clear();
    fishDraws_.clear();
    fishWorldBases_.clear();
    gpu_.Release();
    DestroyProgram();
    drawCalls_ = 0;
    triangles_ = 0;
}

bool AssetCharacterRenderer::CreateProgram(std::string* error)
{
    DestroyProgram();
    std::string shaderError;
    const GLuint vertex = CompileShader(GL_VERTEX_SHADER, kAssetVertexShader, &shaderError);
    if (vertex == 0) {
        if (error != nullptr) *error = "asset vertex shader: " + shaderError;
        return false;
    }
    const GLuint fragment = CompileShader(GL_FRAGMENT_SHADER, kAssetFragmentShader, &shaderError);
    if (fragment == 0) {
        glDeleteShader(vertex);
        if (error != nullptr) *error = "asset fragment shader: " + shaderError;
        return false;
    }
    program_ = glCreateProgram();
    glAttachShader(program_, vertex);
    glAttachShader(program_, fragment);
    glLinkProgram(program_);
    glDeleteShader(vertex);
    glDeleteShader(fragment);
    GLint linked = GL_FALSE;
    glGetProgramiv(program_, GL_LINK_STATUS, &linked);
    if (linked != GL_TRUE) {
        GLint length = 0;
        glGetProgramiv(program_, GL_INFO_LOG_LENGTH, &length);
        std::string log(static_cast<std::size_t>(std::max(length, 1)), '\0');
        GLsizei written = 0;
        glGetProgramInfoLog(program_, static_cast<GLsizei>(log.size()), &written, log.data());
        if (error != nullptr) *error = "asset program link: " + log;
        DestroyProgram();
        return false;
    }
    return glGetError() == GL_NO_ERROR;
}

void AssetCharacterRenderer::DestroyProgram() noexcept
{
    if (program_ != 0) {
        glDeleteProgram(program_);
        program_ = 0;
    }
}

void AssetCharacterRenderer::Update(const GameSnapshot& snapshot,
                                    const EngineSettings& settings, float mouthOpen)
{
    snapshot_ = snapshot;
    settings_ = settings;
    mouthOpen_ = std::clamp(mouthOpen, 0.0F, 1.0F);
    if (!gpu_.uploaded()) return;
    std::string error;
    if (!UpdateWorldMatrices(&error)) {
        lastError_ = error;
        return;
    }
    bicycleDraws_ = gpu_.BuildDrawList(bicycle_, RootMatrix());
    pelicanDraws_ = gpu_.BuildDrawList(pelican_, RootMatrix());
}

bool AssetCharacterRenderer::UpdateWorldMatrices(std::string* error)
{
    const float wheel = static_cast<float>(snapshot_.wheelAngle);
    const float crank = static_cast<float>(snapshot_.crankAngle);
    const float steer = static_cast<float>(snapshot_.steer);
    const float trick = static_cast<float>(snapshot_.trickBlend);
    const float airborne = snapshot_.airborne ? 1.0F : 0.0F;
    const float time = static_cast<float>(std::remainder(snapshot_.time, 10000.0));
    const float bob = -std::abs(std::sin(crank)) * 0.012F * (snapshot_.pedaling ? 1.0F : 0.0F);
    const float flap = std::sin(time * 8.5F) * 0.55F * airborne +
                       std::sin(time * 2.6F) * 0.32F * trick;
    const float pedalLeft = std::sin(crank) * 0.45F;
    const float pedalRight = std::sin(crank + scene::kPi) * 0.45F;

    return gpu_.UpdateWorldMatrices(
        [&](assets::NodeView node, assets::Transform& local) {
            const std::uint32_t index = node.index();
            if (IsRole(index, roles_.bicycleRoot)) {
                local.scale = {1.0F, 1.0F, 1.0F};
            } else if (IsRole(index, roles_.rearWheel) || IsRole(index, roles_.frontWheel)) {
                RotateZ(local, -wheel);
            } else if (IsRole(index, roles_.frontSteer)) {
                RotateY(local, steer * 0.35F);
            } else if (IsRole(index, roles_.crank)) {
                RotateZ(local, -crank);
            } else if (IsRole(index, roles_.pedalLeft)) {
                RotateZ(local, pedalLeft);
            } else if (IsRole(index, roles_.pedalRight)) {
                RotateZ(local, pedalRight);
            } else if (IsRole(index, roles_.body)) {
                local.position[1] += bob + airborne * 0.025F;
                RotateX(local, std::sin(crank) * 0.035F * (snapshot_.pedaling ? 1.0F : 0.0F));
                RotateZ(local, trick * 0.14F);
            } else if (IsRole(index, roles_.head)) {
                local.position[1] -= bob * 0.75F;
                RotateY(local, std::sin(time * 0.35F) * 0.12F);
                RotateZ(local, -0.05F);
            } else if (IsRole(index, roles_.jaw)) {
                RotateZ(local, -mouthOpen_ * 0.55F);
            } else if (IsRole(index, roles_.wingLeftShoulder)) {
                RotateX(local, flap);
                RotateZ(local, -1.25F * (1.0F - trick));
            } else if (IsRole(index, roles_.wingRightShoulder)) {
                RotateX(local, -flap);
                RotateZ(local, 1.25F * (1.0F - trick));
            } else if (IsRole(index, roles_.wingLeftElbow) || IsRole(index, roles_.wingLeftWrist)) {
                RotateX(local, flap * 0.45F);
                RotateZ(local, -trick * 0.35F);
            } else if (IsRole(index, roles_.wingRightElbow) || IsRole(index, roles_.wingRightWrist)) {
                RotateX(local, -flap * 0.45F);
                RotateZ(local, trick * 0.35F);
            } else if (IsRole(index, roles_.legLeftThigh) || IsRole(index, roles_.legLeftKnee) ||
                       IsRole(index, roles_.legLeftShin) || IsRole(index, roles_.legLeftAnkle) ||
                       IsRole(index, roles_.legLeftFoot)) {
                RotateZ(local, pedalLeft);
            } else if (IsRole(index, roles_.legRightThigh) || IsRole(index, roles_.legRightKnee) ||
                       IsRole(index, roles_.legRightShin) || IsRole(index, roles_.legRightAnkle) ||
                       IsRole(index, roles_.legRightFoot)) {
                RotateZ(local, pedalRight);
            }
            return false;
        },
        error);
}

bool AssetCharacterRenderer::Draw(const scene::ExternalCharacterContext& context)
{
    if (!ready() || program_ == 0) return false;

    drawCalls_ = 0;
    triangles_ = 0;
    const scene::Mat4 viewProjectionScene = context.projection * context.view;
    const assets::Mat4 viewProjection = ToAssetMatrix(viewProjectionScene);

    glUseProgram(program_);
    SetMat4(program_, "uViewProjection", viewProjection);
    SetVec3(program_, "uCamera", context.cameraPosition.x, context.cameraPosition.y,
            context.cameraPosition.z);
    SetVec3(program_, "uSunDir", context.sunDirection.x, context.sunDirection.y,
            context.sunDirection.z);
    SetVec3(program_, "uSunColor", context.sunColor.x, context.sunColor.y,
            context.sunColor.z);
    SetVec3(program_, "uFogColor", context.fogColor.x, context.fogColor.y,
            context.fogColor.z);
    SetFloat(program_, "uAmbient", context.ambient);
    SetFloat(program_, "uFogDensity", context.fogDensity);
    SetInt(program_, "uTexture", 0);

    auto drawList = [&](const std::vector<assets::DrawItem>& items) {
        assets::DrawUniforms uniforms;
        uniforms.beforeDraw = [&](const assets::DrawItem& item) {
            glUseProgram(program_);
            SetMat4(program_, "uModel", item.world);
            const assets::MaterialProperties material = item.material.properties();
            SetVec3(program_, "uBaseColor", material.color[0], material.color[1], material.color[2]);
            SetVec3(program_, "uEmissive",
                    material.emissive[0] * material.emissiveIntensity,
                    material.emissive[1] * material.emissiveIntensity,
                    material.emissive[2] * material.emissiveIntensity);
            SetFloat(program_, "uRoughness", material.roughness);
            SetFloat(program_, "uOpacity", material.opacity);
            SetFloat(program_, "uMorph",
                     item.nodeIndex == roles_.pouch ? mouthOpen_ : item.morphInfluence);
            SetInt(program_, "uInstanced", item.mesh.instanceCount > 0 ? 1 : 0);
            SetInt(program_, "uUseTexture", item.baseColorGpu.texture != 0 ? 1 : 0);
            SetInt(program_, "uFlipY", item.baseColorTexture && item.baseColorTexture.flip_y() ? 1 : 0);
            ++drawCalls_;
            const std::uint64_t instances = std::max<std::uint32_t>(item.mesh.instanceCount, 1U);
            triangles_ += static_cast<std::uint64_t>(item.groupCount / 3U) * instances;
        };
        gpu_.DrawBatch(items, uniforms);
    };

    drawList(bicycleDraws_);
    drawList(pelicanDraws_);

    // PAK fish replaces the staging low-poly visual fish. Draw active deterministic
    // coregame fish at their rider-relative positions.
    for (std::size_t index = 0; index < snapshot_.activeFishCount; ++index) {
        const FishSnapshot& fish = snapshot_.fish[index];
        if (fish.caught && fish.scale <= 0.02F) continue;
        const scene::Mat4 root = scene::compose(
            {fish.localPosition.x, fish.localPosition.y, fish.localPosition.z},
            {0.0F, std::sin(fish.phase) * 0.25F, std::sin(fish.phase * 1.7F) * 0.2F},
            {fish.scale, fish.scale, fish.scale});
        const assets::Mat4 rootMatrix = ToAssetMatrix(root);
        for (std::size_t itemIndex = 0; itemIndex < fishDraws_.size(); ++itemIndex) {
            fishDraws_[itemIndex].world = assets::Multiply(rootMatrix, fishWorldBases_[itemIndex]);
        }
        drawList(fishDraws_);
    }

    glUseProgram(0);
    glDepthMask(GL_TRUE);
    glDisable(GL_BLEND);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_CULL_FACE);
    return glGetError() == GL_NO_ERROR;
}

bool AssetCharacterRenderer::IsRole(std::uint32_t nodeIndex, std::uint32_t roleIndex) const noexcept
{
    return roleIndex != assets::kInvalidIndex && nodeIndex == roleIndex;
}

std::uint32_t AssetCharacterRenderer::buffers() const noexcept
{
    const assets::BundleStats stats = bundle_.stats();
    // Up to position/normal/uv/color/index/morph per geometry plus one instance stream.
    return stats.geometryCount * 6U + bundle_.instance_count();
}

} // namespace pelican::integration
