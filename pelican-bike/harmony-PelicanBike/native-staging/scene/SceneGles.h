#pragma once

#if defined(PELICAN_SCENE_MOCK_GLES)
#include "host/MockGles3.h"
#elif __has_include(<GLES3/gl3.h>)
#include <GLES3/gl3.h>
#else
#error "GLES3/gl3.h was not found. Define PELICAN_SCENE_MOCK_GLES for host compile tests."
#endif
