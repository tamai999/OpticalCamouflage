#include <metal_stdlib>
using namespace metal;

#include <CoreImage/CoreImage.h>

inline void swap(thread float4 &a, thread float4 &b) {
    float4 tmp = a; a = min(a,b); b = max(tmp, b);
}

extern "C" {
    namespace coreimage {
        float4 median(sample_t v0,sample_t v1,sample_t v2,sample_t v3,sample_t v4, destination dest)
        {
            swap(v0, v1);
            swap(v1, v2);
            swap(v2, v3);
            swap(v3, v4);
            
            swap(v0, v1);
            swap(v1, v2);
            swap(v2, v3);
            
            swap(v0, v1);
            swap(v1, v2);
            
            return v2;
        }
        
        float4 composite(sample_t v0, sample_t v1, destination dest)
        {
            if (v0.x == 0.0 && v0.y == 0.0 && v0.z == 0) {
                return v1;
            }
            return v0;
        }
    }
}
