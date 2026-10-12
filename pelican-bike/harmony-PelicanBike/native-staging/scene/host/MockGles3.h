#pragma once

#include <algorithm>
#include <cstddef>
#include <cstdint>

using GLvoid = void;
using GLchar = char;
using GLboolean = uint8_t;
using GLbyte = int8_t;
using GLubyte = uint8_t;
using GLshort = int16_t;
using GLushort = uint16_t;
using GLint = int32_t;
using GLuint = uint32_t;
using GLsizei = int32_t;
using GLenum = uint32_t;
using GLbitfield = uint32_t;
using GLfloat = float;
using GLclampf = float;
using GLintptr = std::ptrdiff_t;
using GLsizeiptr = std::ptrdiff_t;

constexpr GLboolean GL_FALSE = 0;
constexpr GLboolean GL_TRUE = 1;
constexpr GLenum GL_NO_ERROR = 0;
constexpr GLenum GL_VERTEX_SHADER = 0x8B31;
constexpr GLenum GL_FRAGMENT_SHADER = 0x8B30;
constexpr GLenum GL_COMPILE_STATUS = 0x8B81;
constexpr GLenum GL_LINK_STATUS = 0x8B82;
constexpr GLenum GL_INFO_LOG_LENGTH = 0x8B84;
constexpr GLenum GL_ARRAY_BUFFER = 0x8892;
constexpr GLenum GL_ELEMENT_ARRAY_BUFFER = 0x8893;
constexpr GLenum GL_STATIC_DRAW = 0x88E4;
constexpr GLenum GL_DYNAMIC_DRAW = 0x88E8;
constexpr GLenum GL_FLOAT = 0x1406;
constexpr GLenum GL_UNSIGNED_BYTE = 0x1401;
constexpr GLenum GL_UNSIGNED_INT = 0x1405;
constexpr GLenum GL_HALF_FLOAT = 0x140B;
constexpr GLenum GL_TRIANGLES = 0x0004;
constexpr GLenum GL_LINES = 0x0001;
constexpr GLenum GL_POINTS = 0x0000;
constexpr GLenum GL_TEXTURE_2D = 0x0DE1;
constexpr GLenum GL_TEXTURE0 = 0x84C0;
constexpr GLenum GL_TEXTURE_MIN_FILTER = 0x2801;
constexpr GLenum GL_TEXTURE_MAG_FILTER = 0x2800;
constexpr GLenum GL_TEXTURE_WRAP_S = 0x2802;
constexpr GLenum GL_TEXTURE_WRAP_T = 0x2803;
constexpr GLenum GL_LINEAR = 0x2601;
constexpr GLenum GL_NEAREST = 0x2600;
constexpr GLenum GL_REPEAT = 0x2901;
constexpr GLenum GL_CLAMP_TO_EDGE = 0x812F;
constexpr GLenum GL_RGBA = 0x1908;
constexpr GLenum GL_RGBA8 = 0x8058;
constexpr GLenum GL_RGBA16F = 0x881A;
constexpr GLenum GL_FRAMEBUFFER = 0x8D40;
constexpr GLenum GL_RENDERBUFFER = 0x8D41;
constexpr GLenum GL_COLOR_ATTACHMENT0 = 0x8CE0;
constexpr GLenum GL_DEPTH_ATTACHMENT = 0x8D00;
constexpr GLenum GL_DEPTH_COMPONENT24 = 0x81A6;
constexpr GLenum GL_FRAMEBUFFER_COMPLETE = 0x8CD5;
constexpr GLenum GL_DEPTH_TEST = 0x0B71;
constexpr GLenum GL_CULL_FACE = 0x0B44;
constexpr GLenum GL_BACK = 0x0405;
constexpr GLenum GL_CCW = 0x0901;
constexpr GLenum GL_LEQUAL = 0x0203;
constexpr GLenum GL_BLEND = 0x0BE2;
constexpr GLenum GL_SRC_ALPHA = 0x0302;
constexpr GLenum GL_ONE_MINUS_SRC_ALPHA = 0x0303;
constexpr GLenum GL_ONE = 1;
constexpr GLenum GL_COLOR_BUFFER_BIT = 0x00004000;
constexpr GLenum GL_DEPTH_BUFFER_BIT = 0x00000100;
constexpr GLenum GL_PACK_ALIGNMENT = 0x0D05;
constexpr GLenum GL_NUM_EXTENSIONS = 0x821D;
constexpr GLenum GL_EXTENSIONS = 0x1F03;

