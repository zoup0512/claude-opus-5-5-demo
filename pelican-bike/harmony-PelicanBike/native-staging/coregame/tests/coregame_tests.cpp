#include "pelican/coregame.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

namespace {

using pelican::Achievement;
using pelican::EventType;
using pelican::GameSimulation;
using pelican::InputState;
using pelican::Mat4;
using pelican::Mulberry32;
using pelican::Quat;
using pelican::Settings;
using pelican::Vec3;

void fail(const std::string& message) { throw std::runtime_error(message); }

void require(bool condition, const std::string& message) {
  if (!condition) {
    fail(message);
  }
}

void requireNear(double actual, double expected, double tolerance,
                 const std::string& label) {
  if (std::abs(actual - expected) > tolerance) {
    std::ostringstream stream;
    stream.precision(17);
    stream << label << ": expected " << expected << ", got " << actual
           << " (tolerance " << tolerance << ')';
    fail(stream.str());
  }
}

void requireVecNear(const Vec3& actual, const Vec3& expected, double tolerance,
                    const std::string& label) {
  requireNear(actual.x, expected.x, tolerance, label + ".x");
  requireNear(actual.y, expected.y, tolerance, label + ".y");
  requireNear(actual.z, expected.z, tolerance, label + ".z");
}

bool containsEvent(const std::vector<pelican::GameEvent>& events,
                   EventType type) {
  return std::any_of(events.begin(), events.end(),
                     [type](const pelican::GameEvent& event) {
                       return event.type == type;
                     });
}

bool containsAchievement(const std::vector<pelican::GameEvent>& events,
                         Achievement achievement) {
  return std::any_of(events.begin(), events.end(),
                     [achievement](const pelican::GameEvent& event) {
                       return event.type == EventType::AchievementUnlocked &&
                              event.achievement == achievement;
                     });
}

std::string readTextFile(const std::filesystem::path& path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream) {
    return {};
  }
  std::ostringstream content;
  content << stream.rdbuf();
  return content.str();
}

class JsonValue {
 public:
  enum class Type : std::uint8_t {
    Null,
    Bool,
    Number,
    String,
    Array,
    Object,
  };

  using Array = std::vector<JsonValue>;
  using Object = std::vector<std::pair<std::string, JsonValue>>;

  JsonValue() = default;

  [[nodiscard]] Type type() const noexcept { return type_; }

  [[nodiscard]] bool asBool() const {
    require(type_ == Type::Bool, "JSON value is not bool");
    return boolean_;
  }

  [[nodiscard]] double asNumber() const {
    require(type_ == Type::Number, "JSON value is not number");
    return number_;
  }

  [[nodiscard]] const std::string& asString() const {
    require(type_ == Type::String, "JSON value is not string");
    return string_;
  }

  [[nodiscard]] const Array& asArray() const {
    require(type_ == Type::Array, "JSON value is not array");
    return array_;
  }

  [[nodiscard]] const Object& asObject() const {
    require(type_ == Type::Object, "JSON value is not object");
    return object_;
  }

  [[nodiscard]] const JsonValue* find(std::string_view key) const noexcept {
    if (type_ != Type::Object) {
      return nullptr;
    }
    for (const auto& item : object_) {
      if (item.first == key) {
        return &item.second;
      }
    }
    return nullptr;
  }

  [[nodiscard]] const JsonValue& at(std::string_view key) const {
    const JsonValue* value = find(key);
    require(value != nullptr, "JSON object missing key: " + std::string(key));
    return *value;
  }

  [[nodiscard]] const JsonValue& at(std::size_t index) const {
    const Array& values = asArray();
    require(index < values.size(), "JSON array index out of range");
    return values[index];
  }

  [[nodiscard]] std::size_t size() const {
    if (type_ == Type::Array) {
      return array_.size();
    }
    if (type_ == Type::Object) {
      return object_.size();
    }
    fail("JSON scalar has no size");
    return 0U;
  }

 private:
  friend class JsonParser;

  Type type_{Type::Null};
  bool boolean_{false};
  double number_{0.0};
  std::string string_{};
  Array array_{};
  Object object_{};
};

class JsonParser {
 public:
  explicit JsonParser(std::string_view text) : text_(text) {}

  [[nodiscard]] JsonValue parse() {
    JsonValue value = parseValue();
    skipWhitespace();
    require(position_ == text_.size(), "Trailing content after JSON value");
    return value;
  }

 private:
  [[nodiscard]] JsonValue parseValue() {
    skipWhitespace();
    require(position_ < text_.size(), "Unexpected end of JSON");
    const char ch = text_[position_];
    if (ch == '{') {
      return parseObject();
    }
    if (ch == '[') {
      return parseArray();
    }
    if (ch == '"') {
      JsonValue value;
      value.type_ = JsonValue::Type::String;
      value.string_ = parseString();
      return value;
    }
    if (ch == 't') {
      consumeLiteral("true");
      JsonValue value;
      value.type_ = JsonValue::Type::Bool;
      value.boolean_ = true;
      return value;
    }
    if (ch == 'f') {
      consumeLiteral("false");
      JsonValue value;
      value.type_ = JsonValue::Type::Bool;
      value.boolean_ = false;
      return value;
    }
    if (ch == 'n') {
      consumeLiteral("null");
      return JsonValue{};
    }
    return parseNumber();
  }

  [[nodiscard]] JsonValue parseObject() {
    JsonValue value;
    value.type_ = JsonValue::Type::Object;
    expect('{');
    skipWhitespace();
    if (consume('}')) {
      return value;
    }
    while (true) {
      skipWhitespace();
      require(position_ < text_.size() && text_[position_] == '"',
              "JSON object key must be string");
      std::string key = parseString();
      skipWhitespace();
      expect(':');
      value.object_.emplace_back(std::move(key), parseValue());
      skipWhitespace();
      if (consume('}')) {
        return value;
      }
      expect(',');
    }
  }

  [[nodiscard]] JsonValue parseArray() {
    JsonValue value;
    value.type_ = JsonValue::Type::Array;
    expect('[');
    skipWhitespace();
    if (consume(']')) {
      return value;
    }
    while (true) {
      value.array_.push_back(parseValue());
      skipWhitespace();
      if (consume(']')) {
        return value;
      }
      expect(',');
    }
  }

