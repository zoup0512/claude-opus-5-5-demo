#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace pelican::scene {

constexpr float kPi = 3.14159265358979323846f;
constexpr float kTau = kPi * 2.0f;

inline float clamp(float v, float lo, float hi) {
    return std::min(hi, std::max(lo, v));
}

inline float saturate(float v) {
    return clamp(v, 0.0f, 1.0f);
}

inline float lerp(float a, float b, float t) {
    return a + (b - a) * t;
}

inline float smoothstep(float edge0, float edge1, float x) {
    const float denominator = edge1 - edge0;
    if (std::abs(denominator) < 1.0e-8f) {
        return x < edge0 ? 0.0f : 1.0f;
    }
    const float t = saturate((x - edge0) / denominator);
    return t * t * (3.0f - 2.0f * t);
}

inline float damp(float current, float target, float lambda, float dt) {
    return lerp(current, target, 1.0f - std::exp(-lambda * std::max(dt, 0.0f)));
}

inline float radians(float degrees) {
    return degrees * (kPi / 180.0f);
}

inline float degrees(float radiansValue) {
    return radiansValue * (180.0f / kPi);
}

struct Vec2 {
    float x = 0.0f;
    float y = 0.0f;

    constexpr Vec2() = default;
    constexpr Vec2(float xValue, float yValue) : x(xValue), y(yValue) {}

    Vec2 operator+(const Vec2& rhs) const { return {x + rhs.x, y + rhs.y}; }
    Vec2 operator-(const Vec2& rhs) const { return {x - rhs.x, y - rhs.y}; }
    Vec2 operator*(float scalar) const { return {x * scalar, y * scalar}; }
    Vec2 operator/(float scalar) const { return {x / scalar, y / scalar}; }
};

struct Vec3 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;

    constexpr Vec3() = default;
    constexpr Vec3(float xValue, float yValue, float zValue) : x(xValue), y(yValue), z(zValue) {}

    Vec3 operator+() const { return *this; }
    Vec3 operator-() const { return {-x, -y, -z}; }
    Vec3 operator+(const Vec3& rhs) const { return {x + rhs.x, y + rhs.y, z + rhs.z}; }
    Vec3 operator-(const Vec3& rhs) const { return {x - rhs.x, y - rhs.y, z - rhs.z}; }
    Vec3 operator*(float scalar) const { return {x * scalar, y * scalar, z * scalar}; }
    Vec3 operator/(float scalar) const { return {x / scalar, y / scalar, z / scalar}; }
    Vec3& operator+=(const Vec3& rhs) {
        x += rhs.x;
        y += rhs.y;
        z += rhs.z;
        return *this;
    }
    Vec3& operator-=(const Vec3& rhs) {
        x -= rhs.x;
        y -= rhs.y;
        z -= rhs.z;
        return *this;
    }
    Vec3& operator*=(float scalar) {
        x *= scalar;
        y *= scalar;
        z *= scalar;
        return *this;
    }

    float lengthSquared() const { return x * x + y * y + z * z; }
    float length() const { return std::sqrt(lengthSquared()); }

    Vec3 normalized(const Vec3& fallback = {0.0f, 1.0f, 0.0f}) const {
        const float len = length();
        if (!(len > 1.0e-8f) || !std::isfinite(len)) {
            return fallback;
        }
        return *this / len;
    }

    bool finite() const {
        return std::isfinite(x) && std::isfinite(y) && std::isfinite(z);
    }
};

inline Vec3 operator*(float scalar, const Vec3& value) {
    return value * scalar;
}

