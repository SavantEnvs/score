// 3rdparty/glsl-parser (bison/flex GLSL grammar) driven as libisf's function-definition scan does.
extern "C" {
#include <glsl-parser/glsl_parser.h>
}

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>

static void quiet_error_cb(const char*, int, int, int) { }

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
  if(size > (1u << 20))
    return -1;
  char* str = static_cast<char*>(std::malloc(size + 1));
  if(!str)
    return -1;
  std::memcpy(str, data, size);
  str[size] = 0;

  glsl_parse_context context;
  glsl_parse_context_init(&context);
  glsl_parse_set_error_cb(&context, quiet_error_cb);
  const bool error = glsl_parse_string(&context, str);
  int ret = error ? -1 : 0;
  glsl_parse_context_destroy(&context);
  std::free(str);
  return ret;
}
