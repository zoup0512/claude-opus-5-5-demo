#pragma once

#include "Geometry.h"
#include "SceneGles.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace pelican::scene {

class ShaderProgram {
public:
    ShaderProgram() = default;
    ~ShaderProgram();
    ShaderProgram(const ShaderProgram&) = delete;
    ShaderProgram& operator=(const ShaderProgram&) = delete;
    ShaderProgram(ShaderProgram&& other) noexcept;
    ShaderProgram& operator=(ShaderProgram&& other) noexcept;

    bool create(const char* vertexSource, const char* fragmentSource, std::string* error = nullptr);
    void destroy();
    void use() const;
    GLuint id() const { return id_; }
    explicit operator bool() const { return id_ != 0; }

    GLint uniform(const char* name) const;
    void set(const char* name, float value) const;
    void set(const char* name, int value) const;
    void set(const char* name, const Vec2& value) const;
    void set(const char* name, const Vec3& value) const;
    void set(const char* name, const Mat4& value) const;
    void setFloatArray(const char* name, const float* values, GLsizei count) const;

private:
    GLuint id_ = 0;
};

class DynamicBuffer {
public:
    DynamicBuffer() = default;
    ~DynamicBuffer();
    DynamicBuffer(const DynamicBuffer&) = delete;
    DynamicBuffer& operator=(const DynamicBuffer&) = delete;
    DynamicBuffer(DynamicBuffer&& other) noexcept;
    DynamicBuffer& operator=(DynamicBuffer&& other) noexcept;

    bool create(GLenum target, size_t capacityBytes, GLenum usage = GL_DYNAMIC_DRAW);
    bool upload(const void* data, size_t bytes, size_t offset = 0);
    void bind() const;
    void destroy();
    GLuint id() const { return id_; }
    size_t capacity() const { return capacityBytes_; }

private:
    GLuint id_ = 0;
    GLenum target_ = GL_ARRAY_BUFFER;
    GLenum usage_ = GL_DYNAMIC_DRAW;
    size_t capacityBytes_ = 0;
};

class Mesh {
public:
    Mesh() = default;
    ~Mesh();
    Mesh(const Mesh&) = delete;
    Mesh& operator=(const Mesh&) = delete;
    Mesh(Mesh&& other) noexcept;
    Mesh& operator=(Mesh&& other) noexcept;

    bool create(const CpuMesh& mesh, bool dynamic = false, size_t vertexCapacity = 0, size_t indexCapacity = 0);
    bool update(const CpuMesh& mesh);
    void draw(GLenum primitive = GL_TRIANGLES) const;
    void drawInstanced(GLsizei instanceCount, GLenum primitive = GL_TRIANGLES) const;
    void bind() const;
    void destroy();

    GLuint vao() const { return vao_; }
    GLuint vbo() const { return vertexBuffer_; }
    GLuint ibo() const { return indexBuffer_; }
    explicit operator bool() const { return vao_ != 0; }
    GLsizei indexCount() const { return indexCount_; }
    GLenum indexType() const { return indexType_; }

private:
    GLuint vao_ = 0;
    GLuint vertexBuffer_ = 0;
    GLuint indexBuffer_ = 0;
    GLsizei indexCount_ = 0;
    GLenum indexType_ = GL_UNSIGNED_INT;
    size_t vertexCapacityBytes_ = 0;
    size_t indexCapacityBytes_ = 0;
    bool dynamic_ = false;
};

class InstancedBuffer {
public:
    InstancedBuffer() = default;
    ~InstancedBuffer();
    InstancedBuffer(const InstancedBuffer&) = delete;
    InstancedBuffer& operator=(const InstancedBuffer&) = delete;
    InstancedBuffer(InstancedBuffer&& other) noexcept;
    InstancedBuffer& operator=(InstancedBuffer&& other) noexcept;

    bool create(const Mesh& mesh, size_t capacity);
    bool update(const std::vector<InstanceData>& instances);
    void bind(const Mesh& mesh) const;
    void destroy();
    explicit operator bool() const { return buffer_ != 0; }
    GLsizei count() const { return count_; }

private:
    GLuint buffer_ = 0;
    size_t capacity_ = 0;
    GLsizei count_ = 0;
};

class Texture2D {
public:
    Texture2D() = default;
    ~Texture2D();
    Texture2D(const Texture2D&) = delete;
    Texture2D& operator=(const Texture2D&) = delete;
    Texture2D(Texture2D&& other) noexcept;
    Texture2D& operator=(Texture2D&& other) noexcept;

    bool create(int width, int height, GLenum internalFormat, GLenum format, GLenum type,
                const void* pixels = nullptr, bool linear = true, bool repeat = false);
    void bind(GLuint unit = 0) const;
    void destroy();
    GLuint id() const { return id_; }
    explicit operator bool() const { return id_ != 0; }
    int width() const { return width_; }
    int height() const { return height_; }

private:
    GLuint id_ = 0;
    int width_ = 0;
    int height_ = 0;
};

class Framebuffer {
public:
    Framebuffer() = default;
    ~Framebuffer();
    Framebuffer(const Framebuffer&) = delete;
    Framebuffer& operator=(const Framebuffer&) = delete;
    Framebuffer(Framebuffer&& other) noexcept;
    Framebuffer& operator=(Framebuffer&& other) noexcept;

    bool create(int width, int height, GLenum colorInternalFormat, GLenum colorFormat, GLenum colorType,
                bool withDepth);
    void bind() const;
    static void bindDefault();
    void destroy();
    GLuint id() const { return id_; }
    explicit operator bool() const { return id_ != 0; }
    const Texture2D& color() const { return color_; }
    bool hasDepth() const { return depth_ != 0; }
    int width() const { return width_; }
    int height() const { return height_; }

private:
    GLuint id_ = 0;
    GLuint depth_ = 0;
    Texture2D color_{};
    int width_ = 0;
    int height_ = 0;
};

std::vector<uint8_t> makeNoiseTextureRgba(int width, int height, uint32_t seed);
std::vector<uint8_t> makeRoadTextureRgba(int width, int height, uint32_t seed);

}  // namespace pelican::scene