  [[nodiscard]] JsonValue parseNumber() {
    const std::size_t start = position_;
    if (position_ < text_.size() && text_[position_] == '-') {
      ++position_;
    }
    require(position_ < text_.size(), "Malformed JSON number");
    if (text_[position_] == '0') {
      ++position_;
    } else {
      require(text_[position_] >= '1' && text_[position_] <= '9',
              "Malformed JSON number integer part");
      while (position_ < text_.size() && text_[position_] >= '0' &&
             text_[position_] <= '9') {
        ++position_;
      }
    }
    if (position_ < text_.size() && text_[position_] == '.') {
      ++position_;
      require(position_ < text_.size() && text_[position_] >= '0' &&
                  text_[position_] <= '9',
              "Malformed JSON number fraction");
      while (position_ < text_.size() && text_[position_] >= '0' &&
             text_[position_] <= '9') {
        ++position_;
      }
    }
    if (position_ < text_.size() &&
        (text_[position_] == 'e' || text_[position_] == 'E')) {
      ++position_;
      if (position_ < text_.size() &&
          (text_[position_] == '+' || text_[position_] == '-')) {
        ++position_;
      }
      require(position_ < text_.size() && text_[position_] >= '0' &&
                  text_[position_] <= '9',
              "Malformed JSON number exponent");
      while (position_ < text_.size() && text_[position_] >= '0' &&
             text_[position_] <= '9') {
        ++position_;
      }
    }

    JsonValue value;
    value.type_ = JsonValue::Type::Number;
    const std::string token{text_.substr(start, position_ - start)};
    std::size_t consumed = 0U;
    try {
      value.number_ = std::stod(token, &consumed);
    } catch (const std::exception&) {
      fail("Unable to parse JSON number");
    }
    require(consumed == token.size(), "Partially parsed JSON number");
    return value;
  }

  [[nodiscard]] std::string parseString() {
    expect('"');
    std::string result;
    while (position_ < text_.size()) {
      const char ch = text_[position_++];
      if (ch == '"') {
        return result;
      }
      if (ch != '\\') {
        result.push_back(ch);
        continue;
      }
      require(position_ < text_.size(), "Truncated JSON escape");
      const char escaped = text_[position_++];
      switch (escaped) {
        case '"':
        case '\\':
        case '/':
          result.push_back(escaped);
          break;
        case 'b':
          result.push_back('\b');
          break;
        case 'f':
          result.push_back('\f');
          break;
        case 'n':
          result.push_back('\n');
          break;
        case 'r':
          result.push_back('\r');
          break;
        case 't':
          result.push_back('\t');
          break;
        case 'u': {
          require(position_ + 4U <= text_.size(), "Truncated JSON unicode escape");
          unsigned codepoint = 0U;
          for (int index = 0; index < 4; ++index) {
            const char hex = text_[position_++];
            codepoint <<= 4U;
            if (hex >= '0' && hex <= '9') {
              codepoint += static_cast<unsigned>(hex - '0');
            } else if (hex >= 'a' && hex <= 'f') {
              codepoint += static_cast<unsigned>(hex - 'a' + 10);
            } else if (hex >= 'A' && hex <= 'F') {
              codepoint += static_cast<unsigned>(hex - 'A' + 10);
            } else {
              fail("Malformed JSON unicode escape");
            }
          }
          appendUtf8(result, codepoint);
          break;
        }
        default:
          fail("Unsupported JSON escape");
      }
    }
    fail("Unterminated JSON string");
    return {};
  }

  static void appendUtf8(std::string& out, unsigned codepoint) {
    if (codepoint <= 0x7FU) {
      out.push_back(static_cast<char>(codepoint));
    } else if (codepoint <= 0x7FFU) {
      out.push_back(static_cast<char>(0xC0U | (codepoint >> 6U)));
      out.push_back(static_cast<char>(0x80U | (codepoint & 0x3FU)));
    } else {
      out.push_back(static_cast<char>(0xE0U | (codepoint >> 12U)));
      out.push_back(static_cast<char>(0x80U | ((codepoint >> 6U) & 0x3FU)));
      out.push_back(static_cast<char>(0x80U | (codepoint & 0x3FU)));
    }
  }

  void consumeLiteral(std::string_view literal) {
    require(text_.substr(position_, literal.size()) == literal,
            "Malformed JSON literal");
    position_ += literal.size();
  }

  void skipWhitespace() noexcept {
    while (position_ < text_.size()) {
      const char ch = text_[position_];
      if (ch != ' ' && ch != '\t' && ch != '\r' && ch != '\n') {
        return;
      }
      ++position_;
    }
  }

  [[nodiscard]] bool consume(char expected) noexcept {
    if (position_ < text_.size() && text_[position_] == expected) {
      ++position_;
      return true;
    }
    return false;
  }

  void expect(char expected) {
    require(consume(expected),
            std::string("Expected JSON character: ") + expected);
  }

  std::string_view text_;
  std::size_t position_{0U};
};

[[nodiscard]] std::uint32_t seedToU32(double value) {
  const auto signedSeed = static_cast<std::int64_t>(value);
  return static_cast<std::uint32_t>(signedSeed);
}

[[nodiscard]] std::uint32_t randomDoubleToU32(double value) {
  const double scaled = value * 4294967296.0;
  require(scaled >= 0.0 && scaled <= 4294967295.0,
          "Mulberry32 golden value outside uint32 range");
  return static_cast<std::uint32_t>(scaled);
}

[[nodiscard]] int jsonInt(const JsonValue& value) {
  return static_cast<int>(value.asNumber());
}

[[nodiscard]] std::vector<double> jsonNumberArray(const JsonValue& value) {
  std::vector<double> result;
  result.reserve(value.size());
  for (const JsonValue& item : value.asArray()) {
    result.push_back(item.asNumber());
  }
  return result;
}

struct SourceRideState {
  double speed{4.5};
  double distance{0.0};
  double lane{0.9};
  double laneVelocity{0.0};
  double laneTarget{0.9};
  double previousLaneVelocity{0.0};
  double lateralAcceleration{0.0};
  double lean{0.0};
  double steer{0.0};
  double crankAngle{0.0};
  double wheelAngle{0.0};
  int gear{2};
  double verticalPosition{0.0};
  double verticalVelocity{0.0};
  bool airborne{false};
  double trickBlend{0.0};
  double trickTimeRemaining{0.0};
  double wheelie{0.0};
  double accelerationVisual{0.0};
  bool pedaling{true};
  double cadenceRpm{0.0};
  double lastSteerTime{-99.0};
  double lastManualGearTime{-99.0};
  double time{0.0};
  double animationTime{0.0};
};

struct SourceRideInput {
  bool accelerate{false};
  bool brake{false};
  bool steerLeft{false};
  bool steerRight{false};
};

struct SourceRideSettings {
  double cruiseSpeed{7.5};
  bool autopilot{false};
  bool autoGear{true};
};

void sourceJump(SourceRideState& state) {
  if (state.airborne) {
    return;
  }
  state.airborne = true;
  state.verticalVelocity = 3.6;
}

