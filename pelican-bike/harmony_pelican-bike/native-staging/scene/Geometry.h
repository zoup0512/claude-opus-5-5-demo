#pragma once

#include "SceneMath.h"

#include <array>
#include <cstdint>
#include <functional>
#include <vector>

namespace pelican::scene {

struct Vertex {
    Vec3 position{};
    Vec3 normal{0.0f, 1.0f, 0.0f};
    Vec3 color{1.0f, 1.0f, 1.0f};
    Vec2 uv{};
};

struct CpuMesh {
    std::vector<Vertex> vertices;
    std::vector<uint32_t> indices;

    bool empty() const { return vertices.empty() || indices.empty(); }
    void clear();
    void append(const CpuMesh& other, const Mat4& transform = Mat4::identity(), const Vec3* colorOverride = nullptr);
    void recomputeNormals();
};

struct InstanceData {
    Mat4 transform{};
    Vec3 color{1.0f, 1.0f, 1.0f};
    float parameter = 0.0f;
};

CpuMesh makePlane(float width, float depth, uint32_t xSegments = 1, uint32_t zSegments = 1,
                  const Vec3& color = {1.0f, 1.0f, 1.0f});
CpuMesh makeBox(const Vec3& size, const Vec3& color = {1.0f, 1.0f, 1.0f});
CpuMesh makeUvSphere(float radius, uint32_t longitudeSegments, uint32_t latitudeSegments,
                     const Vec3& color = {1.0f, 1.0f, 1.0f});
CpuMesh makeCylinder(float radiusBottom, float radiusTop, float height, uint32_t radialSegments,
                     const Vec3& color = {1.0f, 1.0f, 1.0f}, bool caps = true);
CpuMesh makeCone(float radius, float height, uint32_t radialSegments,
                 const Vec3& color = {1.0f, 1.0f, 1.0f}, bool cap = true);
CpuMesh makeTorus(float majorRadius, float minorRadius, uint32_t majorSegments, uint32_t minorSegments,
                  const Vec3& color = {1.0f, 1.0f, 1.0f});
CpuMesh makeCylinderBetween(const Vec3& a, const Vec3& b, float radiusA, float radiusB,
                            uint32_t radialSegments, const Vec3& color);
CpuMesh makeRibbon(const std::vector<Vec3>& centerline, float halfWidth, const Vec3& color);
CpuMesh makeLoft(uint32_t longitudinalSegments, uint32_t radialSegments,
                 const std::function<Vec3(float)>& center,
                 const std::function<Vec2(float, float)>& section,
                 const std::function<Vec3(float, float)>& color);

CpuMesh makeOceanGrid(int quality);
CpuMesh makeTerrainChunk(int quality);
void fillTerrainChunk(CpuMesh& mesh, double worldXOrigin);
float terrainHeight(double x, float z);
Vec3 terrainNormal(double x, float z);

CpuMesh makeTreeMesh();
CpuMesh makePineMesh();
CpuMesh makePalmMesh();
CpuMesh makeRockMesh();
CpuMesh makeLampMesh();
CpuMesh makeGuardrailChunk();
CpuMesh makeLighthouseMesh();
CpuMesh makeBoatMesh();
CpuMesh makeBirdBodyMesh(bool pelican);
CpuMesh makeBirdWingMesh(bool pelican);
CpuMesh makeBicycleMesh();
CpuMesh makeBicycleFrameMesh();
CpuMesh makeBicycleWheelMesh();
CpuMesh makeBicycleCrankMesh();
CpuMesh makeBicycleSteeringMesh();
CpuMesh makeLimbMesh();
CpuMesh makeShinMesh();
CpuMesh makeJointMesh();
CpuMesh makeFootMesh();
// Catmull-Rom station along a 5-point neck curve, t in [0, 1].
Vec3 catmullRomSample(const std::array<Vec3, 5>& points, float t);
// Rebuilds a neck tube in place so a per-frame skinning pass reuses the buffer capacity.
void buildNeckMesh(CpuMesh& mesh, const std::array<Vec3, 5>& controlPoints,
                   uint32_t tubeSegments, uint32_t radialSegments, const Vec3& color);
CpuMesh makePelicanBodyMesh();
CpuMesh makePelicanHeadMesh();
CpuMesh makePelicanBeakMesh();
CpuMesh makePelicanWingMesh();
CpuMesh makeFishMesh();

std::vector<InstanceData> buildTreeInstances(int64_t chunkIndex, int quality, bool palms, bool pines);
std::vector<InstanceData> buildRockInstances(int64_t chunkIndex, int quality);

}  // namespace pelican::scene
