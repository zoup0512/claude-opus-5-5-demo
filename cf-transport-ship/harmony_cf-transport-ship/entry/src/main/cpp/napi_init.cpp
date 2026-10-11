/**
 * 运输船渲染模块 NAPI 入口：
 * - 注册 gameRenderer 模块（与 ArkTS XComponent libraryname 对应）
 * - 接管 XComponent surface 生命周期（创建 / 尺寸变化 / 销毁）
 * - 导出 createTexture / uploadMesh / renderFrame / surfaceReady / viewSize
 */
#include <cstdint>
#include <hilog/log.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <napi/native_api.h>
#include "renderer.h"

#define LOG_TAG "CfShip"

static void OnSurfaceCreatedCB(OH_NativeXComponent *component, void *window)
{
    uint64_t w = 0;
    uint64_t h = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &w, &h);
    Renderer::Instance().OnSurfaceCreated(window, (int)w, (int)h);
    hilog_info(LOG_APP, LOG_TAG, "surface created %{public}dx%{public}d", (int)w, (int)h);
}

static void OnSurfaceChangedCB(OH_NativeXComponent *component, void *window)
{
    uint64_t w = 0;
    uint64_t h = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &w, &h);
    Renderer::Instance().OnSurfaceChanged((int)w, (int)h);
}

static void OnSurfaceDestroyedCB(OH_NativeXComponent *component, void *window)
{
    (void)component;
    Renderer::Instance().OnSurfaceDestroyed();
}

static void DispatchTouchEventCB(OH_NativeXComponent *component, void *window)
{
    // 触摸事件在 ArkTS 层处理，这里留空
    (void)component;
    (void)window;
}

static napi_value CreateTexture(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value argv[4] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 4) {
        return nullptr;
    }
    int32_t id = 0;
    int32_t w = 0;
    int32_t h = 0;
    napi_get_value_int32(env, argv[0], &id);
    napi_get_value_int32(env, argv[1], &w);
    napi_get_value_int32(env, argv[2], &h);
    void *data = nullptr;
    size_t len = 0;
    napi_get_typedarray_info(env, argv[3], nullptr, &len, &data, nullptr, nullptr);
    if (data == nullptr || len < (size_t)w * h * 4u) {
        return nullptr;
    }
    Renderer::Instance().CreateTexture(id, w, h, (const uint8_t *)data);
    return nullptr;
}

static napi_value UploadMesh(napi_env env, napi_callback_info info)
{
    size_t argc = 6;
    napi_value argv[6] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 6) {
        return nullptr;
    }
    int32_t id = 0;
    int32_t texId = 0;
    int32_t flags = 0;
    napi_get_value_int32(env, argv[0], &id);
    napi_get_value_int32(env, argv[1], &texId);
    napi_get_value_int32(env, argv[2], &flags);

    float matParams[8] = {1, 1, 1, 0.7f, 0.1f, 0, 0, 0};
    void *matData = nullptr;
    size_t matLen = 0;
    napi_get_typedarray_info(env, argv[3], nullptr, &matLen, &matData, nullptr, nullptr);
    if (matData != nullptr) {
        size_t n = matLen < 8 ? matLen : 8;
        for (size_t i = 0; i < n; i++) {
            matParams[i] = ((float *)matData)[i];
        }
    }
    void *vdata = nullptr;
    size_t vlen = 0;
    napi_get_typedarray_info(env, argv[4], nullptr, &vlen, &vdata, nullptr, nullptr);
    void *idata = nullptr;
    size_t ilen = 0;
    napi_get_typedarray_info(env, argv[5], nullptr, &ilen, &idata, nullptr, nullptr);
    if (vdata == nullptr || idata == nullptr) {
        return nullptr;
    }
    Renderer::Instance().UploadMesh(id, texId, (uint32_t)flags, matParams,
                                    (const float *)vdata, vlen,
                                    (const uint32_t *)idata, ilen);
    return nullptr;
}

static napi_value RenderFrame(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc < 1) {
        return nullptr;
    }
    void *fdata = nullptr;
    size_t flen = 0;
    napi_get_typedarray_info(env, argv[0], nullptr, &flen, &fdata, nullptr, nullptr);
    if (fdata == nullptr || flen < 80) {
        return nullptr;
    }
    Renderer::Instance().RenderFrame((const float *)fdata);
    return nullptr;
}

static napi_value SurfaceReady(napi_env env, napi_callback_info info)
{
    napi_value result = nullptr;
    napi_get_boolean(env, Renderer::Instance().IsReady() ? true : false, &result);
    return result;
}

static napi_value ViewSize(napi_env env, napi_callback_info info)
{
    napi_value result = nullptr;
    int wh = Renderer::Instance().ViewSizePacked();
    napi_create_int32(env, wh, &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_value exportInstance = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &exportInstance) != napi_ok) {
        return exports;
    }
    OH_NativeXComponent *nativeXComponent = nullptr;
    if (napi_unwrap(env, exportInstance, reinterpret_cast<void **>(&nativeXComponent)) != napi_ok) {
        return exports;
    }
    char idBuf[OH_XCOMPONENT_ID_LEN + 1] = {};
    uint64_t idLen = OH_XCOMPONENT_ID_LEN + 1;
    OH_NativeXComponent_GetXComponentId(nativeXComponent, idBuf, &idLen);

    static OH_NativeXComponent_Callback callback;
    callback.OnSurfaceCreated = OnSurfaceCreatedCB;
    callback.OnSurfaceChanged = OnSurfaceChangedCB;
    callback.OnSurfaceDestroyed = OnSurfaceDestroyedCB;
    callback.DispatchTouchEvent = DispatchTouchEventCB;
    OH_NativeXComponent_RegisterCallback(nativeXComponent, &callback);

    napi_property_descriptor desc[] = {
        {"createTexture", nullptr, CreateTexture, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"uploadMesh", nullptr, UploadMesh, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"renderFrame", nullptr, RenderFrame, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"surfaceReady", nullptr, SurfaceReady, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"viewSize", nullptr, ViewSize, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module gameRendererModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "gameRenderer",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterGameRendererModule(void)
{
    napi_module_register(&gameRendererModule);
}
