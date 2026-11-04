/* Known-answer probe over 3rdparty/dxv's LZF decoder. Dynamically linked and unsanitized on purpose. */
#include <dxv.h>

#include <stdio.h>
#include <string.h>

int main(void)
{
  /* literal run "hello", then literal "ab" + back-reference (len 4, offset 2) -> "ababab" */
  const uint8_t lit[] = {0x04, 'h', 'e', 'l', 'l', 'o'};
  const uint8_t ref[] = {0x01, 'a', 'b', 0x40, 0x01, 0x00};
  uint8_t out[32];

  memset(out, 0, sizeof out);
  int n = dxv_decompress_lzf(lit, (int)sizeof lit, out, (int)sizeof out);
  printf("lzf_literal n=%d out=%.*s\n", n, n > 0 ? n : 0, out);

  memset(out, 0, sizeof out);
  n = dxv_decompress_lzf(ref, (int)sizeof ref, out, (int)sizeof out);
  printf("lzf_backref n=%d out=%.*s\n", n, n > 0 ? n : 0, out);

  /* output too small -> reported as an error, not an overrun */
  n = dxv_decompress_lzf(lit, (int)sizeof lit, out, 3);
  printf("lzf_overflow n=%d\n", n);
  return 0;
}