void sourceUpdateRide(SourceRideState& state,
                      const SourceRideSettings& settings,
                      const SourceRideInput& input, double dt) {
  double acceleration;
  if (state.airborne) {
    acceleration = -0.15;
  } else if (input.brake) {
    acceleration = -6.0;
  } else if (input.accelerate) {
    acceleration = 2.4;
  } else {
    acceleration = (settings.cruiseSpeed - state.speed) * 0.7;
  }
  if (state.trickTimeRemaining > 0.0) {
    acceleration = std::min(acceleration, 0.2);
  }
  state.accelerationVisual =
      pelican::damp(state.accelerationVisual, acceleration, 6.0, dt);
  state.speed = pelican::clamp(state.speed + acceleration * dt, 0.0, 15.5);
  state.pedaling = !state.airborne && !input.brake && state.speed > 0.25 &&
                   acceleration > -0.4;
  state.distance += state.speed * dt;
  state.wheelAngle += (state.speed / pelican::kWheelRadius) * dt;

  const double wheelRpm =
      (state.speed / pelican::kWheelRadius) * 60.0 / pelican::kTau;
  if (settings.autoGear && state.time - state.lastManualGearTime > 8.0) {
    int bestGear = state.gear;
    double bestError = 1e9;
    for (std::size_t index = 0; index < pelican::kGears.size(); ++index) {
      const double ratio =
          static_cast<double>(pelican::kGears[index][0]) /
          static_cast<double>(pelican::kGears[index][1]);
      const double cadence = wheelRpm / ratio;
      const double error = std::abs(cadence - 86.0);
      if (error < bestError) {
        bestError = error;
        bestGear = static_cast<int>(index);
      }
    }
    const auto& current = pelican::kGears[static_cast<std::size_t>(state.gear)];
    const double currentRatio =
        static_cast<double>(current[0]) / static_cast<double>(current[1]);
    const double currentCadence = wheelRpm / currentRatio;
    if (bestGear != state.gear &&
        (currentCadence > 102.0 || currentCadence < 68.0)) {
      state.gear += bestGear > state.gear ? 1 : -1;
    }
  }
  const auto& selected = pelican::kGears[static_cast<std::size_t>(state.gear)];
  const double ratio =
      static_cast<double>(selected[0]) / static_cast<double>(selected[1]);
  const double crankAngularVelocity =
      state.pedaling ? state.speed / pelican::kWheelRadius / ratio : 0.0;
  state.crankAngle += crankAngularVelocity * dt;
  state.cadenceRpm = crankAngularVelocity * 60.0 / pelican::kTau;

  const int steeringInput = (input.steerRight ? 1 : 0) -
                            (input.steerLeft ? 1 : 0);
  if (steeringInput != 0) {
    state.lastSteerTime = state.time;
    state.laneTarget = pelican::clamp(
        state.laneTarget + steeringInput * 2.4 * dt, -2.15, 2.15);
  } else if (settings.autopilot && state.time - state.lastSteerTime > 4.0) {
    const double desired = 0.9 + std::sin(state.time * 0.23) * 0.7;
    state.laneTarget =
        pelican::damp(state.laneTarget, desired, 0.8, dt);
  }
  constexpr double spring = 10.0;
  state.laneVelocity +=
      ((state.laneTarget - state.lane) * spring -
       state.laneVelocity * 2.0 * std::sqrt(spring)) *
      dt;
  state.lane += state.laneVelocity * dt;
  state.lateralAcceleration =
      pelican::damp(state.lateralAcceleration,
                    (state.laneVelocity - state.previousLaneVelocity) /
                        std::max(dt, 1e-3),
                    8.0, dt);
  state.previousLaneVelocity = state.laneVelocity;
  const double wobble =
      std::sin(state.time * 1.7) * 0.02 *
      pelican::clamp(1.5 - state.speed * 0.2, 0.2, 1.5);
  state.lean = pelican::damp(
      state.lean,
      pelican::clamp(std::atan(state.lateralAcceleration / 9.8) * 1.4,
                     -0.4, 0.4) +
          wobble * 0.5,
      7.0, dt);
  const double steeringTarget =
      state.trickTimeRemaining > 0.0
          ? 0.0
          : -pelican::clamp(
                state.lateralAcceleration * 0.05 +
                    state.laneVelocity * 0.12 /
                        std::max(1.0, state.speed * 0.3),
                -0.35, 0.35) +
                wobble;
  state.steer = pelican::damp(state.steer, steeringTarget, 10.0, dt);

  if (state.airborne) {
    state.verticalVelocity -= 13.0 * dt;
    state.verticalPosition += state.verticalVelocity * dt;
    if (state.verticalPosition <= 0.0) {
      state.verticalPosition = 0.0;
      state.airborne = false;
    }
  }
  if (state.trickTimeRemaining > 0.0) {
    state.trickTimeRemaining -= dt;
  }
  state.trickBlend = pelican::damp(
      state.trickBlend, state.trickTimeRemaining > 0.0 ? 1.0 : 0.0, 4.0,
      dt);
  const double wheelieTarget =
      state.trickBlend * 0.3 +
      (state.airborne ? state.verticalVelocity * 0.025 : 0.0);
  state.wheelie =
      pelican::damp(state.wheelie, wheelieTarget, 6.0, dt);
}

[[nodiscard]] SourceRideInput sourceInputForScenario(std::string_view id,
                                                      double tBefore) {
  SourceRideInput input;
  if (id == "acceleration") {
    input.accelerate = tBefore < 10.0;
  } else if (id == "braking") {
    input.brake = tBefore < 10.0;
  } else if (id == "lateral") {
    input.steerRight = tBefore < 2.0;
    input.steerLeft = tBefore >= 4.0 && tBefore < 6.0;
  }
  return input;
}

[[nodiscard]] double sourceRideColumn(const SourceRideState& state,
                                      std::string_view column, int frame) {
  if (column == "frame") {
    return static_cast<double>(frame);
  }
  if (column == "time") {
    return state.time;
  }
  if (column == "speed") {
    return state.speed;
  }
  if (column == "distance") {
    return state.distance;
  }
  if (column == "lane") {
    return state.lane;
  }
  if (column == "laneV") {
    return state.laneVelocity;
  }
  if (column == "latAcc") {
    return state.lateralAcceleration;
  }
  if (column == "lean") {
    return state.lean;
  }
  if (column == "steer") {
    return state.steer;
  }
  if (column == "y") {
    return state.verticalPosition;
  }
  if (column == "vy") {
    return state.verticalVelocity;
  }
  if (column == "gear") {
    return static_cast<double>(state.gear);
  }
  if (column == "cadence") {
    return state.cadenceRpm;
  }
  if (column == "wheel") {
    return state.wheelAngle;
  }
  if (column == "crank") {
    return state.crankAngle;
  }
  if (column == "accel") {
    return state.accelerationVisual;
  }
  if (column == "wheelie") {
    return state.wheelie;
  }
  fail("Unknown numeric ride column: " + std::string(column));
  return 0.0;
}

