#pragma once

#include <cstdint>

namespace pelican {

class Mulberry32 {
 public:
  explicit constexpr Mulberry32(std::uint32_t seed = 0U) noexcept : state_(seed) {}

  void seed(std::uint32_t value) noexcept { state_ = value; }
  [[nodiscard]] std::uint32_t state() const noexcept { return state_; }
  [[nodiscard]] std::uint32_t nextU32() noexcept;
  [[nodiscard]] double nextDouble() noexcept;
  [[nodiscard]] float nextFloat() noexcept;

 private:
  std::uint32_t state_{0U};
};

}  // namespace pelican
