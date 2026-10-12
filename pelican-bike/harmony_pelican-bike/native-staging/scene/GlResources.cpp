#include "GlResources.h"

#include <algorithm>
#include <array>
#include <cstring>
#include <sstream>
#include <utility>

namespace pelican::scene {
namespace {

GLuint compileShader(GLenum type, const char* source, std::string* error) {
    GLuint shader = glCreateShader(type);
    if (!shader) {
        if (error) {
            *error = "glCreateShader returned 0";
        }
        return 0;
    }
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint status = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    if (status != GL_TRUE) {
        GLint length = 0;
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);
        std::string log(static_cast<size_t>(std::max(length, 1)), '\0');
        GLsizei written = 0;
        glGetShaderInfoLog(shader, static_cast<GLsizei>(log.size()), &written, log.data());
        if (error) {
            *error = log;
        }
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

void configureVertexAttributes() {
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), reinterpret_cast<const void*>(offsetof(Vertex, position)));
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), reinterpret_cast<const void*>(offsetof(Vertex, normal)));
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex), reinterpret_cast<const void*>(offsetof(Vertex, color)));
    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), reinterpret_cast<const void*>(offsetof(Vertex, uv)));
}

struct GpuInstance {
    float matrix[16];
    float color[4];
};

}  // namespace

ShaderProgram::~ShaderProgram() { destroy(); }
ShaderProgram::ShaderProgram(ShaderProgram&& other) noexcept : id_(std::exchange(other.id_, 0)) {}
ShaderProgram& ShaderProgram::operator=(ShaderProgram&& other) noexcept {
    if (this != &other) {
        destroy();
        id_ = std::exchange(other.id_, 0);
    }
    return *this;
}

bool ShaderProgram::create(const char* vertexSource, const char* fragmentSource, std::string* error) {
    destroy();
    std::string vertexError;
    std::string fragmentError;
    const GLuint vertex = compileShader(GL_VERTEX_SHADER, vertexSource, &vertexError);
    if (!vertex) {
        if (error) {
            *error = "vertex shader: " + vertexError;
        }
        return false;
    }
    const GLuint fragment = compileShader(GL_FRAGMENT_SHADER, fragmentSource, &fragmentError);
    if (!fragment) {
        glDeleteShader(vertex);
        if (error) {
            *error = "fragment shader: " + fragmentError;
        }
        return false;
    }
    id_ = glCreateProgram();
    glAttachShader(id_, vertex);
    glAttachShader(id_, fragment);
    glLinkProgram(id_);
    glDeleteShader(vertex);
    glDeleteShader(fragment);
    GLint status = GL_FALSE;
    glGetProgramiv(id_, GL_LINK_STATUS, &status);
    if (status != GL_TRUE) {
        GLint length = 0;
        glGetProgramiv(id_, GL_INFO_LOG_LENGTH, &length);
        std::string log(static_cast<size_t>(std::max(length, 1)), '\0');
        GLsizei written = 0;
        glGetProgramInfoLog(id_, static_cast<GLsizei>(log.size()), &written, log.data());
        if (error) {
            *error = "program link: " + log;
        }
        destroy();
        return false;
    }
    return true;
}

void ShaderProgram::destroy() {
    if (id_) {
        glDeleteProgram(id_);
        id_ = 0;
    }
}

void ShaderProgram::use() const { glUseProgram(id_); }
GLint ShaderProgram::uniform(const char* name) const { return id_ ? glGetUniformLocation(id_, name) : -1; }
void ShaderProgram::set(const char* name, float value) const {
    const GLint location = uniform(name);
    if (location >= 0) glUniform1f(location, value);
}
void ShaderProgram::set(const char* name, int value) const {
    const GLint location = uniform(name);
    if (location >= 0) glUniform1i(location, value);
}
void ShaderProgram::set(const char* name, const Vec2& value) const {
    const GLint location = uniform(name);
    if (location >= 0) glUniform2f(location, value.x, value.y);
}
void ShaderProgram::set(const char* name, const Vec3& value) const {
    const GLint location = uniform(name);
    if (location >= 0) glUniform3f(location, value.x, value.y, value.z);
}
void ShaderProgram::set(const char* name, const Mat4& value) const {
    const GLint location = uniform(name);
    if (location >= 0) glUniformMatrix4fv(location, 1, GL_FALSE, value.data());
}
void ShaderProgram::setFloatArray(const char* name, const float* values, GLsizei count) const {
    const GLint location = uniform(name);
    if (location >= 0) glUniform1fv(location, count, values);
}

