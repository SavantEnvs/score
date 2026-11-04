// libisf: a Vertex Shader Art (.vs) program as Score's ShaderProgram loads it.
#include <isf.hpp>

#include <cstddef>
#include <cstdint>
#include <exception>
#include <string>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
  if(size > (1u << 20))
    return -1;
  try
  {
    isf::parser p{
        std::string{reinterpret_cast<const char*>(data), size}, std::string{}, 450,
        isf::parser::ShaderType::VertexShaderArt};
    (void)p.data();
    (void)p.vertex();
    (void)p.fragment();
  }
  catch(const std::exception&)
  {
    return -1;
  }
  return 0;
}
