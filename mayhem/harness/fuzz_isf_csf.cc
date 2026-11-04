// libisf: a compute shader (CSF) as Score's CSF process loads it.
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
        std::string{reinterpret_cast<const char*>(data), size},
        isf::parser::ShaderType::CSF};
    (void)p.mode();
    (void)p.data();
    (void)p.compute_shader();
  }
  catch(const std::exception&)
  {
    return -1;
  }
  return 0;
}
