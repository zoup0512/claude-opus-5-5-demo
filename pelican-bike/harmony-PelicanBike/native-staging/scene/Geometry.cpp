#include "Geometry.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <limits>

namespace pelican::scene {
namespace {

constexpr float kChunkLength = 72.0f;

Vec3 normalFromTransform(const Mat4& transform, const Vec3& normal) {
    return transformVector(transform, normal).normalized({0.0f, 1.0f, 0.0f});
}

float valueNoise(int x, int y, int seed) {
    const uint32_t h = hashUint(static_cast<uint32_t>(x) * 0x8da6b343U ^
                                static_cast<uint32_t>(y) * 0xd8163841U ^
                                static_cast<uint32_t>(seed) * 0xcb1ab31fU);
    return static_cast<float>(h & 0xffffU) / 32767.5f - 1.0f;
}

float noise2(float x, float y, int seed) {
    const int ix = static_cast<int>(std::floor(x));
    const int iy = static_cast<int>(std::floor(y));
    const float fx = x - static_cast<float>(ix);
    const float fy = y - static_cast<float>(iy);
    const float sx = fx * fx * (3.0f - 2.0f * fx);
    const float sy = fy * fy * (3.0f - 2.0f * fy);
    const float a = valueNoise(ix, iy, seed);
    const float b = valueNoise(ix + 1, iy, seed);
    const float c = valueNoise(ix, iy + 1, seed);
    const float d = valueNoise(ix + 1, iy + 1, seed);
    return lerp(lerp(a, b, sx), lerp(c, d, sx), sy);
}

float fbm2(float x, float y, int octaves, int seed) {
    float sum = 0.0f;
    float amplitude = 0.5f;
    float frequency = 1.0f;
    for (int octave = 0; octave < octaves; ++octave) {
        sum += amplitude * noise2(x * frequency, y * frequency, seed + octave * 37);
        amplitude *= 0.5f;
        frequency *= 2.03f;
    }
    return sum;
}

Vec3 terrainColor(float x, float z, float height, const Vec3& normal) {
    if (z >= 0.0f) {
        const Vec3 grassA{0.11f, 0.27f, 0.055f};
        const Vec3 grassB{0.36f, 0.55f, 0.12f};
        const Vec3 dry{0.48f, 0.43f, 0.16f};
        const Vec3 dirt{0.34f, 0.27f, 0.14f};
        const Vec3 rock{0.31f, 0.29f, 0.26f};
        const float variation = saturate(fbm2(x * 0.05f, z * 0.05f, 3, 13) + 0.5f);
        Vec3 color = mix(grassA, grassB, variation);
        color = mix(color, dry, smoothstep(9.0f, 22.0f, height) * 0.55f);
        color = mix(color, dirt, 1.0f - smoothstep(3.6f, 6.5f, z));
        color = mix(color, rock, smoothstep(0.86f, 0.70f, normal.y));
        return sanitizeColor(color, 1.0f);
    }
    const float shoreDistance = -z;
    Vec3 color = mix(Vec3{0.28f, 0.25f, 0.20f}, Vec3{0.81f, 0.68f, 0.43f},
                     smoothstep(3.2f, 4.2f, shoreDistance));
    color = mix(color, Vec3{0.48f, 0.36f, 0.22f}, smoothstep(-1.1f, -1.55f, height));
    color = mix(color, Vec3{0.25f, 0.20f, 0.14f}, smoothstep(-1.7f, -2.6f, height));
    const float grain = fbm2(x * 0.3f, z * 0.3f, 2, 29) * 0.08f;
    return sanitizeColor(color + Vec3{grain, grain, grain}, 1.0f);
}

Mat4 basisAlongY(const Vec3& from, const Vec3& to, float radialScaleX, float radialScaleZ) {
    const Vec3 direction = to - from;
    const float length = direction.length();
    const Vec3 y = direction.normalized({0.0f, 1.0f, 0.0f});
    Vec3 helper = std::abs(y.y) > 0.92f ? Vec3{1.0f, 0.0f, 0.0f} : Vec3{0.0f, 1.0f, 0.0f};
    const Vec3 x = cross(helper, y).normalized({1.0f, 0.0f, 0.0f});
    const Vec3 z = cross(y, x).normalized({0.0f, 0.0f, 1.0f});
    Mat4 result;
    result.m[0] = x.x * radialScaleX;
    result.m[1] = x.y * radialScaleX;
    result.m[2] = x.z * radialScaleX;
    result.m[4] = y.x * length;
    result.m[5] = y.y * length;
    result.m[6] = y.z * length;
    result.m[8] = z.x * radialScaleZ;
    result.m[9] = z.y * radialScaleZ;
    result.m[10] = z.z * radialScaleZ;
    result.m[12] = from.x;
    result.m[13] = from.y;
    result.m[14] = from.z;
    return result;
}

CpuMesh makeTriangleFin(const std::array<Vec3, 3>& points, const Vec3& color, bool doubleSided = true) {
    CpuMesh mesh;
    const Vec3 n = cross(points[1] - points[0], points[2] - points[0]).normalized({0.0f, 0.0f, 1.0f});
    mesh.vertices = {
        {points[0], n, color, {0.0f, 0.0f}},
        {points[1], n, color, {1.0f, 0.0f}},
        {points[2], n, color, {0.5f, 1.0f}},
    };
    mesh.indices = {0, 1, 2};
    if (doubleSided) {
        const uint32_t base = static_cast<uint32_t>(mesh.vertices.size());
        mesh.vertices.push_back({points[0], -n, color, {0.0f, 0.0f}});
        mesh.vertices.push_back({points[2], -n, color, {0.5f, 1.0f}});
        mesh.vertices.push_back({points[1], -n, color, {1.0f, 0.0f}});
        mesh.indices.insert(mesh.indices.end(), {base, base + 1, base + 2});
    }
    return mesh;
}

}  // namespace

void CpuMesh::clear() {
    vertices.clear();
    indices.clear();
}

void CpuMesh::append(const CpuMesh& other, const Mat4& transform, const Vec3* colorOverride) {
    const uint32_t base = static_cast<uint32_t>(vertices.size());
    vertices.reserve(vertices.size() + other.vertices.size());
    indices.reserve(indices.size() + other.indices.size());
    for (const Vertex& source : other.vertices) {
        Vertex destination = source;
        destination.position = transformPoint(transform, source.position);
        destination.normal = normalFromTransform(transform, source.normal);
        destination.color = colorOverride ? *colorOverride : source.color;
        vertices.push_back(destination);
    }
    for (uint32_t index : other.indices) {
        indices.push_back(base + index);
    }
}

void CpuMesh::recomputeNormals() {
    for (Vertex& vertex : vertices) {
        vertex.normal = {0.0f, 0.0f, 0.0f};
    }
    for (size_t index = 0; index + 2 < indices.size(); index += 3) {
        Vertex& a = vertices[indices[index]];
        Vertex& b = vertices[indices[index + 1]];
        Vertex& c = vertices[indices[index + 2]];
        const Vec3 face = cross(b.position - a.position, c.position - a.position);
        a.normal += face;
        b.normal += face;
        c.normal += face;
    }
    for (Vertex& vertex : vertices) {
        vertex.normal = vertex.normal.normalized({0.0f, 1.0f, 0.0f});
    }
}

CpuMesh makePlane(float width, float depth, uint32_t xSegments, uint32_t zSegments, const Vec3& color) {
    xSegments = std::max<uint32_t>(1, xSegments);
    zSegments = std::max<uint32_t>(1, zSegments);
    CpuMesh mesh;
    mesh.vertices.reserve(static_cast<size_t>(xSegments + 1) * (zSegments + 1));
    for (uint32_t z = 0; z <= zSegments; ++z) {
        const float vz = static_cast<float>(z) / static_cast<float>(zSegments);
        for (uint32_t x = 0; x <= xSegments; ++x) {
            const float vx = static_cast<float>(x) / static_cast<float>(xSegments);
            mesh.vertices.push_back({{(vx - 0.5f) * width, 0.0f, (vz - 0.5f) * depth},
                                     {0.0f, 1.0f, 0.0f}, color, {vx, vz}});
        }
    }
    const uint32_t row = xSegments + 1;
    for (uint32_t z = 0; z < zSegments; ++z) {
        for (uint32_t x = 0; x < xSegments; ++x) {
            const uint32_t a = z * row + x;
            const uint32_t b = a + row;
            mesh.indices.insert(mesh.indices.end(), {a, b, a + 1, b, b + 1, a + 1});
        }
    }
    return mesh;
}

CpuMesh makeBox(const Vec3& size, const Vec3& color) {
    CpuMesh mesh;
    const Vec3 h = size * 0.5f;
    struct Face {
        Vec3 n;
        std::array<Vec3, 4> p;
    };
    const std::array<Face, 6> faces = {{
        {{1, 0, 0}, {{{h.x, -h.y, -h.z}, {h.x, h.y, -h.z}, {h.x, h.y, h.z}, {h.x, -h.y, h.z}}}},
        {{-1, 0, 0}, {{{-h.x, -h.y, h.z}, {-h.x, h.y, h.z}, {-h.x, h.y, -h.z}, {-h.x, -h.y, -h.z}}}},
        {{0, 1, 0}, {{{-h.x, h.y, -h.z}, {-h.x, h.y, h.z}, {h.x, h.y, h.z}, {h.x, h.y, -h.z}}}},
        {{0, -1, 0}, {{{-h.x, -h.y, h.z}, {-h.x, -h.y, -h.z}, {h.x, -h.y, -h.z}, {h.x, -h.y, h.z}}}},
        {{0, 0, 1}, {{{h.x, -h.y, h.z}, {h.x, h.y, h.z}, {-h.x, h.y, h.z}, {-h.x, -h.y, h.z}}}},
        {{0, 0, -1}, {{{-h.x, -h.y, -h.z}, {-h.x, h.y, -h.z}, {h.x, h.y, -h.z}, {h.x, -h.y, -h.z}}}},
    }};
    for (const Face& face : faces) {
        const uint32_t base = static_cast<uint32_t>(mesh.vertices.size());
        mesh.vertices.push_back({face.p[0], face.n, color, {0, 0}});
        mesh.vertices.push_back({face.p[1], face.n, color, {0, 1}});
        mesh.vertices.push_back({face.p[2], face.n, color, {1, 1}});
        mesh.vertices.push_back({face.p[3], face.n, color, {1, 0}});
        mesh.indices.insert(mesh.indices.end(), {base, base + 1, base + 2, base, base + 2, base + 3});
    }
    return mesh;
}

CpuMesh makeUvSphere(float radius, uint32_t longitudeSegments, uint32_t latitudeSegments, const Vec3& color) {
    longitudeSegments = std::max<uint32_t>(3, longitudeSegments);
    latitudeSegments = std::max<uint32_t>(2, latitudeSegments);
    CpuMesh mesh;
    for (uint32_t y = 0; y <= latitudeSegments; ++y) {
        const float v = static_cast<float>(y) / static_cast<float>(latitudeSegments);
        const float phi = v * kPi;
        for (uint32_t x = 0; x <= longitudeSegments; ++x) {
            const float u = static_cast<float>(x) / static_cast<float>(longitudeSegments);
            const float theta = u * kTau;
            const Vec3 normal{std::sin(phi) * std::cos(theta), std::cos(phi), std::sin(phi) * std::sin(theta)};
            mesh.vertices.push_back({normal * radius, normal, color, {u, v}});
        }
    }
    const uint32_t row = longitudeSegments + 1;
    for (uint32_t y = 0; y < latitudeSegments; ++y) {
        for (uint32_t x = 0; x < longitudeSegments; ++x) {
            const uint32_t a = y * row + x;
            const uint32_t b = a + row;
            mesh.indices.insert(mesh.indices.end(), {a, b, a + 1, b, b + 1, a + 1});
        }
    }
    return mesh;
}

CpuMesh makeCylinder(float radiusBottom, float radiusTop, float height, uint32_t radialSegments,
                     const Vec3& color, bool caps) {
    radialSegments = std::max<uint32_t>(3, radialSegments);
    CpuMesh mesh;
    const float slope = (radiusBottom - radiusTop) / std::max(height, 1.0e-5f);
    for (uint32_t y = 0; y <= 1; ++y) {
        const float v = static_cast<float>(y);
        const float radius = lerp(radiusBottom, radiusTop, v);
        for (uint32_t segment = 0; segment <= radialSegments; ++segment) {
            const float u = static_cast<float>(segment) / static_cast<float>(radialSegments);
            const float angle = u * kTau;
            const Vec3 normal = Vec3{std::cos(angle), slope, std::sin(angle)}.normalized({1, 0, 0});
            mesh.vertices.push_back({{std::cos(angle) * radius, v * height, std::sin(angle) * radius},
                                     normal, color, {u, v}});
        }
    }
    const uint32_t row = radialSegments + 1;
    for (uint32_t segment = 0; segment < radialSegments; ++segment) {
        const uint32_t a = segment;
        const uint32_t b = row + segment;
        mesh.indices.insert(mesh.indices.end(), {a, a + 1, b, b, a + 1, b + 1});
    }
    if (caps) {
        for (int cap = 0; cap < 2; ++cap) {
            const float y = cap == 0 ? 0.0f : height;
            const float radius = cap == 0 ? radiusBottom : radiusTop;
            const Vec3 normal = cap == 0 ? Vec3{0, -1, 0} : Vec3{0, 1, 0};
            const uint32_t center = static_cast<uint32_t>(mesh.vertices.size());
            mesh.vertices.push_back({{0, y, 0}, normal, color, {0.5f, 0.5f}});
            for (uint32_t segment = 0; segment <= radialSegments; ++segment) {
                const float u = static_cast<float>(segment) / static_cast<float>(radialSegments);
                const float angle = u * kTau;
                mesh.vertices.push_back({{std::cos(angle) * radius, y, std::sin(angle) * radius}, normal,
                                         color, {0.5f + 0.5f * std::cos(angle), 0.5f + 0.5f * std::sin(angle)}});
            }
            for (uint32_t segment = 0; segment < radialSegments; ++segment) {
                if (cap == 0) {
                    mesh.indices.insert(mesh.indices.end(), {center, center + segment + 2, center + segment + 1});
                } else {
                    mesh.indices.insert(mesh.indices.end(), {center, center + segment + 1, center + segment + 2});
                }
            }
        }
    }
    return mesh;
}

CpuMesh makeCone(float radius, float height, uint32_t radialSegments, const Vec3& color, bool cap) {
    return makeCylinder(radius, 0.0f, height, radialSegments, color, cap);
}

CpuMesh makeTorus(float majorRadius, float minorRadius, uint32_t majorSegments, uint32_t minorSegments,
                  const Vec3& color) {
    majorSegments = std::max<uint32_t>(3, majorSegments);
    minorSegments = std::max<uint32_t>(3, minorSegments);
    CpuMesh mesh;
    for (uint32_t major = 0; major <= majorSegments; ++major) {
        const float u = static_cast<float>(major) / static_cast<float>(majorSegments);
        const float a = u * kTau;
        const Vec3 center{std::cos(a) * majorRadius, std::sin(a) * majorRadius, 0.0f};
        for (uint32_t minor = 0; minor <= minorSegments; ++minor) {
            const float v = static_cast<float>(minor) / static_cast<float>(minorSegments);
            const float b = v * kTau;
            const Vec3 normal{std::cos(a) * std::cos(b), std::sin(a) * std::cos(b), std::sin(b)};
            mesh.vertices.push_back({center + normal * minorRadius, normal, color, {u, v}});
        }
    }
    const uint32_t row = minorSegments + 1;
    for (uint32_t major = 0; major < majorSegments; ++major) {
        for (uint32_t minor = 0; minor < minorSegments; ++minor) {
            const uint32_t a = major * row + minor;
            const uint32_t b = a + row;
            mesh.indices.insert(mesh.indices.end(), {a, b, a + 1, b, b + 1, a + 1});
        }
    }
    return mesh;
}

CpuMesh makeCylinderBetween(const Vec3& a, const Vec3& b, float radiusA, float radiusB,
                            uint32_t radialSegments, const Vec3& color) {
    CpuMesh base = makeCylinder(1.0f, radiusB / std::max(radiusA, 1.0e-6f), 1.0f, radialSegments, color, true);
    CpuMesh result;
    result.append(base, basisAlongY(a, b, radiusA, radiusA));
    return result;
}

CpuMesh makeRibbon(const std::vector<Vec3>& centerline, float halfWidth, const Vec3& color) {
    CpuMesh mesh;
    if (centerline.size() < 2) {
        return mesh;
    }
    mesh.vertices.reserve(centerline.size() * 2);
    Vec3 previousSide{0.0f, 0.0f, 1.0f};
    for (size_t i = 0; i < centerline.size(); ++i) {
        const Vec3 before = centerline[i == 0 ? 0 : i - 1];
        const Vec3 after = centerline[std::min(i + 1, centerline.size() - 1)];
        const Vec3 tangent = (after - before).normalized({1, 0, 0});
        Vec3 side = cross({0, 1, 0}, tangent).normalized(previousSide);
        if (dot(side, previousSide) < 0.0f) {
            side = -side;
        }
        previousSide = side;
        const float u = static_cast<float>(i) / static_cast<float>(centerline.size() - 1);
        mesh.vertices.push_back({centerline[i] - side * halfWidth, {0, 1, 0}, color, {u, 0}});
        mesh.vertices.push_back({centerline[i] + side * halfWidth, {0, 1, 0}, color, {u, 1}});
    }
    for (uint32_t i = 0; i + 1 < centerline.size(); ++i) {
        const uint32_t a = i * 2;
        mesh.indices.insert(mesh.indices.end(), {a, a + 2, a + 1, a + 1, a + 2, a + 3});
    }
    mesh.recomputeNormals();
    return mesh;
}

CpuMesh makeLoft(uint32_t longitudinalSegments, uint32_t radialSegments,
                 const std::function<Vec3(float)>& center,
                 const std::function<Vec2(float, float)>& section,
                 const std::function<Vec3(float, float)>& color) {
    longitudinalSegments = std::max<uint32_t>(1, longitudinalSegments);
    radialSegments = std::max<uint32_t>(3, radialSegments);
    CpuMesh mesh;
    for (uint32_t i = 0; i <= longitudinalSegments; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(longitudinalSegments);
        const Vec3 c = center(t);
        for (uint32_t j = 0; j <= radialSegments; ++j) {
            const float a = static_cast<float>(j) / static_cast<float>(radialSegments);
            const Vec2 s = section(t, a);
            mesh.vertices.push_back({{c.x, c.y + s.x, c.z + s.y}, {0, 1, 0}, color(t, a), {t, a}});
        }
    }
    const uint32_t row = radialSegments + 1;
    for (uint32_t i = 0; i < longitudinalSegments; ++i) {
        for (uint32_t j = 0; j < radialSegments; ++j) {
            const uint32_t a = i * row + j;
            const uint32_t b = a + row;
            mesh.indices.insert(mesh.indices.end(), {a, a + 1, b, b, a + 1, b + 1});
        }
    }
    mesh.recomputeNormals();
    return mesh;
}

float terrainHeight(double x, float z) {
    const float localX = static_cast<float>(std::remainder(x, 1048576.0));
    if (z >= 0.0f) {
        const float transition = smoothstep(3.8f, 28.0f, z);
        const float big = 2.5f + 17.0f * smoothstep(16.0f, 115.0f, z);
        const float n = fbm2(localX * 0.013f, z * 0.013f, 4, 11);
        const float small = fbm2(localX * 0.085f, z * 0.085f, 2, 71);
        return -0.06f + transition * std::max(0.0f, big * (0.62f + 1.1f * n) + small * 1.3f);
    }
    const float distance = -z;
    const float transition = smoothstep(3.2f, 30.0f, distance);
    const float dunes = fbm2(localX * 0.07f, z * 0.07f, 2, 97) * 0.5f *
                        smoothstep(3.6f, 6.5f, distance) * (1.0f - smoothstep(9.0f, 13.5f, distance));
    return -0.08f - transition * 3.9f + dunes;
}

Vec3 terrainNormal(double x, float z) {
    const float epsilon = 0.6f;
    return Vec3{terrainHeight(x - epsilon, z) - terrainHeight(x + epsilon, z),
                2.0f * epsilon,
                terrainHeight(x, z - epsilon) - terrainHeight(x, z + epsilon)}
        .normalized({0, 1, 0});
}

CpuMesh makeOceanGrid(int quality) {
    const int q = std::clamp(quality, 0, 2);
    const int xSegments = q == 0 ? 72 : (q == 1 ? 120 : 168);
    const int zSegments = q == 0 ? 72 : (q == 1 ? 112 : 156);
    CpuMesh mesh;
    mesh.vertices.reserve(static_cast<size_t>(xSegments + 1) * (zSegments + 1));
    for (int j = 0; j <= zSegments; ++j) {
        const float v = static_cast<float>(j) / static_cast<float>(zSegments);
        const float shaped = std::pow(v, 1.7f);
        const float z = lerp(-8.0f, -520.0f, shaped);
        for (int i = 0; i <= xSegments; ++i) {
            const float u = static_cast<float>(i) / static_cast<float>(xSegments);
            const float x = lerp(-260.0f, 420.0f, u);
            mesh.vertices.push_back({{x, -1.6f, z}, {0, 1, 0}, {1, 1, 1}, {u, v}});
        }
    }
    const uint32_t row = static_cast<uint32_t>(xSegments + 1);
    for (int j = 0; j < zSegments; ++j) {
        for (int i = 0; i < xSegments; ++i) {
            const uint32_t a = static_cast<uint32_t>(j) * row + static_cast<uint32_t>(i);
            const uint32_t b = a + row;
            mesh.indices.insert(mesh.indices.end(), {a, b, a + 1, b, b + 1, a + 1});
        }
    }
    return mesh;
}

CpuMesh makeTerrainChunk(int quality) {
    const int q = std::clamp(quality, 0, 2);
    const int xSegments = q == 0 ? 18 : (q == 1 ? 28 : 36);
    const std::vector<float> zValues = q == 0
        ? std::vector<float>{-34, -24, -16, -11, -7, -4, -3, 3, 4, 8, 14, 24, 40, 64, 96, 136}
        : (q == 1
            ? std::vector<float>{-34, -28, -22, -16, -12, -9, -6, -4, -3.2f, 3.2f, 4, 6, 9, 13, 18, 26, 38, 54, 74, 98, 120, 136}
            : std::vector<float>{-34, -30, -26, -22, -18, -15, -12, -10, -8, -6, -4.5f, -3.3f, 3.3f, 4.2f,
                                 5.4f, 7, 9, 12, 16, 21, 28, 36, 46, 58, 72, 88, 106, 124, 136});
    CpuMesh mesh;
    for (float z : zValues) {
        for (int i = 0; i <= xSegments; ++i) {
            const float u = static_cast<float>(i) / static_cast<float>(xSegments);
            mesh.vertices.push_back({{u * kChunkLength, 0.0f, z}, {0, 1, 0}, {1, 1, 1}, {u, z / 9.0f}});
        }
    }
    const uint32_t row = static_cast<uint32_t>(xSegments + 1);
    for (uint32_t j = 0; j + 1 < zValues.size(); ++j) {
        for (uint32_t i = 0; i < static_cast<uint32_t>(xSegments); ++i) {
            const uint32_t a = j * row + i;
            const uint32_t b = a + row;
            mesh.indices.insert(mesh.indices.end(), {a, b, a + 1, b, b + 1, a + 1});
        }
    }
    fillTerrainChunk(mesh, 0.0f);
    return mesh;
}

void fillTerrainChunk(CpuMesh& mesh, double worldXOrigin) {
    for (Vertex& vertex : mesh.vertices) {
        const double worldX = worldXOrigin + static_cast<double>(vertex.position.x);
        const float localNoiseX = static_cast<float>(std::remainder(worldX, 1048576.0));
        vertex.position.y = terrainHeight(worldX, vertex.position.z);
        vertex.normal = terrainNormal(worldX, vertex.position.z);
        vertex.color = terrainColor(localNoiseX, vertex.position.z, vertex.position.y, vertex.normal);
        vertex.uv = {static_cast<float>(std::remainder(worldX / 9.0, 4096.0)), vertex.position.z / 9.0f};
    }
}

CpuMesh makeTreeMesh() {
    CpuMesh mesh;
    const Vec3 trunkColor{0.20f, 0.095f, 0.035f};
    const Vec3 leafA{0.10f, 0.34f, 0.045f};
    const Vec3 leafB{0.18f, 0.48f, 0.06f};
    mesh.append(makeCylinder(0.18f, 0.12f, 1.8f, 7, trunkColor));
    const CpuMesh sphere = makeUvSphere(1.0f, 8, 5, leafA);
    mesh.append(sphere, compose({0.0f, 2.35f, 0.0f}, {}, {1.25f, 1.0f, 1.1f}));
    mesh.append(sphere, compose({0.62f, 2.0f, 0.3f}, {}, {0.78f, 0.7f, 0.72f}), &leafB);
    mesh.append(sphere, compose({-0.5f, 2.1f, -0.35f}, {}, {0.88f, 0.78f, 0.82f}));
    mesh.append(sphere, compose({0.1f, 2.95f, 0.1f}, {}, {0.75f, 0.7f, 0.72f}), &leafB);
    return mesh;
}

CpuMesh makePineMesh() {
    CpuMesh mesh;
    mesh.append(makeCylinder(0.16f, 0.10f, 1.2f, 6, {0.16f, 0.07f, 0.025f}));
    const std::array<Vec3, 4> layers = {{{1.0f, 1.35f, 1.7f}, {1.75f, 1.05f, 1.5f},
                                         {2.45f, 0.75f, 1.3f}, {3.05f, 0.45f, 1.0f}}};
    for (size_t i = 0; i < layers.size(); ++i) {
        const Vec3 layer = layers[i];
        const Vec3 color = i % 2 == 0 ? Vec3{0.055f, 0.25f, 0.08f} : Vec3{0.075f, 0.32f, 0.10f};
        mesh.append(makeCone(layer.y, layer.z, 8, color), Mat4::translation({0, layer.x, 0}));
    }
    return mesh;
}

CpuMesh makePalmMesh() {
    CpuMesh mesh;
    const Vec3 trunk{0.34f, 0.20f, 0.075f};
    mesh.append(makeCylinderBetween({0, 0, 0}, {0.18f, 1.8f, 0}, 0.2f, 0.17f, 8, trunk));
    mesh.append(makeCylinderBetween({0.18f, 1.8f, 0}, {0.55f, 3.8f, 0.1f}, 0.17f, 0.14f, 8, trunk));
    mesh.append(makeCylinderBetween({0.55f, 3.8f, 0.1f}, {1.1f, 5.6f, 0.2f}, 0.14f, 0.11f, 8, trunk));
    const Vec3 top{1.1f, 5.6f, 0.2f};
    for (int i = 0; i < 9; ++i) {
        const float angle = static_cast<float>(i) / 9.0f * kTau + (i % 2 ? 0.2f : 0.0f);
        const float length = 2.3f + static_cast<float>(i % 3) * 0.35f;
        std::vector<Vec3> center;
        for (int segment = 0; segment <= 10; ++segment) {
            const float t = static_cast<float>(segment) / 10.0f;
            const Vec3 local{std::cos(angle) * length * t,
                             std::sin(t * kPi * 0.75f) * (i % 2 ? 0.55f : 0.25f) - t * t * 1.35f,
                             std::sin(angle) * length * t};
            center.push_back(top + local);
        }
        mesh.append(makeRibbon(center, 0.18f, i % 2 ? Vec3{0.08f, 0.38f, 0.04f} : Vec3{0.12f, 0.48f, 0.05f}));
    }
    return mesh;
}

CpuMesh makeRockMesh() {
    CpuMesh mesh = makeUvSphere(1.0f, 7, 4, {0.34f, 0.32f, 0.29f});
    for (size_t i = 0; i < mesh.vertices.size(); ++i) {
        Vertex& vertex = mesh.vertices[i];
        const float jitter = 0.8f + 0.35f * hash01(static_cast<uint32_t>(i) * 17U + 77U);
        vertex.position.x *= 1.2f * jitter;
        vertex.position.y *= 0.7f * jitter;
        vertex.position.z *= jitter;
    }
    mesh.recomputeNormals();
    return mesh;
}

CpuMesh makeLampMesh() {
    CpuMesh mesh;
    const Vec3 metal{0.055f, 0.075f, 0.09f};
    mesh.append(makeCylinder(0.10f, 0.06f, 5.2f, 8, metal));
    mesh.append(makeCylinderBetween({0, 5.05f, 0}, {0, 5.55f, -0.3f}, 0.045f, 0.045f, 6, metal));
    mesh.append(makeCylinderBetween({0, 5.55f, -0.3f}, {0, 5.48f, -1.15f}, 0.045f, 0.04f, 6, metal));
    mesh.append(makeCylinder(0.26f, 0.12f, 0.22f, 10, metal), compose({0, 5.25f, -1.15f}, {kPi, 0, 0}));
    mesh.append(makeUvSphere(0.16f, 10, 5, {3.5f, 2.0f, 0.7f}), compose({0, 5.18f, -1.15f}, {}, {1, 0.45f, 1}));
    return mesh;
}

CpuMesh makeGuardrailChunk() {
    CpuMesh mesh;
    const Vec3 white{0.72f, 0.74f, 0.72f};
    for (float x = 1.2f; x < kChunkLength; x += 2.4f) {
        mesh.append(makeBox({0.08f, 0.8f, 0.08f}, white), Mat4::translation({x, 0.4f, -3.05f}));
    }
    mesh.append(makeBox({kChunkLength, 0.07f, 0.05f}, white), Mat4::translation({kChunkLength * 0.5f, 0.74f, -3.0f}));
    mesh.append(makeBox({kChunkLength, 0.05f, 0.05f}, white), Mat4::translation({kChunkLength * 0.5f, 0.42f, -3.0f}));
    return mesh;
}

CpuMesh makeLighthouseMesh() {
    CpuMesh mesh;
    mesh.append(makeCone(16.0f, 7.0f, 14, {0.25f, 0.23f, 0.20f}), compose({0, -2.3f, 0}, {kPi, 0, 0}));
    const CpuMesh tower = makeCylinder(1.7f, 1.1f, 13.0f, 18, {0.85f, 0.82f, 0.73f});
    mesh.append(tower, Mat4::translation({0, 4.5f, 0}));
    for (int stripe = 0; stripe < 4; ++stripe) {
        mesh.append(makeCylinder(1.72f - stripe * 0.08f, 1.60f - stripe * 0.08f, 1.1f, 18, {0.55f, 0.02f, 0.015f}),
                    Mat4::translation({0, 6.0f + stripe * 3.0f, 0}));
    }
    mesh.append(makeCylinder(1.7f, 1.7f, 0.25f, 20, {0.04f, 0.05f, 0.06f}), Mat4::translation({0, 17.6f, 0}));
    mesh.append(makeCylinder(0.9f, 0.9f, 1.6f, 16, {4.0f, 2.6f, 0.8f}), Mat4::translation({0, 17.7f, 0}));
    mesh.append(makeCone(1.25f, 1.4f, 16, {0.5f, 0.015f, 0.01f}), Mat4::translation({0, 19.3f, 0}));
    return mesh;
}

CpuMesh makeBoatMesh() {
    CpuMesh mesh;
    mesh.append(makeLoft(14, 10,
        [](float t) { return Vec3{(t - 0.5f) * 6.0f, 0, 0}; },
        [](float t, float a) {
            const float theta = a * kTau;
            const float width = std::pow(std::max(std::sin(kPi * std::pow(t, 0.8f)), 0.0f), 0.6f) * 1.1f + 0.02f;
            const float c = std::cos(theta);
            return Vec2{c > 0.0f ? c * 0.5f : c * 0.9f, std::sin(theta) * width};
        },
        [](float, float a) { return std::cos(a * kTau) > 0.2f ? Vec3{0.85f, 0.85f, 0.8f} : Vec3{0.02f, 0.18f, 0.35f}; }));
    mesh.append(makeCylinder(0.08f, 0.06f, 8.0f, 6, {0.72f, 0.72f, 0.68f}), Mat4::translation({0.3f, 0.2f, 0}));
    mesh.append(makeTriangleFin({Vec3{0.3f, 1.0f, 0.02f}, Vec3{0.3f, 7.9f, 0.02f}, Vec3{3.7f, 1.2f, 0.02f}},
                                {0.95f, 0.72f, 0.15f}));
    mesh.append(makeTriangleFin({Vec3{0.2f, 1.0f, -0.02f}, Vec3{0.2f, 7.0f, -0.02f}, Vec3{-2.2f, 1.2f, -0.02f}},
                                {0.92f, 0.92f, 0.86f}));
    return mesh;
}

CpuMesh makeBirdBodyMesh(bool pelican) {
    CpuMesh mesh;
    const Vec3 white{0.85f, 0.84f, 0.79f};
    mesh.append(makeUvSphere(1.0f, 10, 6, white), compose({}, {}, pelican ? Vec3{0.5f, 0.16f, 0.17f} : Vec3{0.24f, 0.075f, 0.08f}));
    const float headX = pelican ? 0.44f : 0.22f;
    mesh.append(makeUvSphere(pelican ? 0.11f : 0.06f, 8, 5, white), Mat4::translation({headX, 0.05f, 0}));
    mesh.append(makeCone(pelican ? 0.045f : 0.018f, pelican ? 0.55f : 0.09f, 7, {0.95f, 0.42f, 0.06f}),
                compose({headX + (pelican ? 0.04f : 0.02f), 0.04f, 0}, {0, 0, -kPi * 0.5f}));
    return mesh;
}

CpuMesh makeBirdWingMesh(bool pelican) {
    const float length = pelican ? 1.3f : 0.55f;
    const float chord = pelican ? 0.38f : 0.16f;
    CpuMesh wing = makeTriangleFin({Vec3{0, 0, 0}, Vec3{0.15f * length, 0.02f, 0.45f * chord},
                                    Vec3{0.0f, 0.0f, length}}, {0.8f, 0.8f, 0.76f});
    wing.append(makeTriangleFin({Vec3{0.0f, 0.0f, length}, Vec3{0.02f, -0.04f, length * 0.55f},
                                 Vec3{0.0f, 0.0f, 0.0f}}, {0.05f, 0.05f, 0.055f}));
    return wing;
}

namespace {

// Shared bicycle landmarks. Part meshes below are built in the frame's local space so
// each animated node (wheel, crank, steering) can own its own transform.
constexpr float kBikeRearHubX = -0.46f;
constexpr float kBikeFrontHubX = 0.48f;
constexpr float kBikeHubY = 0.3f;
constexpr float kBikeCrankRadius = 0.15f;
const Vec3 kBikeSteeringPivot{0.34f, 0.645f, 0.0f};

// Duplicates a mesh with reversed winding and inverted normals. The character pass culls
// back faces, so open containers need this to read as double-sided.
CpuMesh invertedCopy(const CpuMesh& source) {
    CpuMesh mesh = source;
    for (Vertex& vertex : mesh.vertices) {
        vertex.normal = -vertex.normal;
    }
    for (size_t i = 0; i + 2 < mesh.indices.size(); i += 3) {
        const uint32_t swapped = mesh.indices[i + 1];
        mesh.indices[i + 1] = mesh.indices[i + 2];
        mesh.indices[i + 2] = swapped;
    }
    return mesh;
}

const Vec3 kBikeTireColor{0.012f, 0.012f, 0.014f};
const Vec3 kBikeChromeColor{0.65f, 0.68f, 0.72f};

}  // namespace

CpuMesh makeBicycleWheelMesh() {
    // Centred on the hub so the node transform can spin it in place.
    CpuMesh mesh;
    mesh.append(makeTorus(0.282f, 0.018f, 32, 6, kBikeTireColor));
    mesh.append(makeTorus(0.26f, 0.007f, 32, 5, kBikeChromeColor));
    mesh.append(makeCylinder(0.018f, 0.018f, 0.1f, 10, kBikeChromeColor),
                compose({0, 0, -0.05f}, {kPi * 0.5f, 0, 0}));
    for (int spoke = 0; spoke < 12; ++spoke) {
        const float angle = static_cast<float>(spoke) / 12.0f * kTau;
        mesh.append(makeCylinderBetween({0, 0, 0}, {std::cos(angle) * 0.25f, std::sin(angle) * 0.25f, 0},
                                        0.0016f, 0.0016f, 4, kBikeChromeColor));
    }
    return mesh;
}

CpuMesh makeBicycleCrankMesh() {
    // Crank arms and pedals, centred on the bottom bracket.
    CpuMesh mesh;
    for (float side : {-1.0f, 1.0f}) {
        const Vec3 arm{side * kBikeCrankRadius, 0.0f, side * 0.078f};
        mesh.append(makeCylinderBetween({0, 0, side * 0.078f}, arm, 0.012f, 0.012f, 8, kBikeChromeColor));
        mesh.append(makeBox({0.09f, 0.016f, 0.07f}, kBikeTireColor), Mat4::translation(arm));
    }
    mesh.append(makeTorus(0.1f, 0.005f, 30, 5, kBikeChromeColor), Mat4::translation({0, 0, 0.065f}));
    return mesh;
}

CpuMesh makeBicycleSteeringMesh() {
    // Fork, stem, handlebar and basket, expressed around the head-tube pivot so the
    // node transform can yaw the whole assembly.
    const Vec3 pivot = kBikeSteeringPivot;
    const Vec3 headBottom{0.36f, 0.57f, 0};
    const Vec3 front{kBikeFrontHubX, kBikeHubY, 0};
    const Vec3 forkRoot{headBottom.x - pivot.x, headBottom.y - pivot.y, 0};
    const Vec3 forkTip{front.x - pivot.x, front.y - pivot.y, 0};
    CpuMesh mesh;
    mesh.append(makeCylinderBetween(forkRoot, forkTip, 0.012f, 0.01f, 8, {0.0f, 0.42f, 0.42f}));
    mesh.append(makeCylinderBetween(forkRoot, forkTip, 0.012f, 0.01f, 8, {0.0f, 0.42f, 0.42f}),
                Mat4::translation({0, 0, 0.052f}));
    mesh.append(makeCylinderBetween(forkRoot, forkTip, 0.012f, 0.01f, 8, {0.0f, 0.42f, 0.42f}),
                Mat4::translation({0, 0, -0.052f}));
    mesh.append(makeCylinderBetween({0.34f - pivot.x, 0.73f - pivot.y, 0},
                                    {0.38f - pivot.x, 0.86f - pivot.y, 0},
                                    0.012f, 0.012f, 8, kBikeChromeColor));
    mesh.append(makeCylinderBetween({0.38f - pivot.x, 0.86f - pivot.y, -0.24f},
                                    {0.38f - pivot.x, 0.86f - pivot.y, 0.24f},
                                    0.012f, 0.012f, 8, kBikeChromeColor));
    // Wicker basket: flares outward towards the rim, with a closed floor and a rim ring.
    const Vec3 wicker{0.82f, 0.70f, 0.48f};
    const Vec3 wickerTrim{0.60f, 0.45f, 0.28f};
    const Vec3 basketCenter{0.53f - pivot.x, 0.78f - pivot.y, 0.0f};
    constexpr float kBasketBottomRadius = 0.125f;
    constexpr float kBasketTopRadius = 0.15f;
    constexpr float kBasketHalfHeight = 0.075f;
    // makeCylinder builds from y = 0 upwards, so shift it down to centre on the basket.
    const Mat4 basketBase = Mat4::translation(basketCenter + Vec3{0.0f, -kBasketHalfHeight, 0.0f});
    const CpuMesh basketShell =
        makeCylinder(kBasketBottomRadius, kBasketTopRadius, kBasketHalfHeight * 2.0f, 16, wicker, false);
    mesh.append(basketShell, basketBase);
    mesh.append(invertedCopy(basketShell), basketBase);
    mesh.append(makeCylinder(kBasketBottomRadius, kBasketBottomRadius, 0.012f, 16, wickerTrim, true),
                basketBase);
    mesh.append(makeTorus(kBasketTopRadius, 0.008f, 16, 5, wickerTrim),
                Mat4::translation(basketCenter + Vec3{0.0f, kBasketHalfHeight, 0.0f}) *
                    Mat4::rotationX(kPi * 0.5f));
    // Support strut tying the basket's lower side back to the fork, as in the H5 rig.
    mesh.append(makeCylinderBetween({0.44f - pivot.x, 0.66f - pivot.y, 0},
                                    {0.50f - pivot.x, 0.71f - pivot.y, 0}, 0.006f, 0.006f, 8,
                                    kBikeChromeColor));
    return mesh;
}

CpuMesh makeBicycleFrameMesh() {
    CpuMesh mesh;
    const Vec3 teal{0.0f, 0.42f, 0.42f};
    const Vec3 rear{kBikeRearHubX, kBikeHubY, 0};
    const Vec3 front{kBikeFrontHubX, kBikeHubY, 0};
    const Vec3 bb{-0.06f, 0.25f, 0};
    const Vec3 seat{-0.2f, 0.64f, 0};
    const Vec3 headTop{0.32f, 0.72f, 0};
    const Vec3 headBottom{0.36f, 0.57f, 0};
    for (const auto& tube : std::array<std::pair<Vec3, Vec3>, 7>{{
             {rear, seat}, {rear, bb}, {bb, seat}, {seat, headTop}, {bb, headBottom},
             {headBottom, headTop}, {headBottom, front}}}) {
        mesh.append(makeCylinderBetween(tube.first, tube.second, 0.016f, 0.014f, 8, teal));
    }
    mesh.append(makeUvSphere(1.0f, 10, 5, {0.25f, 0.10f, 0.035f}), compose({-0.235f, 0.72f, 0}, {}, {0.13f, 0.035f, 0.085f}));
    return mesh;
}

CpuMesh makeBicycleMesh() {
    // Kept for host tests: the merged silhouette of every animated bicycle part.
    CpuMesh mesh;
    mesh.append(makeBicycleFrameMesh());
    mesh.append(makeBicycleWheelMesh(), Mat4::translation({kBikeRearHubX, kBikeHubY, 0}));
    mesh.append(makeBicycleWheelMesh(), Mat4::translation({kBikeFrontHubX, kBikeHubY, 0}));
    mesh.append(makeBicycleCrankMesh(), Mat4::translation({-0.06f, 0.25f, 0}));
    mesh.append(makeBicycleSteeringMesh(), Mat4::translation(kBikeSteeringPivot));
    return mesh;
}

CpuMesh makeLimbMesh() {
    // Unit limb: radius 1, spanning y in [-0.5, 0.5], so a segment matrix can scale it.
    CpuMesh mesh = makeCylinder(1.0f, 1.0f, 1.0f, 10, {0.94f, 0.92f, 0.85f});
    CpuMesh centered;
    centered.append(mesh, Mat4::translation({0.0f, -0.5f, 0.0f}));
    return centered;
}

CpuMesh makeShinMesh() {
    // Bare lower leg: same unit limb topology, but the scaly orange of the H5 rig's M.leg.
    CpuMesh mesh = makeCylinder(1.0f, 1.0f, 1.0f, 10, {0.95f, 0.54f, 0.17f});
    CpuMesh centered;
    centered.append(mesh, Mat4::translation({0.0f, -0.5f, 0.0f}));
    return centered;
}

CpuMesh makeJointMesh() {
    return makeUvSphere(1.0f, 12, 8, {0.94f, 0.92f, 0.85f});
}

CpuMesh makeFootMesh() {
    // Webbed foot from the H5 rig's outline: flat plate with three toe lobes, toes towards +X.
    const Vec3 orange{0.95f, 0.54f, 0.17f};
    const std::array<Vec2, 12> outline{{
        {-0.020f, 0.012f}, {0.040f, 0.030f}, {0.100f, 0.050f}, {0.090f, 0.028f},
        {0.105f, 0.022f},  {0.110f, 0.010f}, {0.125f, 0.000f}, {0.110f, -0.010f},
        {0.105f, -0.022f}, {0.090f, -0.028f}, {0.100f, -0.050f}, {0.040f, -0.030f},
    }};
    constexpr float kHalfThickness = 0.006f;
    constexpr uint32_t kCount = static_cast<uint32_t>(outline.size());

    float centerX = 0.0f;
    float centerZ = 0.0f;
    for (const Vec2& point : outline) {
        centerX += point.x;
        centerZ += point.y;
    }
    centerX /= static_cast<float>(kCount);
    centerZ /= static_cast<float>(kCount);

    CpuMesh mesh;
    mesh.vertices.reserve(kCount * 2 + 2);
    for (const Vec2& point : outline) {
        mesh.vertices.push_back({{point.x, kHalfThickness, point.y}, {0.0f, 1.0f, 0.0f}, orange, {0.0f, 0.0f}});
    }
    const uint32_t topCenter = static_cast<uint32_t>(mesh.vertices.size());
    mesh.vertices.push_back({{centerX, kHalfThickness, centerZ}, {0.0f, 1.0f, 0.0f}, orange, {0.5f, 0.5f}});
    for (const Vec2& point : outline) {
        mesh.vertices.push_back({{point.x, -kHalfThickness, point.y}, {0.0f, -1.0f, 0.0f}, orange, {0.0f, 0.0f}});
    }
    const uint32_t bottomCenter = static_cast<uint32_t>(mesh.vertices.size());
    mesh.vertices.push_back({{centerX, -kHalfThickness, centerZ}, {0.0f, -1.0f, 0.0f}, orange, {0.5f, 0.5f}});

    for (uint32_t i = 0; i < kCount; ++i) {
        const uint32_t next = (i + 1) % kCount;
        const uint32_t topI = i;
        const uint32_t topNext = next;
        const uint32_t bottomI = kCount + 1 + i;
        const uint32_t bottomNext = kCount + 1 + next;
        // Winding chosen so the top face looks up and the bottom face looks down.
        mesh.indices.insert(mesh.indices.end(), {topCenter, topI, topNext});
        mesh.indices.insert(mesh.indices.end(), {bottomCenter, bottomNext, bottomI});
        mesh.indices.insert(mesh.indices.end(), {topI, bottomI, bottomNext});
        mesh.indices.insert(mesh.indices.end(), {topI, bottomNext, topNext});
    }
    return mesh;
}

Vec3 catmullRomSample(const std::array<Vec3, 5>& points, float t) {
    const float scaled = clamp(t, 0.0f, 1.0f) * static_cast<float>(points.size() - 1);
    const int segment = std::min(static_cast<int>(scaled), static_cast<int>(points.size()) - 2);
    const float u = scaled - static_cast<float>(segment);
    const auto at = [&points](int index) {
        return points[static_cast<size_t>(std::clamp(index, 0, static_cast<int>(points.size()) - 1))];
    };
    const Vec3 p0 = at(segment - 1);
    const Vec3 p1 = at(segment);
    const Vec3 p2 = at(segment + 1);
    const Vec3 p3 = at(segment + 2);
    const float u2 = u * u;
    const float u3 = u2 * u;
    return (p1 * 2.0f + (p2 - p0) * u + (p0 * 2.0f - p1 * 5.0f + p2 * 4.0f - p3) * u2 +
            (p3 - p0 + (p1 - p2) * 3.0f) * u3) * 0.5f;
}

void buildNeckMesh(CpuMesh& mesh, const std::array<Vec3, 5>& controlPoints,
                   uint32_t tubeSegments, uint32_t radialSegments, const Vec3& color) {
    tubeSegments = std::max<uint32_t>(2, tubeSegments);
    radialSegments = std::max<uint32_t>(3, radialSegments);
    mesh.clear();
    mesh.vertices.reserve(static_cast<size_t>(tubeSegments + 1) * (radialSegments + 1));
    mesh.indices.reserve(static_cast<size_t>(tubeSegments) * radialSegments * 6);

    // Parallel transport along the curve keeps the rings from spinning as the neck bends.
    Vec3 previousNormal{1.0f, 0.0f, 0.0f};
    for (uint32_t i = 0; i <= tubeSegments; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(tubeSegments);
        const Vec3 center = catmullRomSample(controlPoints, t);
        const Vec3 ahead = catmullRomSample(controlPoints, std::min(1.0f, t + 1.0e-2f));
        const Vec3 behind = catmullRomSample(controlPoints, std::max(0.0f, t - 1.0e-2f));
        const Vec3 tangent = (ahead - behind).normalized({0.0f, 1.0f, 0.0f});

        Vec3 normal = previousNormal - tangent * dot(previousNormal, tangent);
        if (normal.lengthSquared() < 1.0e-8f) {
            normal = cross(tangent, Vec3{0.0f, 0.0f, 1.0f});
        }
        normal = normal.normalized({1.0f, 0.0f, 0.0f});
        const Vec3 binormal = cross(tangent, normal).normalized({0.0f, 1.0f, 0.0f});
        previousNormal = normal;

        // Radius profile from the H5 rig: taper to the head, a slight belly mid-neck,
        // then a flare where the skull meets the tube.
        const float taper = lerp(0.085f, 0.05f, smoothstep(0.0f, 0.45f, t));
        const float radius = taper + 0.004f * std::sin(t * kPi) + (t > 0.85f ? (t - 0.85f) * 0.05f : 0.0f);

        for (uint32_t j = 0; j <= radialSegments; ++j) {
            const float angle = static_cast<float>(j) / static_cast<float>(radialSegments) * kTau;
            const Vec3 offset = normal * (std::cos(angle) * radius) + binormal * (std::sin(angle) * radius);
            mesh.vertices.push_back({center + offset, offset.normalized({1.0f, 0.0f, 0.0f}), color,
                                     {t, static_cast<float>(j) / static_cast<float>(radialSegments)}});
        }
    }

    const uint32_t row = radialSegments + 1;
    for (uint32_t i = 0; i < tubeSegments; ++i) {
        for (uint32_t j = 0; j < radialSegments; ++j) {
            const uint32_t a = i * row + j;
            const uint32_t b = a + row;
            mesh.indices.insert(mesh.indices.end(), {a, a + 1, b, b, a + 1, b + 1});
        }
    }
}

CpuMesh makePelicanBodyMesh() {
    CpuMesh mesh = makeUvSphere(1.0f, 20, 12, {0.94f, 0.92f, 0.85f});
    for (Vertex& vertex : mesh.vertices) {
        const float x = vertex.position.x;
        const float y = vertex.position.y;
        const float taper = x < 0.0f ? 1.0f - 0.5f * std::pow(-x, 1.7f) : 1.0f - 0.14f * x * x;
        vertex.position = {x * 0.4f, y * 0.215f * taper, vertex.position.z * 0.2f * taper};
        if (x > 0.2f && y < 0.1f) {
            vertex.color = mix(vertex.color, {0.92f, 0.70f, 0.25f}, 0.38f);
        }
    }
    mesh.recomputeNormals();
    return mesh;
}

CpuMesh makePelicanHeadMesh() {
    CpuMesh mesh;
    mesh.append(makeUvSphere(0.075f, 16, 10, {0.95f, 0.94f, 0.90f}), compose({}, {}, {1.3f, 1.0f, 0.9f}));
    mesh.append(makeUvSphere(0.05f, 12, 8, {0.96f, 0.95f, 0.91f}), compose({0.05f, -0.006f, 0}, {}, {1.45f, 0.85f, 0.85f}));
    for (float side : {-1.0f, 1.0f}) {
        mesh.append(makeUvSphere(0.014f, 8, 6, {0.015f, 0.006f, 0.003f}), Mat4::translation({0.05f, 0.008f, side * 0.06f}));
    }
    mesh.append(makeUvSphere(0.084f, 14, 7, {0.85f, 0.04f, 0.035f}), compose({-0.012f, 0.03f, 0}, {}, {1.32f, 0.65f, 1.08f}));
    return mesh;
}

CpuMesh makePelicanBeakMesh() {
    CpuMesh beak = makeLoft(24, 12,
        [](float t) { return Vec3{t * 0.4f, -0.008f * t - 0.012f * t * t * t, 0}; },
        [](float t, float a) {
            const float theta = a * kTau;
            const float close = std::sqrt(std::max(0.0f, 1.0f - std::pow(t, 10.0f)));
            const float width = (0.034f * (1.0f - 0.55f * t) + 0.007f) * close;
            const float height = (0.017f * (1.0f - 0.5f * t) + 0.004f) * close;
            return Vec2{std::cos(theta) * height, std::sin(theta) * width};
        },
        [](float t, float) { return mix(Vec3{0.94f, 0.34f, 0.18f}, Vec3{0.96f, 0.68f, 0.12f}, smoothstep(0.0f, 0.45f, t)); });
    beak.append(makeLoft(20, 10,
        [](float t) { return Vec3{t * 0.38f, -0.035f - 0.02f * t, 0}; },
        [](float t, float a) {
            const float phi = a * kPi;
            const float bell = std::pow(std::max(std::sin(kPi * std::pow(t, 0.72f)), 0.0f), 1.25f);
            const float close = std::sqrt(std::max(0.0f, 1.0f - std::pow(t, 8.0f)));
            return Vec2{-std::sin(phi) * (0.07f * bell + 0.004f) * close,
                        std::cos(phi) * (0.031f * (1.0f - 0.5f * t) + 0.004f) * close};
        },
        [](float, float) { return Vec3{0.96f, 0.50f, 0.08f}; }));
    return beak;
}

namespace {

// Wing palette: cream arm, pale coverts, dark primaries (real pelicans have black tips).
const Vec3 kWingWhite{0.98f, 0.97f, 0.93f};
const Vec3 kWingPanel{0.88f, 0.87f, 0.84f};
const Vec3 kWingDark{0.16f, 0.16f, 0.19f};

// Scalloped wing panel spanning x in [0, length] with its trailing edge at z = depth.
void appendWingPanel(CpuMesh& mesh, float length, float depth, int scallops, const Vec3& color,
                     const Vec3& offset) {
    const int count = std::max(2, scallops);
    const int steps = count * 2;
    CpuMesh panel;
    for (int i = 0; i <= steps; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(steps);
        const float trailing =
            depth * (0.72f + 0.28f * std::abs(std::sin(t * kPi * static_cast<float>(count))));
        panel.vertices.push_back({{t * length, 0.0f, -0.012f}, {0.0f, 1.0f, 0.0f}, color, {t, 0.0f}});
        panel.vertices.push_back({{t * length, 0.0f, trailing}, {0.0f, 1.0f, 0.0f}, color, {t, 1.0f}});
    }
    for (int i = 0; i < steps; ++i) {
        const uint32_t a = static_cast<uint32_t>(i) * 2;
        panel.indices.insert(panel.indices.end(), {a, a + 1, a + 2, a + 1, a + 3, a + 2});
    }
    panel.recomputeNormals();
    mesh.append(panel, Mat4::translation(offset));
}

// Lens-shaped primaries, matching the H5 rig's feather profile (rounded tip, pointed base).
void appendFeather(CpuMesh& mesh, float length, float width, float yaw, const Vec3& color,
                   const Vec3& offset) {
    constexpr int kStations = 4;
    CpuMesh feather;
    for (int i = 0; i <= kStations; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(kStations);
        // sin(pi * t) can land a hair below zero at the tip, and pow() would return NaN.
        const float edge = std::max(std::sin(kPi * t), 0.0f);
        const float halfWidth = width * 0.5f * std::pow(edge, 0.62f);
        feather.vertices.push_back({{t * length, 0.0f, -halfWidth}, {0.0f, 1.0f, 0.0f}, color, {t, 0.0f}});
        feather.vertices.push_back({{t * length, 0.0f, halfWidth}, {0.0f, 1.0f, 0.0f}, color, {t, 1.0f}});
    }
    for (int i = 0; i < kStations; ++i) {
        const uint32_t a = static_cast<uint32_t>(i) * 2;
        feather.indices.insert(feather.indices.end(), {a, a + 1, a + 2, a + 1, a + 3, a + 2});
    }
    feather.recomputeNormals();
    mesh.append(feather, Mat4::translation(offset) * Mat4::rotationY(yaw));
}

// Tapered arm segment laid along +X; cheap open cylinder keeps the wing inside its triangle budget.
void appendArmSegment(CpuMesh& mesh, float startX, float endX, float radiusStart, float radiusEnd,
                      const Vec3& color) {
    const float length = std::max(endX - startX, 1.0e-4f);
    mesh.append(makeCylinder(radiusStart, radiusEnd, length, 8, color, false),
                compose({startX, 0.0f, 0.0f}, {0.0f, 0.0f, -kPi * 0.5f}));
}

}  // namespace

CpuMesh makePelicanWingMesh() {
    // Built in the spread orientation: the arm runs along +X and the primaries fan at the hand.
    // The rig folds the whole wing by yawing the node, so the resting silhouette lies along the
    // body instead of reading as separate fins.
    constexpr float kHumerus = 0.22f;
    constexpr float kForearm = 0.23f;
    const float handX = kHumerus + kForearm;

    CpuMesh mesh;
    appendArmSegment(mesh, 0.0f, kHumerus, 0.058f, 0.046f, kWingWhite);
    appendArmSegment(mesh, kHumerus, handX, 0.046f, 0.032f, kWingWhite);
    appendArmSegment(mesh, handX, handX + 0.06f, 0.032f, 0.016f, kWingWhite);
    // Wing surfaces: pale coverts over the arm, dark secondaries behind the forearm.
    appendWingPanel(mesh, 0.30f, 0.10f, 3, kWingPanel, {0.06f, -0.004f, -0.004f});
    appendWingPanel(mesh, kForearm, 0.165f, 4, kWingDark, {kHumerus, -0.006f, 0.004f});
    // Primaries: six lens-shaped feathers, longest in the middle, fanning slightly backward.
    const std::array<float, 6> lengths{{0.20f, 0.24f, 0.27f, 0.28f, 0.27f, 0.24f}};
    for (size_t i = 0; i < lengths.size(); ++i) {
        const float yaw = 0.10f - static_cast<float>(i) * 0.045f;
        appendFeather(mesh, lengths[i], 0.05f, yaw, kWingDark,
                      {handX + 0.01f, -0.003f - static_cast<float>(i) * 0.0015f,
                       static_cast<float>(i) * 0.004f});
    }
    return mesh;
}

CpuMesh makeFishMesh() {
    constexpr float length = 0.3f;
    CpuMesh mesh = makeLoft(22, 14,
        [](float t) { return Vec3{(t - 0.5f) * length, std::sin(t * kPi) * 0.004f, 0}; },
        [](float t, float a) {
            const float theta = a * kTau;
            const float s = std::max(std::sin(kPi * std::pow(t, 0.8f)), 0.0f);
            return Vec2{std::cos(theta) * (std::pow(s, 0.85f) * 0.055f + 0.002f),
                        std::sin(theta) * (std::pow(s, 1.1f) * 0.024f + 0.001f)};
        },
        [](float, float a) {
            const float up = std::cos(a * kTau);
            return mix(Vec3{0.75f, 0.84f, 0.88f}, Vec3{0.03f, 0.29f, 0.48f}, smoothstep(-0.2f, 0.6f, up));
        });
    mesh.append(makeTriangleFin({Vec3{-0.14f, 0, 0}, Vec3{-0.235f, 0.07f, 0}, Vec3{-0.225f, -0.07f, 0}},
                                {0.05f, 0.36f, 0.57f}));
    mesh.append(makeTriangleFin({Vec3{0.04f, 0.045f, 0}, Vec3{0.0f, 0.095f, 0}, Vec3{-0.05f, 0.045f, 0}},
                                {0.05f, 0.36f, 0.57f}));
    for (float side : {-1.0f, 1.0f}) {
        mesh.append(makeUvSphere(0.009f, 7, 5, {0.005f, 0.005f, 0.005f}), Mat4::translation({0.1f, 0.012f, side * 0.016f}));
    }
    return mesh;
}

std::vector<InstanceData> buildTreeInstances(int64_t chunkIndex, int quality, bool palms, bool pines) {
    const int q = std::clamp(quality, 0, 2);
    const int target = palms ? (q == 0 ? 2 : 4) : (pines ? (q == 0 ? 8 : (q == 1 ? 15 : 22))
                                                     : (q == 0 ? 10 : (q == 1 ? 20 : 30)));
    const uint64_t chunkBits = static_cast<uint64_t>(chunkIndex);
    Random random(hashUint(static_cast<uint32_t>(chunkBits) ^ static_cast<uint32_t>(chunkBits >> 32U) ^
                           static_cast<uint32_t>(palms ? 211 : pines ? 109 : 17)));
    std::vector<InstanceData> instances;
    instances.reserve(target);
    for (int attempt = 0; attempt < target * 6 && static_cast<int>(instances.size()) < target; ++attempt) {
        const float localX = random.range(0.0f, kChunkLength);
        float z = 0.0f;
        float scaleValue = 1.0f;
        if (palms) {
            z = random.range(-11.5f, -5.2f);
            scaleValue = random.range(0.78f, 1.08f);
        } else if (pines) {
            z = random.range(16.0f, 130.0f);
            scaleValue = random.range(0.85f, 1.55f);
        } else {
            z = random.range(7.0f, 125.0f);
            scaleValue = random.range(0.75f, 1.45f);
        }
        const double worldX = static_cast<double>(chunkIndex) * kChunkLength + localX;
        const Vec3 normal = terrainNormal(worldX, z);
        const float height = terrainHeight(worldX, z);
        if ((!palms && normal.y < (pines ? 0.74f : 0.80f)) || (pines && height < 4.0f)) {
            continue;
        }
        const float yaw = palms ? kPi * 0.5f + random.range(-0.3f, 0.3f) : random.range(0.0f, kTau);
        const Vec3 tint = palms ? Vec3{random.range(0.85f, 1.05f), random.range(0.9f, 1.08f), random.range(0.8f, 1.0f)}
                                : Vec3{random.range(0.82f, 1.06f), random.range(0.85f, 1.08f), random.range(0.78f, 1.0f)};
        instances.push_back({compose({localX, height - 0.04f, z}, {0, yaw, 0},
                                             {scaleValue, scaleValue * random.range(0.86f, 1.18f), scaleValue}), tint,
                             random.next() * kTau});
    }
    return instances;
}

std::vector<InstanceData> buildRockInstances(int64_t chunkIndex, int quality) {
    const int count = std::clamp(quality, 0, 2) == 0 ? 4 : 8;
    const uint64_t chunkBits = static_cast<uint64_t>(chunkIndex);
    Random random(hashUint(static_cast<uint32_t>(chunkBits) ^ static_cast<uint32_t>(chunkBits >> 32U) ^ 77U));
    std::vector<InstanceData> instances;
    instances.reserve(count);
    for (int i = 0; i < count; ++i) {
        const float x = random.range(0.0f, kChunkLength);
        const float z = random.next() < 0.45f ? random.range(-30.0f, -12.0f) : random.range(6.0f, 60.0f);
        const double worldX = static_cast<double>(chunkIndex) * kChunkLength + x;
        const float scaleValue = random.range(0.3f, 1.1f);
        instances.push_back({compose({x, terrainHeight(worldX, z), z}, {random.range(-0.15f, 0.15f), random.range(0, kTau),
                                                                       random.range(-0.15f, 0.15f)},
                                      {scaleValue, scaleValue, scaleValue}),
                             {random.range(0.82f, 1.0f), random.range(0.82f, 1.0f), random.range(0.82f, 1.0f)}, 0});
    }
    return instances;
}

}  // namespace pelican::scene