DynamicBuffer::~DynamicBuffer() { destroy(); }
DynamicBuffer::DynamicBuffer(DynamicBuffer&& other) noexcept
    : id_(std::exchange(other.id_, 0)), target_(other.target_), usage_(other.usage_),
      capacityBytes_(std::exchange(other.capacityBytes_, 0)) {}
DynamicBuffer& DynamicBuffer::operator=(DynamicBuffer&& other) noexcept {
    if (this != &other) {
        destroy();
        id_ = std::exchange(other.id_, 0);
        target_ = other.target_;
        usage_ = other.usage_;
        capacityBytes_ = std::exchange(other.capacityBytes_, 0);
    }
    return *this;
}

bool DynamicBuffer::create(GLenum target, size_t capacityBytes, GLenum usage) {
    destroy();
    target_ = target;
    usage_ = usage;
    capacityBytes_ = capacityBytes;
    glGenBuffers(1, &id_);
    if (!id_) return false;
    glBindBuffer(target_, id_);
    glBufferData(target_, static_cast<GLsizeiptr>(capacityBytes_), nullptr, usage_);
    if (glGetError() != GL_NO_ERROR) {
        destroy();
        return false;
    }
    return true;
}

bool DynamicBuffer::upload(const void* data, size_t bytes, size_t offset) {
    if (!id_ || offset + bytes > capacityBytes_) return false;
    glBindBuffer(target_, id_);
    if (bytes > 0) {
        glBufferSubData(target_, static_cast<GLintptr>(offset), static_cast<GLsizeiptr>(bytes), data);
    }
    return glGetError() == GL_NO_ERROR;
}

void DynamicBuffer::bind() const { glBindBuffer(target_, id_); }
void DynamicBuffer::destroy() {
    if (id_) glDeleteBuffers(1, &id_);
    id_ = 0;
    capacityBytes_ = 0;
}

Mesh::~Mesh() { destroy(); }
Mesh::Mesh(Mesh&& other) noexcept
    : vao_(std::exchange(other.vao_, 0)), vertexBuffer_(std::exchange(other.vertexBuffer_, 0)),
      indexBuffer_(std::exchange(other.indexBuffer_, 0)), indexCount_(std::exchange(other.indexCount_, 0)),
      vertexCapacityBytes_(std::exchange(other.vertexCapacityBytes_, 0)),
      indexCapacityBytes_(std::exchange(other.indexCapacityBytes_, 0)), dynamic_(other.dynamic_) {}
Mesh& Mesh::operator=(Mesh&& other) noexcept {
    if (this != &other) {
        destroy();
        vao_ = std::exchange(other.vao_, 0);
        vertexBuffer_ = std::exchange(other.vertexBuffer_, 0);
        indexBuffer_ = std::exchange(other.indexBuffer_, 0);
        indexCount_ = std::exchange(other.indexCount_, 0);
        vertexCapacityBytes_ = std::exchange(other.vertexCapacityBytes_, 0);
        indexCapacityBytes_ = std::exchange(other.indexCapacityBytes_, 0);
        dynamic_ = other.dynamic_;
    }
    return *this;
}

