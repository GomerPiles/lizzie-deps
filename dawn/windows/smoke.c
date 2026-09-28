#include <dawn/webgpu.h>

int main(void) {
    WGPUInstance instance = wgpuCreateInstance(NULL);
    if (instance == NULL) return 1;
    wgpuInstanceRelease(instance);
    return 0;
}
