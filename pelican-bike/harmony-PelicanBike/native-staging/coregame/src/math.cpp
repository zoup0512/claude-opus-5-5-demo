#include "pelican/math.hpp"

#include <algorithm>
#include <limits>

namespace pelican {
namespace {

constexpr double kEpsilon = 1e-12;

}  // namespace

double Vec2::lengthSquared() const noexcept { return x * x + y * y; }

double Vec2::length() const noexcept { return std::sqrt(lengthSquared()); }

Vec2 Vec2::normalized(double epsilon) const noexcept {
  const double len = length();
  return len > epsilon ? *this / len : Vec2{};
}

double Vec2::dot(const Vec2& rhs) const noexcept { return x * rhs.x + y * rhs.y; }

Vec2& Vec2::operator+=(const Vec2& rhs) noexcept {
  x += rhs.x;
  y += rhs.y;
  return *this;
}

Vec2& Vec2::operator-=(const Vec2& rhs) noexcept {
  x -= rhs.x;
  y -= rhs.y;
  return *this;
}

Vec2& Vec2::operator*=(double scalar) noexcept {
  x *= scalar;
  y *= scalar;
  return *this;
}

Vec2& Vec2::operator/=(double scalar) noexcept {
  x /= scalar;
  y /= scalar;
  return *this;
}

Vec2 operator+(Vec2 lhs, const Vec2& rhs) noexcept { return lhs += rhs; }
Vec2 operator-(Vec2 lhs, const Vec2& rhs) noexcept { return lhs -= rhs; }
Vec2 operator-(const Vec2& value) noexcept { return {-value.x, -value.y}; }
Vec2 operator*(Vec2 value, double scalar) noexcept { return value *= scalar; }
Vec2 operator*(double scalar, Vec2 value) noexcept { return value *= scalar; }
Vec2 operator/(Vec2 value, double scalar) noexcept { return value /= scalar; }

double Vec3::lengthSquared() const noexcept { return x * x + y * y + z * z; }

double Vec3::length() const noexcept { return std::sqrt(lengthSquared()); }

Vec3 Vec3::normalized(double epsilon) const noexcept {
  const double len = length();
  return len > epsilon ? *this / len : Vec3{};
}

double Vec3::dot(const Vec3& rhs) const noexcept {
  return x * rhs.x + y * rhs.y + z * rhs.z;
}

Vec3 Vec3::cross(const Vec3& rhs) const noexcept {
  return {y * rhs.z - z * rhs.y, z * rhs.x - x * rhs.z,
          x * rhs.y - y * rhs.x};
}

Vec3& Vec3::operator+=(const Vec3& rhs) noexcept {
  x += rhs.x;
  y += rhs.y;
  z += rhs.z;
  return *this;
}

Vec3& Vec3::operator-=(const Vec3& rhs) noexcept {
  x -= rhs.x;
  y -= rhs.y;
  z -= rhs.z;
  return *this;
}

Vec3& Vec3::operator*=(double scalar) noexcept {
  x *= scalar;
  y *= scalar;
  z *= scalar;
  return *this;
}

Vec3& Vec3::operator/=(double scalar) noexcept {
  x /= scalar;
  y /= scalar;
  z /= scalar;
  return *this;
}

Vec3 operator+(Vec3 lhs, const Vec3& rhs) noexcept { return lhs += rhs; }
Vec3 operator-(Vec3 lhs, const Vec3& rhs) noexcept { return lhs -= rhs; }
Vec3 operator-(const Vec3& value) noexcept {
  return {-value.x, -value.y, -value.z};
}
Vec3 operator*(Vec3 value, double scalar) noexcept { return value *= scalar; }
Vec3 operator*(double scalar, Vec3 value) noexcept { return value *= scalar; }
Vec3 operator/(Vec3 value, double scalar) noexcept { return value /= scalar; }

Quat Quat::identity() noexcept { return {}; }

Quat Quat::fromAxisAngle(const Vec3& axis, double radians) noexcept {
  const Vec3 n = axis.normalized();
  if (n.lengthSquared() <= kEpsilon) {
    return identity();
  }
  const double half = radians * 0.5;
  const double sine = std::sin(half);
  return {n.x * sine, n.y * sine, n.z * sine, std::cos(half)};
}

Quat Quat::fromRotationMatrix(const Mat4& matrix) noexcept {
  const auto& e = matrix.elements;
  const double m11 = e[0];
  const double m12 = e[4];
  const double m13 = e[8];
  const double m21 = e[1];
  const double m22 = e[5];
  const double m23 = e[9];
  const double m31 = e[2];
  const double m32 = e[6];
  const double m33 = e[10];
  const double trace = m11 + m22 + m33;

  Quat result;
  if (trace > 0.0) {
    const double s = 0.5 / std::sqrt(trace + 1.0);
    result.w = 0.25 / s;
    result.x = (m32 - m23) * s;
    result.y = (m13 - m31) * s;
    result.z = (m21 - m12) * s;
  } else if (m11 > m22 && m11 > m33) {
    const double s = 2.0 * std::sqrt(std::max(0.0, 1.0 + m11 - m22 - m33));
    result.w = (m32 - m23) / s;
    result.x = 0.25 * s;
    result.y = (m12 + m21) / s;
    result.z = (m13 + m31) / s;
  } else if (m22 > m33) {
    const double s = 2.0 * std::sqrt(std::max(0.0, 1.0 + m22 - m11 - m33));
    result.w = (m13 - m31) / s;
    result.x = (m12 + m21) / s;
    result.y = 0.25 * s;
    result.z = (m23 + m32) / s;
  } else {
    const double s = 2.0 * std::sqrt(std::max(0.0, 1.0 + m33 - m11 - m22));
    result.w = (m21 - m12) / s;
    result.x = (m13 + m31) / s;
    result.y = (m23 + m32) / s;
    result.z = 0.25 * s;
  }
  return result.normalized();
}

Quat Quat::fromUnitVectors(const Vec3& from, const Vec3& to) noexcept {
  const Vec3 vFrom = from.normalized();
  const Vec3 vTo = to.normalized();
  if (vFrom.lengthSquared() <= kEpsilon || vTo.lengthSquared() <= kEpsilon) {
    return identity();
  }

  double r = vFrom.dot(vTo) + 1.0;
  Vec3 vector;
  if (r < 1e-6) {
    r = 0.0;
    vector = std::abs(vFrom.x) > std::abs(vFrom.z)
                 ? Vec3{-vFrom.y, vFrom.x, 0.0}
                 : Vec3{0.0, -vFrom.z, vFrom.y};
  } else {
    vector = vFrom.cross(vTo);
  }
  return Quat{vector.x, vector.y, vector.z, r}.normalized();
}

double Quat::lengthSquared() const noexcept { return x * x + y * y + z * z + w * w; }

double Quat::length() const noexcept { return std::sqrt(lengthSquared()); }

Quat Quat::normalized(double epsilon) const noexcept {
  const double len = length();
  return len > epsilon ? Quat{x / len, y / len, z / len, w / len} : identity();
}

Quat Quat::conjugate() const noexcept { return {-x, -y, -z, w}; }

Quat Quat::inverse(double epsilon) const noexcept {
  const double lenSq = lengthSquared();
  if (lenSq <= epsilon) {
    return identity();
  }
  const Quat c = conjugate();
  return {c.x / lenSq, c.y / lenSq, c.z / lenSq, c.w / lenSq};
}

double Quat::dot(const Quat& rhs) const noexcept {
  return x * rhs.x + y * rhs.y + z * rhs.z + w * rhs.w;
}

Quat Quat::slerp(const Quat& rhs, double t) const noexcept {
  const Quat from = normalized();
  Quat to = rhs.normalized();
  double cosine = from.dot(to);
  if (cosine < 0.0) {
    to = {-to.x, -to.y, -to.z, -to.w};
    cosine = -cosine;
  }

  if (cosine > 0.9995) {
    Quat linear{from.x + (to.x - from.x) * t,
                from.y + (to.y - from.y) * t,
                from.z + (to.z - from.z) * t,
                from.w + (to.w - from.w) * t};
    return linear.normalized();
  }

  cosine = clamp(cosine, -1.0, 1.0);
  const double theta = std::acos(cosine);
  const double sine = std::sin(theta);
  if (std::abs(sine) <= kEpsilon) {
    return from;
  }
  const double a = std::sin((1.0 - t) * theta) / sine;
  const double b = std::sin(t * theta) / sine;
  return {from.x * a + to.x * b, from.y * a + to.y * b,
          from.z * a + to.z * b, from.w * a + to.w * b};
}

Vec3 Quat::rotate(const Vec3& value) const noexcept {
  const Quat q = normalized();
  const Vec3 qv{q.x, q.y, q.z};
  const Vec3 uv = qv.cross(value);
  const Vec3 uuv = qv.cross(uv);
  return value + (uv * q.w + uuv) * 2.0;
}

Quat& Quat::operator*=(const Quat& rhs) noexcept {
  const double ax = x;
  const double ay = y;
  const double az = z;
  const double aw = w;
  const double bx = rhs.x;
  const double by = rhs.y;
  const double bz = rhs.z;
  const double bw = rhs.w;
  x = ax * bw + aw * bx + ay * bz - az * by;
  y = ay * bw + aw * by + az * bx - ax * bz;
  z = az * bw + aw * bz + ax * by - ay * bx;
  w = aw * bw - ax * bx - ay * by - az * bz;
  return *this;
}

Quat operator*(Quat lhs, const Quat& rhs) noexcept { return lhs *= rhs; }

Mat4::Mat4() noexcept : elements(identity().elements) {}

Mat4 Mat4::identity() noexcept {
  return Mat4{{1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0,
               0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0}};
}

Mat4 Mat4::translation(const Vec3& value) noexcept {
  Mat4 result = identity();
  result.elements[12] = value.x;
  result.elements[13] = value.y;
  result.elements[14] = value.z;
  return result;
}

Mat4 Mat4::scaling(const Vec3& value) noexcept {
  Mat4 result = identity();
  result.elements[0] = value.x;
  result.elements[5] = value.y;
  result.elements[10] = value.z;
  return result;
}

Mat4 Mat4::rotation(const Quat& value) noexcept {
  const Quat q = value.normalized();
  const double x2 = q.x + q.x;
  const double y2 = q.y + q.y;
  const double z2 = q.z + q.z;
  const double xx = q.x * x2;
  const double xy = q.x * y2;
  const double xz = q.x * z2;
  const double yy = q.y * y2;
  const double yz = q.y * z2;
  const double zz = q.z * z2;
  const double wx = q.w * x2;
  const double wy = q.w * y2;
  const double wz = q.w * z2;

  return Mat4{{1.0 - (yy + zz), xy + wz, xz - wy, 0.0,
               xy - wz, 1.0 - (xx + zz), yz + wx, 0.0,
               xz + wy, yz - wx, 1.0 - (xx + yy), 0.0,
               0.0, 0.0, 0.0, 1.0}};
}

Mat4 Mat4::compose(const Vec3& position, const Quat& rotationValue,
                   const Vec3& scale) noexcept {
  Mat4 result = rotation(rotationValue);
  result.elements[0] *= scale.x;
  result.elements[1] *= scale.x;
  result.elements[2] *= scale.x;
  result.elements[4] *= scale.y;
  result.elements[5] *= scale.y;
  result.elements[6] *= scale.y;
  result.elements[8] *= scale.z;
  result.elements[9] *= scale.z;
  result.elements[10] *= scale.z;
  result.elements[12] = position.x;
  result.elements[13] = position.y;
  result.elements[14] = position.z;
  return result;
}

Mat4 Mat4::lookAt(const Vec3& eye, const Vec3& target, const Vec3& up) noexcept {
  Vec3 z = (eye - target).normalized();
  if (z.lengthSquared() <= kEpsilon) {
    z.z = 1.0;
  }
  Vec3 x = up.cross(z).normalized();
  if (x.lengthSquared() <= kEpsilon) {
    z.x += 1e-4;
    z = z.normalized();
    x = up.cross(z).normalized();
  }
  const Vec3 y = z.cross(x);
  return Mat4{{x.x, x.y, x.z, 0.0, y.x, y.y, y.z, 0.0,
               z.x, z.y, z.z, 0.0, 0.0, 0.0, 0.0, 1.0}};
}

Mat4 Mat4::perspective(double verticalFovRadians, double aspect,
                       double nearPlane, double farPlane) noexcept {
  const double f = 1.0 / std::tan(verticalFovRadians * 0.5);
  const double nf = 1.0 / (nearPlane - farPlane);
  return Mat4{{f / aspect, 0.0, 0.0, 0.0,
               0.0, f, 0.0, 0.0,
               0.0, 0.0, (farPlane + nearPlane) * nf, -1.0,
               0.0, 0.0, 2.0 * farPlane * nearPlane * nf, 0.0}};
}

Vec3 Mat4::transformPoint(const Vec3& value) const noexcept {
  const auto& e = elements;
  const double wValue = e[3] * value.x + e[7] * value.y +
                        e[11] * value.z + e[15];
  const double reciprocal = std::abs(wValue) > kEpsilon ? 1.0 / wValue : 1.0;
  return {(e[0] * value.x + e[4] * value.y + e[8] * value.z + e[12]) * reciprocal,
          (e[1] * value.x + e[5] * value.y + e[9] * value.z + e[13]) * reciprocal,
          (e[2] * value.x + e[6] * value.y + e[10] * value.z + e[14]) * reciprocal};
}

Vec3 Mat4::transformVector(const Vec3& value) const noexcept {
  const auto& e = elements;
  return {e[0] * value.x + e[4] * value.y + e[8] * value.z,
          e[1] * value.x + e[5] * value.y + e[9] * value.z,
          e[2] * value.x + e[6] * value.y + e[10] * value.z};
}

Mat4 Mat4::transposed() const noexcept {
  Mat4 result;
  for (std::size_t row = 0; row < 4; ++row) {
    for (std::size_t column = 0; column < 4; ++column) {
      result.elements[column * 4 + row] = elements[row * 4 + column];
    }
  }
  return result;
}

Mat4 Mat4::inverse(double epsilon) const noexcept {
  const double* m = elements.data();
  std::array<double, 16> inv{};

  inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] -
           m[9] * m[6] * m[15] + m[9] * m[7] * m[14] +
           m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
  inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] +
           m[8] * m[6] * m[15] - m[8] * m[7] * m[14] -
           m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
  inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] -
           m[8] * m[5] * m[15] + m[8] * m[7] * m[13] +
           m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
  inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] +
            m[8] * m[5] * m[14] - m[8] * m[6] * m[13] -
            m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
  inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] +
           m[9] * m[2] * m[15] - m[9] * m[3] * m[14] -
           m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
  inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] -
           m[8] * m[2] * m[15] + m[8] * m[3] * m[14] +
           m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
  inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] +
           m[8] * m[1] * m[15] - m[8] * m[3] * m[13] -
           m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
  inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] -
            m[8] * m[1] * m[14] + m[8] * m[2] * m[13] +
            m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
  inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] -
           m[5] * m[2] * m[15] + m[5] * m[3] * m[14] +
           m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
  inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] +
           m[4] * m[2] * m[15] - m[4] * m[3] * m[14] -
           m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
  inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] -
            m[4] * m[1] * m[15] + m[4] * m[3] * m[13] +
            m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
  inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] +
            m[4] * m[1] * m[14] - m[4] * m[2] * m[13] -
            m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
  inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] +
           m[5] * m[2] * m[11] - m[5] * m[3] * m[10] -
           m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
  inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] -
           m[4] * m[2] * m[11] + m[4] * m[3] * m[10] +
           m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
  inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] +
            m[4] * m[1] * m[11] - m[4] * m[3] * m[9] -
            m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
  inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] -
            m[4] * m[1] * m[10] + m[4] * m[2] * m[9] +
            m[8] * m[1] * m[6] - m[8] * m[2] * m[5];

  const double determinant = m[0] * inv[0] + m[1] * inv[4] +
                             m[2] * inv[8] + m[3] * inv[12];
  if (std::abs(determinant) <= epsilon) {
    return identity();
  }
  const double reciprocal = 1.0 / determinant;
  for (double& value : inv) {
    value *= reciprocal;
  }
  return Mat4{inv};
}

Mat4& Mat4::operator*=(const Mat4& rhs) noexcept {
  const auto a = elements;
  const auto& b = rhs.elements;
  std::array<double, 16> result{};
  for (std::size_t column = 0; column < 4; ++column) {
    for (std::size_t row = 0; row < 4; ++row) {
      result[column * 4 + row] =
          a[0 * 4 + row] * b[column * 4 + 0] +
          a[1 * 4 + row] * b[column * 4 + 1] +
          a[2 * 4 + row] * b[column * 4 + 2] +
          a[3 * 4 + row] * b[column * 4 + 3];
    }
  }
  elements = result;
  return *this;
}

Mat4 operator*(Mat4 lhs, const Mat4& rhs) noexcept { return lhs *= rhs; }

double damp(double current, double target, double lambda,
            double deltaSeconds) noexcept {
  return lerp(current, target, 1.0 - std::exp(-lambda * deltaSeconds));
}

double smoothstep(double edge0, double edge1, double x) noexcept {
  if (edge0 == edge1) {
    return x < edge0 ? 0.0 : 1.0;
  }
  const double t = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

}  // namespace pelican
