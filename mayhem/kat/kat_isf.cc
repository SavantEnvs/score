// Known-answer probe over libisf. Dynamically linked and unsanitized on purpose: test.sh compares its
// stdout in bash, so neutering the binary cannot make the oracle pass.
#include <isf.hpp>

#include <cstdio>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>

static std::string slurp(const char* path)
{
  std::ifstream f(path, std::ios::binary);
  std::stringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

int main(int argc, char** argv)
{
  if(argc != 3)
    return 2;
  const std::string mode = argv[1];
  const std::string src = slurp(argv[2]);
  if(src.empty())
    return 3;
  try
  {
    if(mode == "frag")
    {
      isf::parser p{
          std::string{}, src, 450, isf::parser::ShaderType::Autodetect};
      const auto d = p.data();
      std::printf("description=%s\n", d.description.c_str());
      std::printf("credits=%s\n", d.credits.c_str());
      std::printf("categories=%zu:", d.categories.size());
      for(auto& c : d.categories)
        std::printf(" [%s]", c.c_str());
      std::printf("\ninputs=%zu\n", d.inputs.size());
      for(auto& in : d.inputs)
      {
        if(auto f = ossia::get_if<isf::float_input>(&in.data))
          std::printf(
              "float %s \"%s\" min=%g max=%g def=%g\n", in.name.c_str(),
              in.label.c_str(), f->min, f->max, f->def);
        else if(ossia::get_if<isf::image_input>(&in.data))
          std::printf("image %s\n", in.name.c_str());
        else
          std::printf("other %s\n", in.name.c_str());
      }
      std::printf("has_main=%d\n", (int)(p.fragment().find("void main") != std::string::npos));
    }
    else if(mode == "csf")
    {
      isf::parser p{src, isf::parser::ShaderType::CSF};
      const auto d = p.data();
      std::printf("mode=%d\n", (int)p.mode());
      std::printf("description_len=%zu\n", d.description.size());
      std::printf("passes=%zu\n", d.csf_passes.size());
      if(!d.csf_passes.empty())
      {
        auto& ls = d.csf_passes[0].local_size;
        std::printf("local_size=%d,%d,%d\n", ls[0], ls[1], ls[2]);
      }
      std::printf("has_main=%d\n", (int)(p.compute_shader().find("void main") != std::string::npos));
    }
    else
      return 2;
  }
  catch(const std::exception& e)
  {
    std::printf("EXCEPTION %s\n", e.what());
    return 1;
  }
  return 0;
}