[[nodiscard]] bool sourceRideBoolColumn(const SourceRideState& state,
                                        std::string_view column) {
  if (column == "airborne") {
    return state.airborne;
  }
  if (column == "pedaling") {
    return state.pedaling;
  }
  fail("Unknown bool ride column: " + std::string(column));
  return false;
}

[[nodiscard]] std::pair<int, double> sourceAutomaticGearProbe(int gear,
                                                              double speed) {
  SourceRideState state;
  state.gear = gear;
  state.speed = speed;
  state.time = 9.0;
  state.animationTime = 9.0;
  state.lastManualGearTime = -99.0;
  sourceUpdateRide(state, SourceRideSettings{}, SourceRideInput{}, 0.0);
  return {state.gear, state.cadenceRpm};
}

struct SourceFishSpawn {
  double lane{0.0};
  double y{0.0};
  bool golden{false};
  double phase{0.0};
};

[[nodiscard]] SourceFishSpawn sourceSpawnFish(Mulberry32& random) {
  SourceFishSpawn result;
  const std::size_t laneIndex = std::min(
      pelican::kFishLaneCount - 1U,
      static_cast<std::size_t>(random.nextDouble() *
                               static_cast<double>(pelican::kFishLaneCount)));
  result.lane = pelican::kFishLanes[laneIndex];
  result.y = 1.3 + random.nextDouble() * 0.25;
  result.golden = random.nextDouble() < 0.12;
  result.phase = random.nextDouble() * pelican::kTau;
  return result;
}

struct GoldenCoverage {
  std::size_t primitiveCases{0U};
  std::size_t mulberryValues{0U};
  std::size_t wavePhaseCases{0U};
  std::size_t wavePhaseValues{0U};
  std::size_t waveHeightCases{0U};
  std::size_t terrainCases{0U};
  std::size_t ikCases{0U};
  std::size_t rideScenarios{0U};
  std::size_t rideFrames{0U};
  std::size_t rideNumericChecks{0U};
  std::size_t rideBooleanChecks{0U};
  std::size_t gearProbes{0U};
  std::size_t fishSpawns{0U};
  std::size_t achievementDefinitions{0U};
  std::size_t achievementThresholds{0U};
};

void verifyPrimitives(const JsonValue& root, GoldenCoverage& coverage) {
  const JsonValue& primitives = root.at("primitives");
  for (const JsonValue& item : primitives.at("clamp").asArray()) {
    const auto args = jsonNumberArray(item.at("args"));
    require(args.size() == 3U, "clamp golden args size");
    requireNear(pelican::clamp(args[0], args[1], args[2]),
                item.at("value").asNumber(), 1e-12, "golden clamp");
    ++coverage.primitiveCases;
  }
  for (const JsonValue& item : primitives.at("lerp").asArray()) {
    const auto args = jsonNumberArray(item.at("args"));
    require(args.size() == 3U, "lerp golden args size");
    requireNear(pelican::lerp(args[0], args[1], args[2]),
                item.at("value").asNumber(), 1e-12, "golden lerp");
    ++coverage.primitiveCases;
  }
  for (const JsonValue& item : primitives.at("damp").asArray()) {
    const auto args = jsonNumberArray(item.at("args"));
    require(args.size() == 4U, "damp golden args size");
    requireNear(pelican::damp(args[0], args[1], args[2], args[3]),
                item.at("value").asNumber(), 1e-12, "golden damp");
    ++coverage.primitiveCases;
  }
  for (const JsonValue& item : primitives.at("smoothstep").asArray()) {
    const auto args = jsonNumberArray(item.at("args"));
    require(args.size() == 3U, "smoothstep golden args size");
    requireNear(pelican::smoothstep(args[0], args[1], args[2]),
                item.at("value").asNumber(), 1e-12,
                "golden smoothstep");
    ++coverage.primitiveCases;
  }
}

void verifyMulberry(const JsonValue& root, GoldenCoverage& coverage) {
  const JsonValue& mulberry = root.at("mulberry32");
  Mulberry32 primary(seedToU32(mulberry.at("seed").asNumber()));
  const auto& first32 = mulberry.at("first32").asArray();
  require(first32.size() == 32U, "mulberry32.first32 must have 32 values");
  for (std::size_t index = 0; index < first32.size(); ++index) {
    const std::uint32_t expected = randomDoubleToU32(first32[index].asNumber());
    require(primary.nextU32() == expected,
            "mulberry32.first32 mismatch at " + std::to_string(index));
    ++coverage.mulberryValues;
  }

  const auto& additional = mulberry.at("additionalSeeds").asArray();
  require(additional.size() == 4U, "mulberry32 additional seed count");
  for (const JsonValue& item : additional) {
    Mulberry32 random(seedToU32(item.at("seed").asNumber()));
    const auto& expectedValues = item.at("first8").asArray();
    require(expectedValues.size() == 8U,
            "mulberry32 additional first8 size");
    for (std::size_t index = 0; index < expectedValues.size(); ++index) {
      const std::uint32_t expected =
          randomDoubleToU32(expectedValues[index].asNumber());
      require(random.nextU32() == expected,
              "mulberry32 additional seed mismatch at " +
                  std::to_string(index));
      ++coverage.mulberryValues;
    }
  }
}