inline float dot(const Vec3& a, const Vec3& b) {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

inline Vec3 cross(const Vec3& a, const Vec3& b) {
    return {
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x,
    };
}

inline Vec3 mix(const Vec3& a, const Vec3& b, float t) {
    return a + (b - a) * t;
}

inline Vec3 hadamard(const Vec3& a, const Vec3& b) {
    return {a.x * b.x, a.y * b.y, a.z * b.z};
}

inline Vec3 sanitizeColor(const Vec3& value, float maximum = 64.0f) {
    auto clean = [maximum](float component) {
        if (!std::isfinite(component)) {
            return 0.0f;
        }
        return clamp(component, 0.0f, maximum);
    };
    return {clean(value.x), clean(value.y), clean(value.z)};
}

struct Vec4 {
    float x = 0.0f;
    float y = 0.0f;
    float z = 0.0f;
    float w = 0.0f;

    constexpr Vec4() = default;
    constexpr Vec4(float xValue, float yValue, float zValue, float wValue)
        : x(xValue), y(yValue), z(zValue), w(wValue) {}
};

// Column-major, OpenGL-compatible 4x4 matrix.
struct Mat4 {
    std::array<float, 16> m{};

    Mat4() {
        m = {1.0f, 0.0f, 0.0f, 0.0f,
             0.0f, 1.0f, 0.0f, 0.0f,
             0.0f, 0.0f, 1.0f, 0.0f,
             0.0f, 0.0f, 0.0f, 1.0f};
    }

    explicit Mat4(const std::array<float, 16>& values) : m(values) {}

    static Mat4 identity() { return {}; }

    static Mat4 translation(const Vec3& value) {
        Mat4 result;
        result.m[12] = value.x;
        result.m[13] = value.y;
        result.m[14] = value.z;
        return result;
    }

    static Mat4 scale(const Vec3& value) {
        Mat4 result;
        result.m[0] = value.x;
        result.m[5] = value.y;
        result.m[10] = value.z;
        return result;
    }

    static Mat4 rotationX(float angle) {
        Mat4 result;
        const float c = std::cos(angle);
        const float s = std::sin(angle);
        result.m[5] = c;
        result.m[6] = s;
        result.m[9] = -s;
        result.m[10] = c;
        return result;
    }

    static Mat4 rotationY(float angle) {
        Mat4 result;
        const float c = std::cos(angle);
        const float s = std::sin(angle);
        result.m[0] = c;
        result.m[2] = -s;
        result.m[8] = s;
        result.m[10] = c;
        return result;
    }

    static Mat4 rotationZ(float angle) {
        Mat4 result;
        const float c = std::cos(angle);
        const float s = std::sin(angle);
        result.m[0] = c;
        result.m[1] = s;
        result.m[4] = -s;
        result.m[5] = c;
        return result;
    }

    static Mat4 perspective(float verticalFovRadians, float aspect, float nearPlane, float farPlane) {
        const float safeAspect = std::max(aspect, 1.0e-4f);
        const float f = 1.0f / std::tan(verticalFovRadians * 0.5f);
        Mat4 result({0.0f, 0.0f, 0.0f, 0.0f,
                     0.0f, 0.0f, 0.0f, 0.0f,
                     0.0f, 0.0f, 0.0f, 0.0f,
                     0.0f, 0.0f, 0.0f, 0.0f});
        result.m[0] = f / safeAspect;
        result.m[5] = f;
        result.m[10] = (farPlane + nearPlane) / (nearPlane - farPlane);
        result.m[11] = -1.0f;
        result.m[14] = (2.0f * farPlane * nearPlane) / (nearPlane - farPlane);
        return result;
    }

    static Mat4 lookAt(const Vec3& eye, const Vec3& target, const Vec3& upHint) {
        const Vec3 forward = (target - eye).normalized({1.0f, 0.0f, 0.0f});
        Vec3 right = cross(forward, upHint).normalized({0.0f, 0.0f, 1.0f});
        Vec3 up = cross(right, forward).normalized({0.0f, 1.0f, 0.0f});
        if (std::abs(dot(right, up)) > 1.0e-3f) {
            right = cross(forward, {0.0f, 1.0f, 0.0f}).normalized({0.0f, 0.0f, 1.0f});
            up = cross(right, forward).normalized({0.0f, 1.0f, 0.0f});
        }
        Mat4 result;
        result.m[0] = right.x;
        result.m[4] = right.y;
        result.m[8] = right.z;
        result.m[1] = up.x;
        result.m[5] = up.y;
        result.m[9] = up.z;
        result.m[2] = -forward.x;
        result.m[6] = -forward.y;
        result.m[10] = -forward.z;
        result.m[12] = -dot(right, eye);
        result.m[13] = -dot(up, eye);
        result.m[14] = dot(forward, eye);
        return result;
    }

    const float* data() const { return m.data(); }
    float* data() { return m.data(); }
};

inline Mat4 operator*(const Mat4& a, const Mat4& b) {
    Mat4 result({0.0f, 0.0f, 0.0f, 0.0f,
                 0.0f, 0.0f, 0.0f, 0.0f,
                 0.0f, 0.0f, 0.0f, 0.0f,
                 0.0f, 0.0f, 0.0f, 0.0f});
    for (int column = 0; column < 4; ++column) {
        for (int row = 0; row < 4; ++row) {
            float sum = 0.0f;
            for (int k = 0; k < 4; ++k) {
                sum += a.m[k * 4 + row] * b.m[column * 4 + k];
            }
            result.m[column * 4 + row] = sum;
        }
    }
    return result;
}

inline Vec3 transformPoint(const Mat4& matrix, const Vec3& point) {
    const float x = matrix.m[0] * point.x + matrix.m[4] * point.y + matrix.m[8] * point.z + matrix.m[12];
    const float y = matrix.m[1] * point.x + matrix.m[5] * point.y + matrix.m[9] * point.z + matrix.m[13];
    const float z = matrix.m[2] * point.x + matrix.m[6] * point.y + matrix.m[10] * point.z + matrix.m[14];
    const float w = matrix.m[3] * point.x + matrix.m[7] * point.y + matrix.m[11] * point.z + matrix.m[15];
    if (std::abs(w) > 1.0e-8f && std::abs(w - 1.0f) > 1.0e-6f) {
        return {x / w, y / w, z / w};
    }
    return {x, y, z};
}

inline Vec3 transformVector(const Mat4& matrix, const Vec3& vector) {
    return {
        matrix.m[0] * vector.x + matrix.m[4] * vector.y + matrix.m[8] * vector.z,
        matrix.m[1] * vector.x + matrix.m[5] * vector.y + matrix.m[9] * vector.z,
        matrix.m[2] * vector.x + matrix.m[6] * vector.y + matrix.m[10] * vector.z,
    };
}

inline bool inverse(const Mat4& matrix, Mat4& output) {
    const float* m = matrix.m.data();
    std::array<float, 16> inv{};
    inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] +
             m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
    inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] -
             m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
    inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] +
             m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
    inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] -
              m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
    inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] -
             m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
    inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] +
             m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
    inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] -
             m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
    inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] +
              m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
    inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] +
             m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
    inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] -
             m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
    inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] +
              m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
    inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] -
              m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
    inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] -
             m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
    inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] +
             m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
    inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] -
              m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
    inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] +
              m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
    const float determinant = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
    if (!std::isfinite(determinant) || std::abs(determinant) < 1.0e-8f) {
        return false;
    }
    const float reciprocal = 1.0f / determinant;
    for (float& value : inv) value *= reciprocal;
    output = Mat4(inv);
    return true;
}

