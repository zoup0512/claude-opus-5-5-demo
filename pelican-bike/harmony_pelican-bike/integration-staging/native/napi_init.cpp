#include <cmath>
#include <string>
#include <utility>

#include <napi/native_api.h>

#include "pelican_renderer.h"

namespace {

using pelican::integration::PelicanRenderer;
using pelican::integration::SettingValue;

napi_value Undefined(napi_env env)
{
    napi_value value = nullptr;
    napi_get_undefined(env, &value);
    return value;
}

napi_value InvalidArgs(napi_env env, const char* message)
{
    napi_throw_type_error(env, nullptr, message);
    return nullptr;
}

bool GetString(napi_env env, napi_value value, std::string& output)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    std::string buffer(length + 1, '\0');
    size_t written = 0;
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &written) != napi_ok) {
        return false;
    }
    buffer.resize(written);
    output = std::move(buffer);
    return true;
}

bool GetSettingValue(napi_env env, napi_value value, SettingValue& output)
{
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, value, &type) != napi_ok) {
        return false;
    }
    if (type == napi_boolean) {
        bool boolean = false;
        if (napi_get_value_bool(env, value, &boolean) != napi_ok) {
            return false;
        }
        output = boolean;
        return true;
    }
    if (type == napi_number) {
        double number = 0.0;
        if (napi_get_value_double(env, value, &number) != napi_ok || !std::isfinite(number)) {
            return false;
        }
        output = number;
        return true;
    }
    if (type == napi_string) {
        std::string text;
        if (!GetString(env, value, text)) {
            return false;
        }
        output = std::move(text);
        return true;
    }
    return false;
}