void verifyEnvironment(const JsonValue& root, GoldenCoverage& coverage) {
  const JsonValue& gerstner = root.at("gerstner");
  requireNear(gerstner.at("seaLevel").asNumber(), pelican::kSeaLevel, 0.0,
              "golden sea level");
  requireNear(gerstner.at("shoreZ").asNumber(), pelican::kShoreZ, 0.0,
              "golden shore z");
  const auto& waves = gerstner.at("waves").asArray();
  require(waves.size() == pelican::kWaveCount, "golden wave count");
  const auto& actualWaves = pelican::oceanWaves();
  for (std::size_t index = 0; index < waves.size(); ++index) {
    const auto direction = jsonNumberArray(waves[index].at("direction"));
    require(direction.size() == 2U, "golden wave direction size");
    requireNear(actualWaves[index].direction.x, direction[0], 0.0,
                "golden wave direction x");
    requireNear(actualWaves[index].direction.y, direction[1], 0.0,
                "golden wave direction y");
    requireNear(actualWaves[index].steepness,
                waves[index].at("steepness").asNumber(), 0.0,
                "golden wave steepness");
    requireNear(actualWaves[index].wavelength,
                waves[index].at("wavelength").asNumber(), 0.0,
                "golden wave wavelength");
  }

  for (const JsonValue& item : gerstner.at("wavePhases").asArray()) {
    const auto actual = pelican::gerstnerWavePhasesSourceParity(
        item.at("distance").asNumber(), item.at("time").asNumber());
    const auto& expected64 = item.at("float64").asArray();
    const auto& expected32 = item.at("float32").asArray();
    require(expected64.size() == actual.size() &&
                expected32.size() == actual.size(),
            "golden wave phase vector size");
    for (std::size_t index = 0; index < actual.size(); ++index) {
      const double expectedDouble = expected64[index].asNumber();
      requireNear(actual[index], expectedDouble, 1e-12,
                  "golden wave phase float64");
      const float actualFloat = static_cast<float>(actual[index]);
      requireNear(static_cast<double>(actualFloat),
                  expected32[index].asNumber(), 2e-6,
                  "golden wave phase float32");
      ++coverage.wavePhaseValues;
    }
    ++coverage.wavePhaseCases;
  }

  for (const JsonValue& item : gerstner.at("waveHeight").asArray()) {
    requireNear(
        pelican::gerstnerWaveHeight(
            item.at("x").asNumber(), item.at("z").asNumber(),
            item.at("time").asNumber(), item.at("amp").asNumber()),
        item.at("value").asNumber(), 1e-9, "golden wave height");
    ++coverage.waveHeightCases;
  }

  for (const JsonValue& item : root.at("terrainHeight").asArray()) {
    requireNear(pelican::terrainHeight(item.at("x").asNumber(),
                                       item.at("z").asNumber()),
                item.at("value").asNumber(), 1e-9,
                "golden terrain height");
    ++coverage.terrainCases;
  }

  for (const JsonValue& item : root.at("solveTwoBone").asArray()) {
    const auto rootPoint = jsonNumberArray(item.at("A"));
    const auto targetPoint = jsonNumberArray(item.at("T"));
    const auto polePoint = jsonNumberArray(item.at("pole"));
    const auto expectedMid = jsonNumberArray(item.at("outMid"));
    const auto expectedEnd = jsonNumberArray(item.at("outEnd"));
    require(rootPoint.size() == 3U && targetPoint.size() == 3U &&
                polePoint.size() == 3U && expectedMid.size() == 3U &&
                expectedEnd.size() == 3U,
            "golden solveTwoBone vector size");
    Vec3 mid;
    Vec3 end;
    const bool reachable = pelican::solveTwoBone(
        Vec3{rootPoint[0], rootPoint[1], rootPoint[2]},
        Vec3{targetPoint[0], targetPoint[1], targetPoint[2]},
        item.at("a").asNumber(), item.at("b").asNumber(),
        Vec3{polePoint[0], polePoint[1], polePoint[2]}, mid, end);
    require(reachable == item.at("reachable").asBool(),
            "golden solveTwoBone reachability");
    requireVecNear(mid, Vec3{expectedMid[0], expectedMid[1], expectedMid[2]},
                   1e-12, "golden solveTwoBone mid");
    requireVecNear(end, Vec3{expectedEnd[0], expectedEnd[1], expectedEnd[2]},
                   1e-12, "golden solveTwoBone end");
    ++coverage.ikCases;
  }
}

void verifyRideTrajectories(const JsonValue& root, GoldenCoverage& coverage) {
  const JsonValue& rides = root.at("rideTrajectories");
  const double dt = rides.at("dt").asNumber();
  const int frames = jsonInt(rides.at("frames"));
  requireNear(dt, pelican::kFixedStepSeconds, 0.0, "golden ride dt");
  require(frames == 600, "golden ride frame count metadata");

  std::vector<std::string> columns;
  for (const JsonValue& value : rides.at("columns").asArray()) {
    columns.push_back(value.asString());
  }
  constexpr std::array<std::string_view, 17> numericColumns{{
      "frame", "time", "speed", "distance", "lane", "laneV",
      "latAcc", "lean", "steer", "y", "vy", "gear", "cadence",
      "wheel", "crank", "accel", "wheelie",
  }};
  constexpr std::array<std::string_view, 2> booleanColumns{{
      "airborne", "pedaling",
  }};
  for (std::string_view column : numericColumns) {
    require(std::find(columns.begin(), columns.end(), column) != columns.end(),
            "golden ride missing numeric column " + std::string(column));
  }
  for (std::string_view column : booleanColumns) {
    require(std::find(columns.begin(), columns.end(), column) != columns.end(),
            "golden ride missing bool column " + std::string(column));
  }

  const auto& scenarios = rides.at("scenarios").asArray();
  require(scenarios.size() == 5U, "golden ride scenario count");
  for (const JsonValue& scenario : scenarios) {
    const std::string& id = scenario.at("id").asString();
    const JsonValue& settingsValue = scenario.at("settings");
    SourceRideSettings settings;
    settings.cruiseSpeed = settingsValue.at("cruise").asNumber();
    settings.autopilot = settingsValue.at("autopilot").asBool();
    settings.autoGear = settingsValue.at("autoGear").asBool();
    SourceRideState state;
    state.speed = settings.cruiseSpeed * 0.6;
    const auto& rows = scenario.at("rows").asArray();
    require(rows.size() == static_cast<std::size_t>(frames + 1),
            "golden ride rows for " + id);
    for (int frame = 0; frame <= frames; ++frame) {
      if (frame > 0) {
        const double tBefore = static_cast<double>(frame - 1) * dt;
        if (id == "jump" && frame == 1) {
          sourceJump(state);
        }
        state.animationTime += dt;
        state.time += dt;
        sourceUpdateRide(state, settings, sourceInputForScenario(id, tBefore),
                         dt);
      }
      const auto& row = rows[static_cast<std::size_t>(frame)].asArray();
      require(row.size() == columns.size(),
              "golden ride row width for " + id);
      for (std::size_t columnIndex = 0; columnIndex < columns.size();
           ++columnIndex) {
        const std::string_view column = columns[columnIndex];
        if (std::find(booleanColumns.begin(), booleanColumns.end(), column) !=
            booleanColumns.end()) {
          require(sourceRideBoolColumn(state, column) ==
                      row[columnIndex].asBool(),
                  "golden ride bool mismatch " + id + "/" +
                      std::string(column) + "/" + std::to_string(frame));
          ++coverage.rideBooleanChecks;
        } else {
          requireNear(sourceRideColumn(state, column, frame),
                      row[columnIndex].asNumber(), 1e-9,
                      "golden ride " + id + "/" + std::string(column) +
                          "/" + std::to_string(frame));
          ++coverage.rideNumericChecks;
        }
      }
      ++coverage.rideFrames;
    }
    ++coverage.rideScenarios;
  }
}

