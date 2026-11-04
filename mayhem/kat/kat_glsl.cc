// Known-answer probe over 3rdparty/glsl-parser: the function names a shader defines, as libisf's
// extract_glsl_function_definitions walks them. Dynamically linked and unsanitized on purpose.
extern "C" {
#include <glsl-parser/glsl_ast.h>
#include <glsl-parser/glsl_parser.h>
}
#include <glsl-parser/glsl_tokens.hpp>

#include <cstdio>

static void quiet(const char*, int, int, int) { }

int main()
{
  const char* src
      = "const float pi = 3.14159265359;\n"
        "float sq(float x) { return x * x; }\n"
        "vec2 rot(vec2 v, float a) { return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a)); }\n"
        "void main() { float r = sq(2.0); }\n";
  glsl_parse_context ctx;
  glsl_parse_context_init(&ctx);
  glsl_parse_set_error_cb(&ctx, quiet);
  const bool error = glsl_parse_string(&ctx, src);
  std::printf("error=%d\n", (int)error);
  if(error || !ctx.root || ctx.root->code != (int)glsl_tokentype::TRANSLATION_UNIT)
    return 1;
  int fdefs = 0;
  for(int i = 0; i < ctx.root->child_count; i++)
  {
    auto def = ctx.root->children[i];
    if(def->code != (int)glsl_tokentype::FUNCTION_DEFINITION)
      continue;
    fdefs++;
    for(int j = 0; j < def->child_count; j++)
    {
      auto decl = def->children[j];
      if(decl->code != (int)glsl_tokentype::FUNCTION_DECLARATION)
        continue;
      for(int k = 0; k < decl->child_count; k++)
      {
        auto head = decl->children[k];
        if(head->code != (int)glsl_tokentype::FUNCTION_HEADER)
          continue;
        for(int l = 0; l < head->child_count; l++)
          if(head->children[l]->code == (int)glsl_tokentype::IDENTIFIER)
          {
            std::printf("fn %s\n", head->children[l]->data.str);
            break;
          }
      }
    }
  }
  std::printf("function_definitions=%d\n", fdefs);

  glsl_parse_context bad;
  glsl_parse_context_init(&bad);
  glsl_parse_set_error_cb(&bad, quiet);
  const bool bad_error = glsl_parse_string(&bad, "void main( { float = ; }");
  std::printf("syntax_error_detected=%d\n", (int)bad_error);
  glsl_parse_context_destroy(&bad);
  glsl_parse_context_destroy(&ctx);
  return 0;
}