void SetDouble(napi_env env, napi_value object, const char* name, double value)
{
    napi_value property = nullptr;
    napi_create_double(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

void SetInt(napi_env env, napi_value object, const char* name, int32_t value)
{
    napi_value property = nullptr;
    napi_create_int32(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

void SetBool(napi_env env, napi_value object, const char* name, bool value)
{
    napi_value property = nullptr;
    napi_get_boolean(env, value, &property);
    napi_set_named_property(env, object, name, property);
}

void SetString(napi_env env, napi_value object, const char* name, const std::string& value)
{
    napi_value property = nullptr;
    napi_create_string_utf8(env, value.c_str(), value.size(), &property);
    napi_set_named_property(env, object, name, property);
}

napi_value SnapshotToJs(napi_env env, const pelican::integration::HudSnapshot& snapshot)
{
    napi_value object = nullptr;
    napi_create_object(env, &object);
    SetDouble(env, object, "speedKmh", snapshot.speedKmh);
    SetDouble(env, object, "cadence", snapshot.cadence);
    SetInt(env, object, "gear", snapshot.gear);
    SetInt(env, object, "gearCount", snapshot.gearCount);
    SetDouble(env, object, "distanceKm", snapshot.distanceKm);
    SetInt(env, object, "fish", snapshot.fish);
    SetInt(env, object, "achievements", snapshot.achievements);
    SetInt(env, object, "achievementTotal", snapshot.achievementTotal);
    SetDouble(env, object, "hour", snapshot.hour);
    SetDouble(env, object, "fps", snapshot.fps);
    SetString(env, object, "quality", snapshot.quality);
    SetString(env, object, "camera", snapshot.camera);
    SetBool(env, object, "night", snapshot.night);
    SetBool(env, object, "started", snapshot.started);
    SetBool(env, object, "paused", snapshot.paused);
    return object;
}

napi_value Initialize(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    napi_value options = argc > 0 ? argv[0] : nullptr;
    const bool initialized = PelicanRenderer::Instance().Initialize(env, options);
    napi_value result = nullptr;
    napi_get_boolean(env, initialized, &result);
    return result;
}

napi_value Start(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        return InvalidArgs(env, "start(withSound) requires a boolean");
    }
    bool withSound = false;
    if (napi_get_value_bool(env, argv[0], &withSound) != napi_ok) {
        return InvalidArgs(env, "withSound must be a boolean");
    }
    napi_value result = nullptr;
    napi_get_boolean(env, PelicanRenderer::Instance().Start(withSound), &result);
    return result;
}

napi_value SetPaused(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    bool paused = false;
    if (argc < 1 || napi_get_value_bool(env, argv[0], &paused) != napi_ok) {
        return InvalidArgs(env, "setPaused(paused) requires a boolean");
    }
    PelicanRenderer::Instance().SetPaused(paused);
    return Undefined(env);
}

napi_value SetInput(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string name;
    bool pressed = false;
    if (argc < 2 || !GetString(env, argv[0], name) ||
        napi_get_value_bool(env, argv[1], &pressed) != napi_ok) {
        return InvalidArgs(env, "setInput(name, pressed) requires string and boolean arguments");
    }
    PelicanRenderer::Instance().SetInput(name, pressed);
    return Undefined(env);
}

napi_value TriggerAction(napi_env env, napi_callback_info info)
{
    size_t argc = 3;
    napi_value argv[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string action;
    if (argc < 1 || !GetString(env, argv[0], action)) {
        return InvalidArgs(env, "triggerAction(action, x?, y?) requires an action string");
    }
    double x = 0.0;
    double y = 0.0;
    bool hasCoordinates = false;
    if (argc >= 3 && napi_get_value_double(env, argv[1], &x) == napi_ok &&
        napi_get_value_double(env, argv[2], &y) == napi_ok && std::isfinite(x) && std::isfinite(y)) {
        hasCoordinates = true;
    }
    PelicanRenderer::Instance().TriggerAction(action, x, y, hasCoordinates);
    return Undefined(env);
}

napi_value SetCamera(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string camera;
    if (argc < 1 || !GetString(env, argv[0], camera)) {
        return InvalidArgs(env, "setCamera(camera) requires a string");
    }
    PelicanRenderer::Instance().SetCamera(camera);
    return Undefined(env);
}

napi_value SetSetting(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    std::string name;
    SettingValue value;
    if (argc < 2 || !GetString(env, argv[0], name) || !GetSettingValue(env, argv[1], value)) {
        return InvalidArgs(env, "setSetting(name, value) requires string and boolean/number/string");
    }
    if (!PelicanRenderer::Instance().SetSetting(name, value)) {
        napi_throw_range_error(env, nullptr, "unsupported setting name or value type");
        return nullptr;
    }
    return Undefined(env);
}

napi_value GetSnapshot(napi_env env, napi_callback_info info)
{
    (void)info;
    return SnapshotToJs(env, PelicanRenderer::Instance().Snapshot());
}

napi_value SetEventCallback(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        return InvalidArgs(env, "setEventCallback(callback) requires a function or null");
    }
    if (!PelicanRenderer::Instance().SetEventCallback(env, argv[0])) {
        return nullptr;
    }
    return Undefined(env);
}

napi_value RequestScreenshot(napi_env env, napi_callback_info info)
{
    (void)info;
    PelicanRenderer::Instance().RequestScreenshot();
    return Undefined(env);
}

napi_value Dispose(napi_env env, napi_callback_info info)
{
    (void)info;
    PelicanRenderer::Instance().Dispose();
    return Undefined(env);
}

napi_value Init(napi_env env, napi_value exports)
{
    const napi_property_descriptor properties[] = {
        {"initialize", nullptr, Initialize, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setPaused", nullptr, SetPaused, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setInput", nullptr, SetInput, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"triggerAction", nullptr, TriggerAction, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setCamera", nullptr, SetCamera, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setSetting", nullptr, SetSetting, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getSnapshot", nullptr, GetSnapshot, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setEventCallback", nullptr, SetEventCallback, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"requestScreenshot", nullptr, RequestScreenshot, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dispose", nullptr, Dispose, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
    PelicanRenderer::Instance().AttachXComponent(env, exports);
    return exports;
}

static napi_module gPelicanModule = {
    NAPI_MODULE_VERSION,
    0,
    __FILE__,
    Init,
    "pelican",
    nullptr,
    {0},
};

} // namespace

extern "C" __attribute__((constructor)) void RegisterPelicanModule(void)
{
    napi_module_register(&gPelicanModule);
}
