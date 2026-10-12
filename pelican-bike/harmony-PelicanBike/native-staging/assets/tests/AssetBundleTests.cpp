#include "pelican/assets/AssetBundle.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

using pelican::assets::AssetBundle;
using pelican::assets::ByteSpan;
using pelican::assets::FloatAttributeView;
using pelican::assets::GeometryView;
using pelican::assets::IndexView;
using pelican::assets::MutableByteSpan;

namespace {

int failures = 0;

void Check(bool condition, std::string_view message) {
    if (!condition) {
        ++failures;
        std::cerr << "FAIL: " << message << '\n';
    }
}

std::vector<std::uint8_t> ReadAll(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    if (!file) return {};
    const std::streamsize size = file.tellg();
    if (size <= 0) return {};
    file.seekg(0, std::ios::beg);
    std::vector<std::uint8_t> data(static_cast<std::size_t>(size));
    if (!file.read(reinterpret_cast<char*>(data.data()), size)) return {};
    return data;
}

bool Finite(const FloatAttributeView& view) {
    if (!view) return true;
    for (float value : view.flat()) if (!std::isfinite(value)) return false;
    return true;
}

void CheckGeometry(const GeometryView& geometry) {
    Check(static_cast<bool>(geometry), "geometry view must be valid");
    Check(geometry.position().count == geometry.vertex_count(), "position count must match vertex count");
    Check(geometry.normal().count == geometry.vertex_count(), "normal count must match vertex count");
    Check(!geometry.uv() || geometry.uv().count == geometry.vertex_count(), "uv count must match vertex count");
    Check(!geometry.color() || geometry.color().count == geometry.vertex_count(), "color count must match vertex count");
    Check(Finite(geometry.position()), "positions must be finite");
    Check(Finite(geometry.normal()), "normals must be finite");
    Check(Finite(geometry.uv()), "uv values must be finite");
    Check(Finite(geometry.color()), "colors must be finite");
    Check(Finite(geometry.morph_position()), "morph positions must be finite");
    const IndexView indices = geometry.indices();
    Check(indices.count == geometry.index_count(), "index count must match metadata");
    for (std::uint32_t i = 0; i < indices.count; ++i) {
        Check(indices.values[i] < geometry.vertex_count(), "index must be below vertex count");
    }
    Check(geometry.triangle_count() == geometry.index_count() / 3u, "triangle count must match index count");
    Check(geometry.draw_start() <= geometry.index_count(), "draw start must be in range");
    Check(geometry.draw_count() <= geometry.index_count() - geometry.draw_start(), "draw count must be in range");
    for (std::uint32_t i = 0; i < geometry.group_count(); ++i) {
        const auto group = geometry.group(i);
        Check(group.start <= geometry.index_count(), "group start must be in range");
        Check(group.count <= geometry.index_count() - group.start, "group count must be in range");
    }
    const auto bounds = geometry.bounds();
    for (float value : bounds.minimum) Check(std::isfinite(value), "bounds minimum must be finite");
    for (float value : bounds.maximum) Check(std::isfinite(value), "bounds maximum must be finite");
    for (float value : bounds.sphereCenter) Check(std::isfinite(value), "bounds sphere center must be finite");
    Check(std::isfinite(bounds.sphereRadius) && bounds.sphereRadius >= 0.0f, "bounds sphere radius must be finite and non-negative");
}

void CheckExpectedRoles(const AssetBundle& bundle) {
    const auto bicycle = bundle.find_asset("bicycle");
    const auto pelican = bundle.find_asset("pelican");
    Check(static_cast<bool>(bicycle), "bicycle asset must exist");
    Check(static_cast<bool>(pelican), "pelican asset must exist");
    for (std::string_view role : {
        "wheel.rear.spin", "wheel.front.spin", "front.steer", "crank", "pedal.left", "pedal.right",
    }) {
        Check(static_cast<bool>(bicycle.find_role(role)), std::string("missing bicycle role: ") + std::string(role));
    }
    for (std::string_view role : {
        "body", "head", "jaw", "pouch",
        "wing.left.shoulder", "wing.left.elbow", "wing.left.wrist",
        "wing.right.shoulder", "wing.right.elbow", "wing.right.wrist",
        "leg.left.thigh", "leg.left.knee", "leg.left.shin", "leg.left.ankle", "leg.left.foot",
        "leg.right.thigh", "leg.right.knee", "leg.right.shin", "leg.right.ankle", "leg.right.foot",
    }) {
        Check(static_cast<bool>(pelican.find_role(role)), std::string("missing pelican role: ") + std::string(role));
    }
}

} // namespace