void verifyAutomaticGears(const JsonValue& root, GoldenCoverage& coverage) {
  const JsonValue& automatic = root.at("automaticGears");
  requireNear(automatic.at("targetCadenceRpm").asNumber(), 86.0, 0.0,
              "golden gear target cadence");
  const auto band = jsonNumberArray(automatic.at("shiftCadenceBandRpm"));
  require(band.size() == 2U && band[0] == 68.0 && band[1] == 102.0,
          "golden gear cadence band");
  const auto& gears = automatic.at("gears").asArray();
  require(gears.size() == pelican::kGears.size(), "golden gear count");
  for (const JsonValue& gearValue : gears) {
    const int gear = jsonInt(gearValue.at("gear"));
    require(gear >= 0 && gear < static_cast<int>(pelican::kGears.size()),
            "golden gear index range");
    require(jsonInt(gearValue.at("ring")) ==
                pelican::kGears[static_cast<std::size_t>(gear)][0] &&
                jsonInt(gearValue.at("cog")) ==
                    pelican::kGears[static_cast<std::size_t>(gear)][1],
            "golden gear teeth");
    for (std::string_view group : {"lowBoundaryProbes",
                                   "highBoundaryProbes"}) {
      const auto& probes = gearValue.at(group).asArray();
      require(probes.size() == 3U, "golden gear probe count");
      for (const JsonValue& probe : probes) {
        const auto actual =
            sourceAutomaticGearProbe(gear, probe.at("speed").asNumber());
        require(actual.first == jsonInt(probe.at("outputGear")),
                "golden gear output index");
        requireNear(actual.second, probe.at("outputCadence").asNumber(), 1e-9,
                    "golden gear output cadence");
        ++coverage.gearProbes;
      }
    }
  }
}

void verifyFishSequence(const JsonValue& root, GoldenCoverage& coverage) {
  const JsonValue& fish = root.at("fishRandomSequence");
  const auto lanes = jsonNumberArray(fish.at("lanes"));
  require(lanes.size() == pelican::kFishLanes.size(), "golden fish lane count");
  for (std::size_t index = 0; index < lanes.size(); ++index) {
    requireNear(lanes[index], pelican::kFishLanes[index], 0.0,
                "golden fish lane constant");
  }
  requireNear(fish.at("goldenProbability").asNumber(), 0.12, 0.0,
              "golden fish probability");
  Mulberry32 random(seedToU32(fish.at("seed").asNumber()));
  const auto& spawns = fish.at("spawns").asArray();
  require(spawns.size() == 32U, "golden fish spawn count");
  for (std::size_t index = 0; index < spawns.size(); ++index) {
    const SourceFishSpawn actual = sourceSpawnFish(random);
    const JsonValue& expected = spawns[index];
    require(jsonInt(expected.at("index")) == static_cast<int>(index),
            "golden fish index");
    requireNear(actual.lane, expected.at("lane").asNumber(), 0.0,
                "golden fish lane");
    requireNear(actual.y, expected.at("y").asNumber(), 1e-12,
                "golden fish y");
    require(actual.golden == expected.at("golden").asBool(),
            "golden fish golden flag");
    requireNear(actual.phase, expected.at("phase").asNumber(), 1e-12,
                "golden fish phase");
    requireNear(expected.at("x").asNumber(),
                expected.at("distance").asNumber() +
                    expected.at("ahead").asNumber(),
                0.0, "golden fish world x structure");
    ++coverage.fishSpawns;
  }
}

struct ExpectedAchievementThreshold {
  std::string_view id;
  std::string_view kind;
  double threshold;
  bool arrayThreshold;
};

void verifyAchievements(const JsonValue& root, GoldenCoverage& coverage) {
  const JsonValue& achievements = root.at("achievements");
  require(jsonInt(achievements.at("count")) ==
              static_cast<int>(pelican::kAchievementCount),
          "golden achievement count");
  const JsonValue& definitions = achievements.at("definitions");
  require(definitions.size() == pelican::kAchievementCount,
          "golden achievement definition count");
  for (std::size_t index = 0; index < pelican::kAchievementCount; ++index) {
    const Achievement achievement = static_cast<Achievement>(index);
    const std::string_view id = pelican::achievementId(achievement);
    const JsonValue* definition = definitions.find(id);
    require(definition != nullptr, "golden achievement missing id " +
                                       std::string(id));
    require(definition->type() == JsonValue::Type::Array &&
                definition->size() == 3U,
            "golden achievement definition tuple " + std::string(id));
    for (const JsonValue& text : definition->asArray()) {
      require(text.type() == JsonValue::Type::String &&
                  !text.asString().empty(),
              "golden achievement definition text " + std::string(id));
    }
    ++coverage.achievementDefinitions;
  }

  constexpr std::array<ExpectedAchievementThreshold,
                       pelican::kAchievementCount>
      expected{{
          {"fish1", "event", 1.0, false},
          {"golden", "event", 1.0, false},
          {"fish10", "gte", 10.0, false},
          {"fish50", "gte", 50.0, false},
          {"jump", "event", 1.0, false},
          {"trick", "event", 1.0, false},
          {"trick3", "gte", 3.0, false},
          {"speed30", "gte", 30.0, false},
          {"speed45", "gte", 45.0, false},
          {"km1", "gte", 1000.0, false},
          {"km5", "gte", 5000.0, false},
          {"night", "all", 0.0, true},
          {"bell10", "gte", 10.0, false},
          {"honk", "event", 1.0, false},
      }};
  const auto& thresholds = achievements.at("thresholds").asArray();
  require(thresholds.size() == expected.size(),
          "golden achievement threshold count");
  for (std::size_t index = 0; index < expected.size(); ++index) {
    const JsonValue& item = thresholds[index];
    require(item.at("id").asString() == expected[index].id,
            "golden achievement threshold id/order");
    require(item.at("kind").asString() == expected[index].kind,
            "golden achievement threshold kind");
    require(item.at("sourceCondition").type() == JsonValue::Type::String &&
                !item.at("sourceCondition").asString().empty(),
            "golden achievement source condition");
    if (expected[index].arrayThreshold) {
      const auto& threshold = item.at("threshold").asArray();
      const auto& strict = item.at("strict").asArray();
      require(threshold.size() == 3U && strict.size() == 3U,
              "golden night achievement structure");
      requireNear(threshold[0].asNumber(), 0.8, 0.0,
                  "golden night factor threshold");
      require(threshold[1].asBool(), "golden night started threshold");
      requireNear(threshold[2].asNumber(), 5.0, 0.0,
                  "golden night time threshold");
      require(strict[0].asString() == ">" &&
                  strict[1].asString() == "===" &&
                  strict[2].asString() == ">",
              "golden night strict operators");
    } else {
      requireNear(item.at("threshold").asNumber(), expected[index].threshold,
                  0.0, "golden achievement threshold value");
    }
    ++coverage.achievementThresholds;
  }
}

GoldenCoverage runGoldenReferenceVectors(const JsonValue& root) {
  require(root.at("schema").asString() ==
              "pelican-bike-reference-vectors/v1",
          "Unsupported golden schema");
  GoldenCoverage coverage;
  verifyPrimitives(root, coverage);
  verifyMulberry(root, coverage);
  verifyEnvironment(root, coverage);
  verifyRideTrajectories(root, coverage);
  verifyAutomaticGears(root, coverage);
  verifyFishSequence(root, coverage);
  verifyAchievements(root, coverage);
  return coverage;
}