bool Mesh::create(const CpuMesh& mesh, bool dynamic, size_t vertexCapacity, size_t indexCapacity) {
    destroy();
    dynamic_ = dynamic;
    vertexCapacityBytes_ = std::max(vertexCapacity * sizeof(Vertex), mesh.vertices.size() * sizeof(Vertex));
    indexCapacityBytes_ = std::max(indexCapacity * sizeof(uint32_t), mesh.indices.size() * sizeof(uint32_t));
    glGenVertexArrays(1, &vao_);
    glGenBuffers(1, &vertexBuffer_);
    glGenBuffers(1, &indexBuffer_);
    if (!vao_ || !vertexBuffer_ || !indexBuffer_) {
        destroy();
        return false;
    }
    glBindVertexArray(vao_);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer_);
    glBufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(vertexCapacityBytes_), nullptr,
                 dynamic ? GL_DYNAMIC_DRAW : GL_STATIC_DRAW);
    if (!mesh.vertices.empty()) {
        glBufferSubData(GL_ARRAY_BUFFER, 0, static_cast<GLsizeiptr>(mesh.vertices.size() * sizeof(Vertex)), mesh.vertices.data());
    }
    configureVertexAttributes();
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer_);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, static_cast<GLsizeiptr>(indexCapacityBytes_), nullptr,
                 dynamic ? GL_DYNAMIC_DRAW : GL_STATIC_DRAW);
    if (!mesh.indices.empty()) {
        glBufferSubData(GL_ELEMENT_ARRAY_BUFFER, 0, static_cast<GLsizeiptr>(mesh.indices.size() * sizeof(uint32_t)), mesh.indices.data());
    }
    indexCount_ = static_cast<GLsizei>(mesh.indices.size());
    glBindVertexArray(0);
    if (glGetError() != GL_NO_ERROR) {
        destroy();
        return false;
    }
    return true;
}

bool Mesh::update(const CpuMesh& mesh) {
    if (!vao_ || mesh.vertices.size() * sizeof(Vertex) > vertexCapacityBytes_ ||
        mesh.indices.size() * sizeof(uint32_t) > indexCapacityBytes_) {
        return false;
    }
    glBindVertexArray(vao_);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer_);
    if (!mesh.vertices.empty()) {
        glBufferSubData(GL_ARRAY_BUFFER, 0, static_cast<GLsizeiptr>(mesh.vertices.size() * sizeof(Vertex)), mesh.vertices.data());
    }
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer_);
    if (!mesh.indices.empty()) {
        glBufferSubData(GL_ELEMENT_ARRAY_BUFFER, 0, static_cast<GLsizeiptr>(mesh.indices.size() * sizeof(uint32_t)), mesh.indices.data());
    }
    indexCount_ = static_cast<GLsizei>(mesh.indices.size());
    const bool ok = glGetError() == GL_NO_ERROR;
    glBindVertexArray(0);
    return ok;
}

void Mesh::draw(GLenum primitive) const {
    if (!vao_ || indexCount_ <= 0) return;
    glBindVertexArray(vao_);
    glDrawElements(primitive, indexCount_, indexType_, nullptr);
}

void Mesh::drawInstanced(GLsizei instanceCount, GLenum primitive) const {
    if (!vao_ || indexCount_ <= 0 || instanceCount <= 0) return;
    glBindVertexArray(vao_);
    glDrawElementsInstanced(primitive, indexCount_, indexType_, nullptr, instanceCount);
}

void Mesh::bind() const { glBindVertexArray(vao_); }
void Mesh::destroy() {
    if (indexBuffer_) glDeleteBuffers(1, &indexBuffer_);
    if (vertexBuffer_) glDeleteBuffers(1, &vertexBuffer_);
    if (vao_) glDeleteVertexArrays(1, &vao_);
    vao_ = vertexBuffer_ = indexBuffer_ = 0;
    indexCount_ = 0;
    indexType_ = GL_UNSIGNED_INT;
    vertexCapacityBytes_ = indexCapacityBytes_ = 0;
}

InstancedBuffer::~InstancedBuffer() { destroy(); }
InstancedBuffer::InstancedBuffer(InstancedBuffer&& other) noexcept
    : buffer_(std::exchange(other.buffer_, 0)), capacity_(std::exchange(other.capacity_, 0)),
      count_(std::exchange(other.count_, 0)) {}
InstancedBuffer& InstancedBuffer::operator=(InstancedBuffer&& other) noexcept {
    if (this != &other) {
        destroy();
        buffer_ = std::exchange(other.buffer_, 0);
        capacity_ = std::exchange(other.capacity_, 0);
        count_ = std::exchange(other.count_, 0);
    }
    return *this;
}

bool InstancedBuffer::create(const Mesh& mesh, size_t capacity) {
    destroy();
    capacity_ = capacity;
    glGenBuffers(1, &buffer_);
    if (!buffer_) return false;
    bind(mesh);
    glBufferData(GL_ARRAY_BUFFER, static_cast<GLsizeiptr>(capacity_ * sizeof(GpuInstance)), nullptr, GL_DYNAMIC_DRAW);
    glBindVertexArray(0);
    if (glGetError() != GL_NO_ERROR) {
        destroy();
        return false;
    }
    return true;
}