int main(int argc, char** argv) {
    const std::string path = argc > 1 ? argv[1] : "pelican_assets.pak";
    std::vector<std::uint8_t> bytes = ReadAll(path);
    Check(!bytes.empty(), "pack file must be readable");
    if (bytes.empty()) return 1;

    AssetBundle bundle;
    std::string error;
    const bool loaded = bundle.LoadFromMemory({bytes.data(), bytes.size()}, &error);
    Check(loaded, std::string("valid pack must load: ") + error);
    if (!loaded || !bundle.loaded()) {
        std::cerr << "loader error: " << error << '\n';
        return 1;
    }

    const auto stats = bundle.stats();
    Check(stats.assetCount == 3, "expected 3 assets");
    Check(stats.nodeCount == 195, "expected 195 nodes");
    Check(stats.geometryCount == 132, "expected 132 geometries");
    Check(stats.textureCount == 10, "expected 10 textures");
    Check(stats.vertexCount == 35631, "expected 35631 vertices");
    Check(stats.triangleCount == 39814, "expected 39814 triangles");
    Check(bundle.material_count() == 30, "expected 30 materials");
    Check(bundle.instance_count() == 1, "expected one instance stream");

    for (std::uint32_t i = 0; i < bundle.geometry_count(); ++i) CheckGeometry(bundle.geometry(i));
    for (std::uint32_t i = 0; i < bundle.texture_count(); ++i) {
        const auto texture = bundle.texture(i);
        const ByteSpan pixels = texture.rgba8();
        Check(pixels.size == static_cast<std::size_t>(texture.width()) * texture.height() * 4u, "texture RGBA8 slice must match dimensions");
        Check(texture.row_stride() == texture.width() * 4u, "texture row stride must be tightly packed");
    }
    for (std::uint32_t i = 0; i < bundle.node_count(); ++i) {
        const auto node = bundle.node(i);
        const auto transform = node.local_transform();
        for (float value : transform.position) Check(std::isfinite(value), "node position must be finite");
        for (float value : transform.quaternion) Check(std::isfinite(value), "node quaternion must be finite");
        for (float value : transform.scale) Check(std::isfinite(value), "node scale must be finite");
        for (std::uint32_t child = 0; child < node.child_count(); ++child) {
            Check(node.child(child).parent().index() == node.index(), "child/parent relationship must agree");
        }
        if (const auto instances = node.instances()) {
            Check(instances.count() == 101, "bicycle chain must have 101 instances");
            Check(instances.matrices().size == 101u * 16u, "instance matrix slice must be complete");
            for (float value : instances.matrices()) Check(std::isfinite(value), "instance matrices must be finite");
        }
    }
    CheckExpectedRoles(bundle);
    Check(bundle.find_geometry("geometry_107").morph_target_count() == 1, "pouch geometry must retain one morph target");

    AssetBundle callbackBundle;
    AssetBundle::ReadFileCallbacks callbacks;
    callbacks.GetSize = [&bytes](std::string_view requested, std::uint64_t& size, std::string&) {
        if (requested != "pelican_assets.pak") return false;
        size = bytes.size();
        return true;
    };
    callbacks.ReadAt = [&bytes](std::string_view, std::uint64_t offset, MutableByteSpan destination, std::string& callbackError) {
        if (offset > bytes.size() || destination.size > bytes.size() - static_cast<std::size_t>(offset)) {
            callbackError = "callback range out of bounds";
            return false;
        }
        std::copy_n(bytes.data() + static_cast<std::size_t>(offset), destination.size, destination.data);
        return true;
    };
    Check(callbackBundle.LoadFromReadFile("pelican_assets.pak", callbacks, &error), std::string("callback load must succeed: ") + error);
    Check(callbackBundle.stats().nodeCount == 195, "callback-loaded bundle must expose all nodes");

    AssetBundle damaged;
    for (std::size_t cut : {std::size_t{0}, std::size_t{1}, std::size_t{95}, bytes.size() / 2u, bytes.size() - 1u}) {
        Check(!damaged.LoadFromMemory({bytes.data(), cut}, &error), "truncated pack must fail");
    }
    std::vector<std::uint8_t> tampered = bytes;
    tampered[tampered.size() / 2u] ^= 0x5au;
    Check(!damaged.LoadFromMemory({tampered.data(), tampered.size()}, &error), "tampered payload must fail CRC validation");
    tampered = bytes;
    tampered[0] ^= 1u;
    Check(!damaged.LoadFromMemory({tampered.data(), tampered.size()}, &error), "tampered header must fail validation");

    if (failures != 0) {
        std::cerr << failures << " checks failed\n";
        return 1;
    }
    std::cout << "validated 3 assets, 195 nodes, 132 geometries, 10 textures\n";
    std::cout << "35631 vertices, 39814 triangles; truncation and tamper tests passed\n";
    return 0;
}