bool runReferenceFileIfPresent(const std::filesystem::path& path,
                               GoldenCoverage& coverage) {
  const std::string text = readTextFile(path);
  if (text.empty()) {
    return false;
  }
  const JsonValue root = JsonParser(text).parse();
  if (const JsonValue* schema = root.find("schema");
      schema != nullptr && schema->type() == JsonValue::Type::String &&
      schema->asString() == "pelican-bike-reference-vectors/v1") {
    coverage = runGoldenReferenceVectors(root);
  } else {
    const JsonValue* expectedMulberry = root.find("mulberry32_u32");
    if (expectedMulberry != nullptr) {
      Mulberry32 random(2024U);
      for (const JsonValue& expected : expectedMulberry->asArray()) {
        require(random.nextU32() ==
                    static_cast<std::uint32_t>(expected.asNumber()),
                "fallback mulberry32_u32 mismatch");
      }
    }
    const JsonValue* expectedTerrain = root.find("terrain_height");
    if (expectedTerrain != nullptr) {
      const auto values = jsonNumberArray(*expectedTerrain);
      require(values.size() % 3U == 0U,
              "fallback terrain_height triples");
      for (std::size_t index = 0; index < values.size(); index += 3U) {
        requireNear(pelican::terrainHeight(values[index], values[index + 1U]),
                    values[index + 2U], 1e-10,
                    "fallback terrain height");
      }
    }
  }
  std::cout << "Loaded reference vectors from " << path.string() << '\n';
  return true;
}

void printCoverage(const GoldenCoverage& coverage) {
  std::cout << "Golden coverage: " << coverage.primitiveCases
            << " primitive cases; " << coverage.mulberryValues
            << " Mulberry32 values; " << coverage.wavePhaseCases
            << " wave-phase cases/" << coverage.wavePhaseValues
            << " values; " << coverage.waveHeightCases << " wave heights; "
            << coverage.terrainCases << " terrain samples; "
            << coverage.ikCases << " IK cases; " << coverage.rideScenarios
            << " ride scenarios/" << coverage.rideFrames << " frames/"
            << coverage.rideNumericChecks << " numeric/"
            << coverage.rideBooleanChecks << " boolean checks; "
            << coverage.gearProbes << " gear probes; "
            << coverage.fishSpawns << " fish spawns; "
            << coverage.achievementDefinitions << " achievement definitions/"
            << coverage.achievementThresholds << " thresholds.\n";
}

void testMath() {
  const Vec3 xAxis{1.0, 0.0, 0.0};
  const Vec3 yAxis{0.0, 1.0, 0.0};
  requireVecNear(xAxis.cross(yAxis), Vec3{0.0, 0.0, 1.0}, 1e-12,
                 "cross");
  requireNear(Vec3{3.0, 4.0, 0.0}.length(), 5.0, 1e-12, "length");
  requireNear(pelican::clamp(12.0, 0.0, 10.0), 10.0, 0.0, "clamp");
  requireNear(pelican::lerp(2.0, 6.0, 0.25), 3.0, 1e-12, "lerp");
  requireNear(pelican::smoothstep(0.0, 1.0, 0.5), 0.5, 1e-12,
              "smoothstep");
  requireNear(pelican::damp(0.0, 1.0, 2.0, 0.25),
              1.0 - std::exp(-0.5), 1e-12, "damp");

  const Quat quarterTurn =
      Quat::fromAxisAngle(Vec3{0.0, 0.0, 1.0}, pelican::kPi * 0.5);
  requireVecNear(quarterTurn.rotate(xAxis), yAxis, 1e-12,
                 "quaternion rotate");
  const Mat4 transform = Mat4::compose(Vec3{2.0, 3.0, 4.0}, quarterTurn,
                                       Vec3{2.0, 2.0, 2.0});
  const Vec3 transformed = transform.transformPoint(Vec3{1.0, 0.0, 0.0});
  requireVecNear(transformed, Vec3{2.0, 5.0, 4.0}, 1e-12,
                 "matrix compose");
  requireVecNear(transform.inverse().transformPoint(transformed),
                 Vec3{1.0, 0.0, 0.0}, 1e-10, "matrix inverse");
}

void testRandom() {
  constexpr std::array<std::uint32_t, 8> expected{{
      3486492848U, 3052955074U, 2793987405U, 2943453892U,
      2228833736U, 2858743618U, 1547667217U, 681987076U,
  }};
  Mulberry32 random(2024U);
  for (std::size_t index = 0; index < expected.size(); ++index) {
    require(random.nextU32() == expected[index],
            "Mulberry32 fixed vector mismatch at index " +
                std::to_string(index));
  }
}

void testEnvironment() {
  pelican::ImprovedNoise noise;
  requireNear(noise.noise(0.0, 0.0, 0.0), 0.0, 1e-15,
              "ImprovedNoise origin");
  requireNear(noise.noise(0.1, 0.2, 0.3), 0.3512292487811072, 1e-12,
              "ImprovedNoise sample");
  requireNear(pelican::terrainHeight(0.0, 0.0), -0.06, 1e-12,
              "terrain road edge");
  requireNear(pelican::terrainHeight(0.0, -3.0), -0.08, 1e-12,
              "terrain near beach");
  const double wave = pelican::gerstnerWaveHeight(20.0, -30.0, 4.0, 1.0);
  require(std::isfinite(wave), "Gerstner height must be finite");
  const auto phases = pelican::gerstnerWavePhases(1.0e12, 12345.0);
  for (double phase : phases) {
    require(std::isfinite(phase), "Gerstner phase must be finite");
    require(std::abs(phase) < pelican::kTau + 1e-12,
            "Gerstner phase must be reduced modulo TAU");
  }

  Vec3 mid;
  Vec3 end;
  const bool reachable = pelican::solveTwoBone(
      Vec3{0.0, 0.0, 0.0}, Vec3{1.0, 0.0, 0.0}, 1.0, 1.0,
      Vec3{0.0, 1.0, 0.0}, mid, end);
  require(reachable, "two-bone target should be reachable");
  requireNear(mid.length(), 1.0, 1e-10, "two-bone first length");
  requireNear((end - mid).length(), 1.0, 2e-3,
              "two-bone second length");
}

