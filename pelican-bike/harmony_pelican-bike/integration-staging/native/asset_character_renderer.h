#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "RenderScene.h"
#include "pelican/assets/AssetBundle.h"
#include "pelican/assets/SceneAssetGpu.h"
#include "pelican/simulation.hpp"

namespace pelican::integration {

struct EngineSettings;

class AssetCharacterRenderer final {
public:
    AssetCharacterRenderer();
    ~AssetCharacterRenderer();

    AssetCharacterRenderer(const AssetCharacterRenderer&) = delete;
    AssetCharacterRenderer& operator=(const AssetCharacterRenderer&) = delete;

    // CPU-side, context-free load. Bytes are copied into AssetBundle-owned storage
    // through ReadFile callbacks, so the caller may release its vector afterwards.
    bool LoadPak(const std::vector<std::uint8_t>& bytes, std::string* error = nullptr);
    bool LoadPakWithReader(const assets::AssetBundle::ReadFileCallbacks& reader,
                           std::string* error = nullptr);
    void ResetBundle() noexcept;

    // GL lifecycle; destination context must be current.
    bool Upload(std::string* error = nullptr);
    void ReleaseGpu() noexcept;

    void Update(const GameSnapshot& snapshot, const EngineSettings& settings,
                float mouthOpen);
    bool Draw(const scene::ExternalCharacterContext& context);

    bool bundleLoaded() const noexcept { return bundle_.loaded(); }
    bool gpuUploaded() const noexcept { return gpu_.uploaded(); }
    bool ready() const noexcept { return bundleLoaded() && gpuUploaded(); }
    const std::string& lastError() const noexcept { return lastError_; }
    std::size_t pakBytes() const noexcept { return pakBytes_; }
    assets::BundleStats bundleStats() const noexcept { return bundle_.stats(); }
    std::uint64_t drawCalls() const noexcept { return drawCalls_; }
    std::uint64_t triangles() const noexcept { return triangles_; }
    std::uint32_t textures() const noexcept { return bundle_.stats().textureCount; }
    std::uint32_t buffers() const noexcept;
    std::uint32_t vaos() const noexcept { return bundle_.stats().geometryCount; }
    bool musicEnabledForTest() const noexcept { return false; }

private:
    struct Roles {
        std::uint32_t bicycleRoot = assets::kInvalidIndex;
        std::uint32_t rearWheel = assets::kInvalidIndex;
        std::uint32_t frontWheel = assets::kInvalidIndex;
        std::uint32_t frontSteer = assets::kInvalidIndex;
        std::uint32_t crank = assets::kInvalidIndex;
        std::uint32_t pedalLeft = assets::kInvalidIndex;
        std::uint32_t pedalRight = assets::kInvalidIndex;
        std::uint32_t pelicanRoot = assets::kInvalidIndex;
        std::uint32_t body = assets::kInvalidIndex;
        std::uint32_t head = assets::kInvalidIndex;
        std::uint32_t jaw = assets::kInvalidIndex;
        std::uint32_t pouch = assets::kInvalidIndex;
        std::uint32_t wingLeftShoulder = assets::kInvalidIndex;
        std::uint32_t wingLeftElbow = assets::kInvalidIndex;
        std::uint32_t wingLeftWrist = assets::kInvalidIndex;
        std::uint32_t wingRightShoulder = assets::kInvalidIndex;
        std::uint32_t wingRightElbow = assets::kInvalidIndex;
        std::uint32_t wingRightWrist = assets::kInvalidIndex;
        std::uint32_t legLeftThigh = assets::kInvalidIndex;
        std::uint32_t legLeftKnee = assets::kInvalidIndex;
        std::uint32_t legLeftShin = assets::kInvalidIndex;
        std::uint32_t legLeftAnkle = assets::kInvalidIndex;
        std::uint32_t legLeftFoot = assets::kInvalidIndex;
        std::uint32_t legRightThigh = assets::kInvalidIndex;
        std::uint32_t legRightKnee = assets::kInvalidIndex;
        std::uint32_t legRightShin = assets::kInvalidIndex;
        std::uint32_t legRightAnkle = assets::kInvalidIndex;
        std::uint32_t legRightFoot = assets::kInvalidIndex;
    };

    bool ResolveAssetsAndRoles(std::string* error);
    bool CreateProgram(std::string* error);
    void DestroyProgram() noexcept;
    bool UpdateWorldMatrices(std::string* error);
    bool IsRole(std::uint32_t nodeIndex, std::uint32_t roleIndex) const noexcept;

    assets::AssetBundle bundle_{};
    assets::SceneAssetGpu gpu_{};
    assets::AssetView bicycle_{};
    assets::AssetView pelican_{};
    assets::AssetView fish_{};
    Roles roles_{};
    std::vector<assets::DrawItem> bicycleDraws_{};
    std::vector<assets::DrawItem> pelicanDraws_{};
    std::vector<assets::DrawItem> fishDraws_{};
    std::vector<assets::Mat4> fishWorldBases_{};
    GameSnapshot snapshot_{};
    EngineSettings settings_{};
    float mouthOpen_ = 0.0F;
    unsigned int program_ = 0;
    std::string lastError_{};
    std::size_t pakBytes_ = 0;
    std::uint64_t drawCalls_ = 0;
    std::uint64_t triangles_ = 0;
};

} // namespace pelican::integration
