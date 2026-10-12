#include "pelican/random.hpp"

namespace pelican {

std::uint32_t Mulberry32::nextU32() noexcept {
  state_ += 0x6D2B79F5U;
  std::uint32_t t = state_;
  t = (t ^ (t >> 15U)) * (1U | t);
  t = (t + ((t ^ (t >> 7U)) * (61U | t))) ^ t;
  return t ^ (t >> 14U);
}

double Mulberry32::nextDouble() noexcept {
  return static_cast<double>(nextU32()) / 4294967296.0;
}

float Mulberry32::nextFloat() noexcept {
  return static_cast<float>(nextDouble());
}

}  // namespace pelican