namespace pelican::scene::mockgl {
inline GLuint nextId = 1;
inline GLenum error = GL_NO_ERROR;
inline uint64_t liveBuffers = 0;
inline uint64_t liveVertexArrays = 0;
inline uint64_t liveTextures = 0;
inline uint64_t liveFramebuffers = 0;
inline uint64_t liveRenderbuffers = 0;
inline uint64_t livePrograms = 0;
inline GLuint allocate() { return nextId++; }
}  // namespace pelican::scene::mockgl

inline GLuint glCreateShader(GLenum) { return pelican::scene::mockgl::allocate(); }
inline void glShaderSource(GLuint, GLsizei, const GLchar* const*, const GLint*) {}
inline void glCompileShader(GLuint) {}
inline void glGetShaderiv(GLuint, GLenum pname, GLint* value) {
    *value = pname == GL_INFO_LOG_LENGTH ? 1 : GL_TRUE;
}
inline void glGetShaderInfoLog(GLuint, GLsizei, GLsizei* written, GLchar* log) {
    if (written) *written = 0;
    if (log) *log = '\0';
}
inline void glDeleteShader(GLuint) {}
inline GLuint glCreateProgram() { ++pelican::scene::mockgl::livePrograms; return pelican::scene::mockgl::allocate(); }
inline void glAttachShader(GLuint, GLuint) {}
inline void glLinkProgram(GLuint) {}
inline void glGetProgramiv(GLuint, GLenum pname, GLint* value) {
    *value = pname == GL_INFO_LOG_LENGTH ? 1 : GL_TRUE;
}
inline void glGetProgramInfoLog(GLuint, GLsizei, GLsizei* written, GLchar* log) {
    if (written) *written = 0;
    if (log) *log = '\0';
}
inline void glDeleteProgram(GLuint id) { if (id && pelican::scene::mockgl::livePrograms) --pelican::scene::mockgl::livePrograms; }
inline void glUseProgram(GLuint) {}
inline GLint glGetUniformLocation(GLuint, const GLchar*) { return 0; }
inline void glUniform1f(GLint, GLfloat) {}
inline void glUniform1i(GLint, GLint) {}
inline void glUniform1fv(GLint, GLsizei, const GLfloat*) {}
inline void glUniform2f(GLint, GLfloat, GLfloat) {}
inline void glUniform3f(GLint, GLfloat, GLfloat, GLfloat) {}
inline void glUniformMatrix4fv(GLint, GLsizei, GLboolean, const GLfloat*) {}
inline void glGenBuffers(GLsizei count, GLuint* ids) { pelican::scene::mockgl::liveBuffers += static_cast<uint64_t>(count); while (count--) *ids++ = pelican::scene::mockgl::allocate(); }
inline void glDeleteBuffers(GLsizei count, const GLuint*) { pelican::scene::mockgl::liveBuffers -= std::min<uint64_t>(pelican::scene::mockgl::liveBuffers, static_cast<uint64_t>(count)); }
inline void glBindBuffer(GLenum, GLuint) {}
inline void glBufferData(GLenum, GLsizeiptr, const void*, GLenum) {}
inline void glBufferSubData(GLenum, GLintptr, GLsizeiptr, const void*) {}
inline void glGenVertexArrays(GLsizei count, GLuint* ids) { pelican::scene::mockgl::liveVertexArrays += static_cast<uint64_t>(count); while (count--) *ids++ = pelican::scene::mockgl::allocate(); }
inline void glDeleteVertexArrays(GLsizei count, const GLuint*) { pelican::scene::mockgl::liveVertexArrays -= std::min<uint64_t>(pelican::scene::mockgl::liveVertexArrays, static_cast<uint64_t>(count)); }
inline void glBindVertexArray(GLuint) {}
inline void glEnableVertexAttribArray(GLuint) {}
inline void glVertexAttribPointer(GLuint, GLint, GLenum, GLboolean, GLsizei, const void*) {}
inline void glVertexAttribDivisor(GLuint, GLuint) {}
inline void glDrawElements(GLenum, GLsizei, GLenum, const void*) {}
inline void glDrawElementsInstanced(GLenum, GLsizei, GLenum, const void*, GLsizei) {}
inline void glDrawArrays(GLenum, GLint, GLsizei) {}
inline void glGenTextures(GLsizei count, GLuint* ids) { pelican::scene::mockgl::liveTextures += static_cast<uint64_t>(count); while (count--) *ids++ = pelican::scene::mockgl::allocate(); }
inline void glDeleteTextures(GLsizei count, const GLuint*) { pelican::scene::mockgl::liveTextures -= std::min<uint64_t>(pelican::scene::mockgl::liveTextures, static_cast<uint64_t>(count)); }
inline void glActiveTexture(GLenum) {}
inline void glBindTexture(GLenum, GLuint) {}
inline void glTexParameteri(GLenum, GLenum, GLint) {}
inline void glTexImage2D(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void*) {}
inline void glGenFramebuffers(GLsizei count, GLuint* ids) { pelican::scene::mockgl::liveFramebuffers += static_cast<uint64_t>(count); while (count--) *ids++ = pelican::scene::mockgl::allocate(); }
inline void glDeleteFramebuffers(GLsizei count, const GLuint*) { pelican::scene::mockgl::liveFramebuffers -= std::min<uint64_t>(pelican::scene::mockgl::liveFramebuffers, static_cast<uint64_t>(count)); }
inline void glBindFramebuffer(GLenum, GLuint) {}
inline void glFramebufferTexture2D(GLenum, GLenum, GLenum, GLuint, GLint) {}
inline GLenum glCheckFramebufferStatus(GLenum) { return GL_FRAMEBUFFER_COMPLETE; }
inline void glGenRenderbuffers(GLsizei count, GLuint* ids) { pelican::scene::mockgl::liveRenderbuffers += static_cast<uint64_t>(count); while (count--) *ids++ = pelican::scene::mockgl::allocate(); }
inline void glDeleteRenderbuffers(GLsizei count, const GLuint*) { pelican::scene::mockgl::liveRenderbuffers -= std::min<uint64_t>(pelican::scene::mockgl::liveRenderbuffers, static_cast<uint64_t>(count)); }
inline void glBindRenderbuffer(GLenum, GLuint) {}
inline void glRenderbufferStorage(GLenum, GLenum, GLsizei, GLsizei) {}
inline void glFramebufferRenderbuffer(GLenum, GLenum, GLenum, GLuint) {}
inline GLenum glGetError() {
    const GLenum result = pelican::scene::mockgl::error;
    pelican::scene::mockgl::error = GL_NO_ERROR;
    return result;
}
inline void glEnable(GLenum) {}
inline void glDisable(GLenum) {}
inline void glDepthFunc(GLenum) {}
inline void glCullFace(GLenum) {}
inline void glFrontFace(GLenum) {}
inline void glDepthMask(GLboolean) {}
inline void glBlendFunc(GLenum, GLenum) {}
inline void glViewport(GLint, GLint, GLsizei, GLsizei) {}
inline void glClearColor(GLfloat, GLfloat, GLfloat, GLfloat) {}
inline void glClear(GLbitfield) {}
inline void glGetIntegerv(GLenum pname, GLint* value) { *value = pname == GL_NUM_EXTENSIONS ? 0 : 0; }
inline const GLubyte* glGetStringi(GLenum, GLuint) { return nullptr; }
inline void glPixelStorei(GLenum, GLint) {}
inline void glFinish() {}
inline void glReadPixels(GLint, GLint, GLsizei width, GLsizei height, GLenum, GLenum, void* data) {
    auto* pixels = static_cast<uint8_t*>(data);
    for (GLsizei i = 0; i < width * height * 4; ++i) pixels[i] = 0;
}