bool InstancedBuffer::update(const std::vector<InstanceData>& instances) {
    if (!buffer_ || instances.size() > capacity_) return false;
    std::vector<GpuInstance> gpu(instances.size());
    for (size_t i = 0; i < instances.size(); ++i) {
        std::memcpy(gpu[i].matrix, instances[i].transform.data(), sizeof(gpu[i].matrix));
        const Vec3 color = sanitizeColor(instances[i].color, 48.0f);
        gpu[i].color[0] = color.x;
        gpu[i].color[1] = color.y;
        gpu[i].color[2] = color.z;
        gpu[i].color[3] = std::isfinite(instances[i].parameter) ? instances[i].parameter : 0.0f;
    }
    glBindBuffer(GL_ARRAY_BUFFER, buffer_);
    if (!gpu.empty()) {
        glBufferSubData(GL_ARRAY_BUFFER, 0, static_cast<GLsizeiptr>(gpu.size() * sizeof(GpuInstance)), gpu.data());
    }
    count_ = static_cast<GLsizei>(gpu.size());
    return glGetError() == GL_NO_ERROR;
}

void InstancedBuffer::bind(const Mesh& mesh) const {
    mesh.bind();
    glBindBuffer(GL_ARRAY_BUFFER, buffer_);
    constexpr GLsizei stride = sizeof(GpuInstance);
    for (GLuint column = 0; column < 4; ++column) {
        const GLuint location = 4 + column;
        glEnableVertexAttribArray(location);
        glVertexAttribPointer(location, 4, GL_FLOAT, GL_FALSE, stride,
                              reinterpret_cast<const void*>(static_cast<uintptr_t>(column * sizeof(float) * 4)));
        glVertexAttribDivisor(location, 1);
    }
    glEnableVertexAttribArray(8);
    glVertexAttribPointer(8, 4, GL_FLOAT, GL_FALSE, stride,
                          reinterpret_cast<const void*>(static_cast<uintptr_t>(sizeof(float) * 16)));
    glVertexAttribDivisor(8, 1);
}

void InstancedBuffer::destroy() {
    if (buffer_) glDeleteBuffers(1, &buffer_);
    buffer_ = 0;
    capacity_ = 0;
    count_ = 0;
}

Texture2D::~Texture2D() { destroy(); }
Texture2D::Texture2D(Texture2D&& other) noexcept
    : id_(std::exchange(other.id_, 0)), width_(std::exchange(other.width_, 0)), height_(std::exchange(other.height_, 0)) {}
Texture2D& Texture2D::operator=(Texture2D&& other) noexcept {
    if (this != &other) {
        destroy();
        id_ = std::exchange(other.id_, 0);
        width_ = std::exchange(other.width_, 0);
        height_ = std::exchange(other.height_, 0);
    }
    return *this;
}

bool Texture2D::create(int width, int height, GLenum internalFormat, GLenum format, GLenum type,
                       const void* pixels, bool linear, bool repeat) {
    destroy();
    width_ = width;
    height_ = height;
    glGenTextures(1, &id_);
    if (!id_) return false;
    glBindTexture(GL_TEXTURE_2D, id_);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, linear ? GL_LINEAR : GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, linear ? GL_LINEAR : GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, repeat ? GL_REPEAT : GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, repeat ? GL_REPEAT : GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, static_cast<GLint>(internalFormat), width, height, 0, format, type, pixels);
    if (glGetError() != GL_NO_ERROR) {
        destroy();
        return false;
    }
    return true;
}

void Texture2D::bind(GLuint unit) const {
    glActiveTexture(GL_TEXTURE0 + unit);
    glBindTexture(GL_TEXTURE_2D, id_);
}

void Texture2D::destroy() {
    if (id_) glDeleteTextures(1, &id_);
    id_ = 0;
    width_ = height_ = 0;
}

Framebuffer::~Framebuffer() { destroy(); }
Framebuffer::Framebuffer(Framebuffer&& other) noexcept
    : id_(std::exchange(other.id_, 0)), depth_(std::exchange(other.depth_, 0)), color_(std::move(other.color_)),
      width_(std::exchange(other.width_, 0)), height_(std::exchange(other.height_, 0)) {}