inline Vec3 unprojectNdc(const Mat4& inverseViewProjection, const Vec3& ndc) {
    const float x = inverseViewProjection.m[0] * ndc.x + inverseViewProjection.m[4] * ndc.y +
                    inverseViewProjection.m[8] * ndc.z + inverseViewProjection.m[12];
    const float y = inverseViewProjection.m[1] * ndc.x + inverseViewProjection.m[5] * ndc.y +
                    inverseViewProjection.m[9] * ndc.z + inverseViewProjection.m[13];
    const float z = inverseViewProjection.m[2] * ndc.x + inverseViewProjection.m[6] * ndc.y +
                    inverseViewProjection.m[10] * ndc.z + inverseViewProjection.m[14];
    const float w = inverseViewProjection.m[3] * ndc.x + inverseViewProjection.m[7] * ndc.y +
                    inverseViewProjection.m[11] * ndc.z + inverseViewProjection.m[15];
    if (std::abs(w) <= 1.0e-8f) return {x, y, z};
    return {x / w, y / w, z / w};
}

inline Mat4 compose(const Vec3& translation, const Vec3& rotationRadians, const Vec3& scaleValue = {1.0f, 1.0f, 1.0f}) {
    return Mat4::translation(translation) * Mat4::rotationZ(rotationRadians.z) *
           Mat4::rotationY(rotationRadians.y) * Mat4::rotationX(rotationRadians.x) * Mat4::scale(scaleValue);
}

inline uint32_t hashUint(uint32_t value) {
    value ^= value >> 16U;
    value *= 0x7feb352dU;
    value ^= value >> 15U;
    value *= 0x846ca68bU;
    value ^= value >> 16U;
    return value;
}

inline float hash01(uint32_t value) {
    return static_cast<float>(hashUint(value) & 0x00ffffffU) / static_cast<float>(0x01000000U);
}

class Random {
public:
    explicit Random(uint32_t seed) : state_(seed) {}

    uint32_t nextUint() {
        uint32_t z = (state_ += 0x6d2b79f5U);
        z = (z ^ (z >> 15U)) * (z | 1U);
        z ^= z + ((z ^ (z >> 7U)) * (z | 61U));
        return z ^ (z >> 14U);
    }

    float next() {
        return static_cast<float>(nextUint()) / static_cast<float>(std::numeric_limits<uint32_t>::max());
    }

    float range(float low, float high) {
        return lerp(low, high, next());
    }

private:
    uint32_t state_;
};

}  // namespace pelican::scene
