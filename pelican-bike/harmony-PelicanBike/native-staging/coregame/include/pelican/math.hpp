#pragma once

#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>

namespace pelican {

inline constexpr double kPi = 3.141592653589793238462643383279502884;
inline constexpr double kTau = kPi * 2.0;

struct Vec2 {
  double x{0.0};
  double y{0.0};

  constexpr Vec2() noexcept = default;
  constexpr Vec2(double xValue, double yValue) noexcept : x(xValue), y(yValue) {}

  [[nodiscard]] double lengthSquared() const noexcept;
  [[nodiscard]] double length() const noexcept;
  [[nodiscard]] Vec2 normalized(double epsilon = 1e-12) const noexcept;
  [[nodiscard]] double dot(const Vec2& rhs) const noexcept;

  Vec2& operator+=(const Vec2& rhs) noexcept;
  Vec2& operator-=(const Vec2& rhs) noexcept;
  Vec2& operator*=(double scalar) noexcept;
  Vec2& operator/=(double scalar) noexcept;
};

[[nodiscard]] Vec2 operator+(Vec2 lhs, const Vec2& rhs) noexcept;
[[nodiscard]] Vec2 operator-(Vec2 lhs, const Vec2& rhs) noexcept;
[[nodiscard]] Vec2 operator-(const Vec2& value) noexcept;
[[nodiscard]] Vec2 operator*(Vec2 value, double scalar) noexcept;
[[nodiscard]] Vec2 operator*(double scalar, Vec2 value) noexcept;
[[nodiscard]] Vec2 operator/(Vec2 value, double scalar) noexcept;

struct Vec3 {
  double x{0.0};
  double y{0.0};
  double z{0.0};

  constexpr Vec3() noexcept = default;
  constexpr Vec3(double xValue, double yValue, double zValue) noexcept
      : x(xValue), y(yValue), z(zValue) {}

  [[nodiscard]] double lengthSquared() const noexcept;
  [[nodiscard]] double length() const noexcept;
  [[nodiscard]] Vec3 normalized(double epsilon = 1e-12) const noexcept;
  [[nodiscard]] double dot(const Vec3& rhs) const noexcept;
  [[nodiscard]] Vec3 cross(const Vec3& rhs) const noexcept;

  Vec3& operator+=(const Vec3& rhs) noexcept;
  Vec3& operator-=(const Vec3& rhs) noexcept;
  Vec3& operator*=(double scalar) noexcept;
  Vec3& operator/=(double scalar) noexcept;
};

[[nodiscard]] Vec3 operator+(Vec3 lhs, const Vec3& rhs) noexcept;
[[nodiscard]] Vec3 operator-(Vec3 lhs, const Vec3& rhs) noexcept;
[[nodiscard]] Vec3 operator-(const Vec3& value) noexcept;
[[nodiscard]] Vec3 operator*(Vec3 value, double scalar) noexcept;
[[nodiscard]] Vec3 operator*(double scalar, Vec3 value) noexcept;
[[nodiscard]] Vec3 operator/(Vec3 value, double scalar) noexcept;

struct Mat4;

struct Quat {
  double x{0.0};
  double y{0.0};
  double z{0.0};
  double w{1.0};

  constexpr Quat() noexcept = default;
  constexpr Quat(double xValue, double yValue, double zValue, double wValue) noexcept
      : x(xValue), y(yValue), z(zValue), w(wValue) {}

  [[nodiscard]] static Quat identity() noexcept;
  [[nodiscard]] static Quat fromAxisAngle(const Vec3& axis, double radians) noexcept;
  [[nodiscard]] static Quat fromRotationMatrix(const Mat4& matrix) noexcept;
  [[nodiscard]] static Quat fromUnitVectors(const Vec3& from, const Vec3& to) noexcept;

  [[nodiscard]] double lengthSquared() const noexcept;
  [[nodiscard]] double length() const noexcept;
  [[nodiscard]] Quat normalized(double epsilon = 1e-12) const noexcept;
  [[nodiscard]] Quat conjugate() const noexcept;
  [[nodiscard]] Quat inverse(double epsilon = 1e-12) const noexcept;
  [[nodiscard]] double dot(const Quat& rhs) const noexcept;
  [[nodiscard]] Quat slerp(const Quat& rhs, double t) const noexcept;
  [[nodiscard]] Vec3 rotate(const Vec3& value) const noexcept;

  Quat& operator*=(const Quat& rhs) noexcept;
};

[[nodiscard]] Quat operator*(Quat lhs, const Quat& rhs) noexcept;

struct Mat4 {
  // Column-major, matching OpenGL/Three.js storage and multiplication order.
  std::array<double, 16> elements{};

  Mat4() noexcept;
  explicit Mat4(const std::array<double, 16>& values) noexcept : elements(values) {}

  [[nodiscard]] static Mat4 identity() noexcept;
  [[nodiscard]] static Mat4 translation(const Vec3& value) noexcept;
  [[nodiscard]] static Mat4 scaling(const Vec3& value) noexcept;
  [[nodiscard]] static Mat4 rotation(const Quat& value) noexcept;
  [[nodiscard]] static Mat4 compose(const Vec3& position, const Quat& rotation,
                                    const Vec3& scale) noexcept;
  [[nodiscard]] static Mat4 lookAt(const Vec3& eye, const Vec3& target,
                                   const Vec3& up) noexcept;
  [[nodiscard]] static Mat4 perspective(double verticalFovRadians, double aspect,
                                        double nearPlane, double farPlane) noexcept;

  [[nodiscard]] Vec3 transformPoint(const Vec3& value) const noexcept;
  [[nodiscard]] Vec3 transformVector(const Vec3& value) const noexcept;
  [[nodiscard]] Mat4 transposed() const noexcept;
  [[nodiscard]] Mat4 inverse(double epsilon = 1e-12) const noexcept;

  Mat4& operator*=(const Mat4& rhs) noexcept;
};

[[nodiscard]] Mat4 operator*(Mat4 lhs, const Mat4& rhs) noexcept;

template <typename T>
[[nodiscard]] constexpr T clamp(T value, T minimum, T maximum) noexcept {
  return value < minimum ? minimum : (value > maximum ? maximum : value);
}

template <typename T, typename U>
[[nodiscard]] constexpr auto lerp(const T& a, const T& b, U t) noexcept
    -> decltype(a + (b - a) * t) {
  return a + (b - a) * t;
}

[[nodiscard]] double damp(double current, double target, double lambda,
                          double deltaSeconds) noexcept;
[[nodiscard]] double smoothstep(double edge0, double edge1, double x) noexcept;

}  // namespace pelican