Framebuffer& Framebuffer::operator=(Framebuffer&& other) noexcept {
    if (this != &other) {
        destroy();
        id_ = std::exchange(other.id_, 0);
        depth_ = std::exchange(other.depth_, 0);
        color_ = std::move(other.color_);
        width_ = std::exchange(other.width_, 0);
        height_ = std::exchange(other.height_, 0);
    }
    return *this;
}

bool Framebuffer::create(int width, int height, GLenum colorInternalFormat, GLenum colorFormat, GLenum colorType,
                         bool withDepth) {
    destroy();
    width_ = width;
    height_ = height;
    if (!color_.create(width, height, colorInternalFormat, colorFormat, colorType, nullptr, true, false)) return false;
    glGenFramebuffers(1, &id_);
    if (!id_) {
        destroy();
        return false;
    }
    glBindFramebuffer(GL_FRAMEBUFFER, id_);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, color_.id(), 0);
    if (withDepth) {
        glGenRenderbuffers(1, &depth_);
        if (!depth_) {
            destroy();
            return false;
        }
        glBindRenderbuffer(GL_RENDERBUFFER, depth_);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depth_);
    }
    const GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (status != GL_FRAMEBUFFER_COMPLETE || glGetError() != GL_NO_ERROR) {
        destroy();
        return false;
    }
    return true;
}

void Framebuffer::bind() const { glBindFramebuffer(GL_FRAMEBUFFER, id_); }
void Framebuffer::bindDefault() { glBindFramebuffer(GL_FRAMEBUFFER, 0); }
void Framebuffer::destroy() {
    if (depth_) glDeleteRenderbuffers(1, &depth_);
    if (id_) glDeleteFramebuffers(1, &id_);
    depth_ = 0;
    id_ = 0;
    color_.destroy();
    width_ = height_ = 0;
}

std::vector<uint8_t> makeNoiseTextureRgba(int width, int height, uint32_t seed) {
    std::vector<uint8_t> pixels(static_cast<size_t>(width) * height * 4);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const uint32_t h = hashUint(static_cast<uint32_t>(x) * 73856093U ^ static_cast<uint32_t>(y) * 19349663U ^ seed);
            const uint8_t value = static_cast<uint8_t>(h & 0xffU);
            const size_t index = (static_cast<size_t>(y) * width + x) * 4;
            pixels[index] = value;
            pixels[index + 1] = static_cast<uint8_t>((h >> 8U) & 0xffU);
            pixels[index + 2] = static_cast<uint8_t>((h >> 16U) & 0xffU);
            pixels[index + 3] = 255;
        }
    }
    return pixels;
}

std::vector<uint8_t> makeRoadTextureRgba(int width, int height, uint32_t seed) {
    std::vector<uint8_t> pixels(static_cast<size_t>(width) * height * 4);
    for (int y = 0; y < height; ++y) {
        const float v = static_cast<float>(y) / std::max(height - 1, 1);
        for (int x = 0; x < width; ++x) {
            const uint32_t h = hashUint(static_cast<uint32_t>(x) * 2654435761U ^ static_cast<uint32_t>(y) * 2246822519U ^ seed);
            const int grain = static_cast<int>(h & 31U) - 15;
            int r = 68 + grain;
            int g = 70 + grain;
            int b = 75 + grain;
            const bool edgeLine = (v > 0.025f && v < 0.055f) || (v > 0.945f && v < 0.975f);
            const bool centerDash = v > 0.48f && v < 0.52f && (x % std::max(width / 4, 1)) < width / 8;
            if (edgeLine) r = g = b = 232;
            if (centerDash) {
                r = 242;
                g = 201;
                b = 76;
            }
            const size_t index = (static_cast<size_t>(y) * width + x) * 4;
            pixels[index] = static_cast<uint8_t>(std::clamp(r, 0, 255));
            pixels[index + 1] = static_cast<uint8_t>(std::clamp(g, 0, 255));
            pixels[index + 2] = static_cast<uint8_t>(std::clamp(b, 0, 255));
            pixels[index + 3] = 255;
        }
    }
    return pixels;
}

}  // namespace pelican::scene
