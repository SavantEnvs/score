// 3rdparty/dxv: Resolume DXV texture decompression, as Score's DXV decoder calls it per frame.
// Input: [format][width/4][height/4] then the compressed payload.
#include <dxv.h>

#include <cstddef>
#include <cstdint>
#include <vector>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
  if(size < 4 || size > (1u << 20))
    return -1;
  const unsigned fmt = data[0] % 5;
  const int bw = 2 + (data[1] % 31); // 4x4 blocks across: 8..128 px, as the decoder's coded_w/4
  const int bh = 2 + (data[2] % 31);
  const uint8_t* src = data + 3;
  const int srcSize = static_cast<int>(size - 3);
  const int w = bw * 4, h = bh * 4;

  switch(fmt)
  {
    case 0:
    {
      std::vector<uint8_t> out(static_cast<size_t>(bw) * bh * 8);
      (void)dxv_decompress_dxt1(src, srcSize, out.data(), static_cast<int>(out.size()));
      break;
    }
    case 1:
    {
      std::vector<uint8_t> out(static_cast<size_t>(bw) * bh * 16);
      (void)dxv_decompress_dxt5(src, srcSize, out.data(), static_cast<int>(out.size()));
      break;
    }
    case 2:
    {
      std::vector<uint8_t> out(static_cast<size_t>(bw) * bh * 16);
      (void)dxv_decompress_lzf(src, srcSize, out.data(), static_cast<int>(out.size()));
      break;
    }
    default:
    {
      // Sizes exactly as Gfx/Graph/decoders/DXV.cpp computes them.
      const bool yg10 = (fmt == 4);
      const size_t ysz = static_cast<size_t>(bw) * bh * (yg10 ? 16 : 8);
      const size_t csz = static_cast<size_t>(w / 2 / 4) * (h / 2 / 4) * 16;
      std::vector<uint8_t> tex(ysz), ctex(csz);
      DXVDecompressContext ctx;
      dxv_ctx_init(&ctx);
      if(yg10)
        (void)dxv_decompress_yg10(
            &ctx, src, srcSize, tex.data(), static_cast<int>(tex.size()), ctex.data(),
            static_cast<int>(ctex.size()), w, h);
      else
        (void)dxv_decompress_ycg6(
            &ctx, src, srcSize, tex.data(), static_cast<int>(tex.size()), ctex.data(),
            static_cast<int>(ctex.size()), w, h);
      dxv_ctx_free(&ctx);
      break;
    }
  }
  return 0;
}