void testSimulationFreezeAndAccumulator() {
  GameSimulation simulation;
  const auto initial = simulation.snapshot();
  InputState idle;
  require(simulation.advance(1.0, idle) == 0U,
          "pre-start simulation must not step");
  const auto frozen = simulation.snapshot();
  requireNear(frozen.time, initial.time, 0.0, "pre-start time freeze");
  requireNear(frozen.distance, initial.distance, 0.0,
              "pre-start distance freeze");
  requireNear(frozen.hour, initial.hour, 0.0, "pre-start hour freeze");
  requireNear(frozen.camera.cinematicShotTime,
              initial.camera.cinematicShotTime, 0.0,
              "pre-start camera schedule freeze");

  InputState start;
  start.startPressed = true;
  require(simulation.advance(0.0, start) == 0U,
          "start command does not need a fixed step");
  require(simulation.state().started, "simulation must start");
  require(containsEvent(simulation.consumeEvents(), EventType::Started),
          "start event missing");

  require(simulation.advance(1.0, idle) == 4U,
          "single host frame must be capped at four fixed steps");
  require(simulation.state().tick == 4U, "tick count after catch-up cap");
  requireNear(simulation.state().time, 4.0 / 60.0, 1e-12,
              "fixed-step time after cap");

  simulation.setPaused(true);
  (void)simulation.consumeEvents();
  const auto paused = simulation.snapshot();
  require(simulation.advance(0.25, idle) == 0U,
          "paused simulation must not step");
  requireNear(simulation.state().time, paused.time, 0.0,
              "paused time freeze");
  requireNear(simulation.state().distance, paused.distance, 0.0,
              "paused distance freeze");
  requireNear(simulation.state().hour, paused.hour, 0.0,
              "paused hour freeze");
  requireNear(simulation.state().camera.cinematicShotTime,
              static_cast<double>(paused.camera.cinematicShotTime), 1e-8,
              "paused camera schedule freeze");
}

void testSimulationGameplayAndEvents() {
  Settings settings;
  settings.cruiseSpeed = 7.5;
  settings.autopilot = false;
  settings.autoGear = false;
  settings.timeFlow = true;
  settings.hour = 17.35;
  GameSimulation simulation(settings, 2024U, 111U);
  simulation.start();
  (void)simulation.consumeEvents();

  InputState input;
  input.accelerate = true;
  input.steerRight = true;
  for (int index = 0; index < 120; ++index) {
    simulation.step(input);
  }
  require(simulation.state().tick == 120U, "two seconds fixed tick count");
  requireNear(simulation.state().time, 2.0, 1e-12,
              "two seconds fixed simulation time");
  require(simulation.state().distance > 0.0, "distance must advance");
  require(simulation.state().lane > 0.9, "right steering must move lane");
  requireNear(simulation.state().hour, 17.40, 1e-10,
              "day-night hour progression");

  InputState commands;
  commands.jumpPressed = true;
  commands.trickPressed = true;
  commands.bellPressed = true;
  commands.honkPressed = true;
  commands.gearUpPressed = true;
  commands.nextCameraPressed = true;
  simulation.step(commands);
  const auto events = simulation.consumeEvents();
  require(containsEvent(events, EventType::Jumped), "jump event missing");
  require(containsEvent(events, EventType::TrickStarted),
          "trick event missing");
  require(containsEvent(events, EventType::BellRung), "bell event missing");
  require(containsEvent(events, EventType::Honked), "honk event missing");
  require(containsEvent(events, EventType::GearChanged),
          "gear event missing");
  require(containsEvent(events, EventType::CameraChanged),
          "camera event missing");
  require(containsAchievement(events, Achievement::FirstJump),
          "jump achievement missing");
  require(containsAchievement(events, Achievement::FirstTrick),
          "trick achievement missing");
  require(containsAchievement(events, Achievement::FirstHonk),
          "honk achievement missing");

  for (int index = 0; index < 250; ++index) {
    simulation.step(InputState{});
  }
  require(!simulation.state().airborne, "jump must land");
  requireNear(simulation.state().trickTimeRemaining, 0.0, 1e-12,
              "3.4 second trick timer must expire");
  require(simulation.snapshot().activeFishCount <= pelican::kFishPoolSize,
          "fish snapshot must respect pool capacity");
}

void testRngSeparationAndDeterminism() {
  Settings settings;
  settings.autopilot = true;
  GameSimulation a(settings, 2024U, 1U);
  GameSimulation b(settings, 2024U, 999U);
  a.start();
  b.start();
  (void)a.consumeEvents();
  (void)b.consumeEvents();

  for (int index = 0; index < 100; ++index) {
    (void)a.nextVisualRandom();
  }
  for (int index = 0; index < 2400; ++index) {
    const InputState input{};
    a.step(input);
    b.step(input);
  }

  const auto sa = a.snapshot();
  const auto sb = b.snapshot();
  requireNear(sa.distance, sb.distance, 0.0,
              "visual RNG must not alter distance");
  requireNear(sa.lane, sb.lane, 0.0, "visual RNG must not alter autopilot");
  require(a.gameplayRandomState() == b.gameplayRandomState(),
          "visual RNG must not consume gameplay RNG");
  require(sa.activeFishCount == sb.activeFishCount,
          "visual RNG must not alter fish population");
  for (std::size_t index = 0; index < sa.activeFishCount; ++index) {
    require(sa.fish[index].poolIndex == sb.fish[index].poolIndex,
            "fish pool index determinism");
    require(sa.fish[index].golden == sb.fish[index].golden,
            "golden fish determinism");
    requireNear(sa.fish[index].localPosition.x,
                sb.fish[index].localPosition.x, 0.0,
                "fish local x determinism");
    requireNear(sa.fish[index].localPosition.z,
                sb.fish[index].localPosition.z, 0.0,
                "fish lane determinism");
  }

  require(sa.distance > 100.0, "deterministic run should travel far enough");
  require(sa.wavePhases.size() == pelican::kWaveCount,
          "snapshot must expose all wave phases");
}

}  // namespace

int main(int argc, char** argv) {
  try {
    GoldenCoverage coverage;
    bool loadedReferences = false;
    if (argc > 1) {
      loadedReferences = runReferenceFileIfPresent(argv[1], coverage);
      require(loadedReferences,
              "Explicit reference vector file could not be read");
    } else {
      loadedReferences = runReferenceFileIfPresent(
          std::filesystem::path{"reference-vectors.json"}, coverage);
    }

    testMath();
    testRandom();
    testEnvironment();
    testSimulationFreezeAndAccumulator();
    testSimulationGameplayAndEvents();
    testRngSeparationAndDeterminism();

    if (!loadedReferences) {
      std::cout << "reference-vectors.json not present; used compiled fixed "
                   "assertions.\n";
    } else if (coverage.rideScenarios > 0U) {
      printCoverage(coverage);
    }
    std::cout << "pelican_coregame_tests: all checks passed\n";
    return EXIT_SUCCESS;
  } catch (const std::exception& error) {
    std::cerr << "pelican_coregame_tests: " << error.what() << '\n';
    return EXIT_FAILURE;
  }
}
