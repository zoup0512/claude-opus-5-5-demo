/**
 * 运输船渲染器：EGL + OpenGL ES 3.0 前向渲染
 *
 * 帧数据布局（Float32Array，与 ArkTS 侧 FrameBuf 保持一致）：
 *   [0]      flags（bit0：世界渲染有效）
 *   [1..16]  世界相机 VP（列主序）
 *   [17..19] 相机位置
 *   [20]     第一人称武器层开关
 *   [21..36] 武器层 VP
 *   [37..39] 太阳方向
 *   [40..42] 太阳颜色
 *   [43..45] 半球天光
 *   [46..48] 半球地光
 *   [49..51] 雾颜色
 *   [52]     雾密度
 *   [53]     时间
 *   [54]     士兵数（最大 16）
 *   [55]     四边形数（最大 320）
 *   [56]     粒子数（最大 1200）
 *   [57]     海洋可见
 *   [58]     武器层网格 id
 *   [59..74] 武器层模型矩阵
 *   [75]     动态网格数（最大 12，手雷等）
 *   [76..79] 保留
 *   士兵（偏移 80，步长 322）：0..303 = 19 根骨骼×16 矩阵（世界空间）
 *             304 = visible(0 无 / 1 潜伏者 / 2 保卫者)，305 = 第三人称枪网格 id，306..321 = 枪模型矩阵
 *   动态网格（偏移 5232，步长 17）：0 = 网格 id，1..16 = 模型矩阵
 *   四边形（偏移 5436，步长 24）：0..2 中心，3..5 方向，6 长，7 宽，
 *             8..11 RGBA，12..15 UV 矩形，16 模式（0 相机朝向 / 1 沿法线贴片 / 2 直立 / 3 武器层 / 4 沿方向条带），
 *             17 标志（bit0 加色，bit1 关深度测试），18 纹理 id
 *   粒子（偏移 13116，步长 9）：0..2 位置，3 尺寸，4..6 RGB，7 透明度，8 纹理（偶数加色 / 奇数普通）
 */
#ifndef CF_SHIP_RENDERER_H
#define CF_SHIP_RENDERER_H

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <cstdint>
#include <unordered_map>
#include <vector>

class Renderer {
public:
    static Renderer &Instance();

    void OnSurfaceCreated(void *window, int w, int h);
    void OnSurfaceChanged(int w, int h);
    void OnSurfaceDestroyed();
    bool IsReady() const { return ready_; }
    int ViewSizePacked() const { return (width_ << 16) | (height_ & 0xFFFF); }

    void CreateTexture(int id, int w, int h, const uint8_t *rgba);
    void UploadMesh(int id, int texId, uint32_t flags, const float matParams[8], const float *vdata,
                    size_t vfloats, const uint32_t *idata, size_t icount);
    void RenderFrame(const float *f);

private:
    Renderer() = default;
    ~Renderer() = default;

    struct Mesh {
        GLuint vao = 0;
        GLuint vbo = 0;
        GLuint ibo = 0;
        uint32_t indexCount = 0;
        int texId = 0;
        float color[3] = {1, 1, 1};
        float rme[3] = {0.7f, 0.1f, 0}; // 粗糙度 / 金属度 / 自发光
        uint32_t flags = 0;             // bit0 alphaTest bit1 双面 bit2 自发光 bit3 蒙皮
    };

    struct Texture {
        GLuint tex = 0;
    };

    bool EnsureContext(void *window);
    void InitGLState();
    void ReleaseSurface();

    GLuint CompileShader(GLenum type, const char *src);
    GLuint LinkProgram(const char *vs, const char *fs);

    void DrawSky(const float *f);
    void DrawOcean(const float *f);
    void DrawStaticMeshes(const float *f);
    void DrawSoldiers(const float *f);
    void DrawDynMeshes(const float *f);
    void DrawQuads(const float *f);
    void DrawVM(const float *f);

    EGLDisplay display_ = EGL_NO_DISPLAY;
    EGLConfig config_ = nullptr;
    EGLContext context_ = EGL_NO_CONTEXT;
    EGLSurface surface_ = EGL_NO_SURFACE;
    bool glReady_ = false;
    bool ready_ = false;
    int width_ = 0;
    int height_ = 0;

    std::unordered_map<int, Mesh> meshes_;
    std::unordered_map<int, GLuint> textures_;

    GLuint progStatic_ = 0;
    GLuint progSkin_ = 0;
    GLuint progOcean_ = 0;
    GLuint progSky_ = 0;
    GLuint progQuad_ = 0;

    // uniform 位置缓存
    GLint stUVP_ = -1, stUModel_ = -1, stUTex_ = -1, stUColor_ = -1, stURME_ = -1, stUSunDir_ = -1,
          stUSunCol_ = -1, stUHemiSky_ = -1, stUHemiGnd_ = -1, stUFogCol_ = -1, stUCamPos_ = -1,
          stUFogDen_ = -1, stUAlphaTest_ = -1;
    GLint skUVP_ = -1, skUBones_ = -1, skUTex_ = -1, skUColor_ = -1, skURME_ = -1, skUSunDir_ = -1,
          skUSunCol_ = -1, skUHemiSky_ = -1, skUHemiGnd_ = -1, skUFogCol_ = -1, skUCamPos_ = -1,
          skUFogDen_ = -1, skUAlphaTest_ = -1;
    GLint ocUVP_ = -1, ocUTime_ = -1, ocUShip_ = -1, ocUWaves_ = -1, ocUCamPos_ = -1, ocUSunDir_ = -1,
          ocUSunCol_ = -1, ocUDeep_ = -1, ocUShallow_ = -1, ocUZen_ = -1, ocUHor_ = -1, ocUFogCol_ = -1,
          ocUFogDen_ = -1;
    GLint sk2UInvVP_ = -1, sk2UCamPos_ = -1, sk2USunDir_ = -1, sk2UZen_ = -1, sk2UHor_ = -1, sk2UFogCol_ = -1,
          sk2UTime_ = -1;
    GLint qdUVP_ = -1, qdUTex_ = -1;

    // 海洋网格
    GLuint oceanVao_ = 0;
    GLuint oceanVbo_ = 0;
    GLuint oceanIbo_ = 0;
    uint32_t oceanIndexCount_ = 0;

    // 天空全屏三角形
    GLuint skyVao_ = 0;
    GLuint skyVbo_ = 0;

    // 动态四边形
    GLuint quadVao_ = 0;
    GLuint quadVbo_ = 0;
    struct QuadBucket {
        std::vector<float> alpha;
        std::vector<float> add;
        std::vector<float> noDepth;
    };
    std::unordered_map<int, QuadBucket> quadBuckets_;
    std::vector<float> vmAlphaVerts_;
    std::vector<float> vmAddVerts_;

    float invVP_[16];
};

#endif // CF_SHIP_RENDERER_H
