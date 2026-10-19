#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// WinUI desktop pickers require their owning Window's native handle. This
// module only connects COM interfaces; all controls are WinUI/Swift-WinRT.
int32_t cappella_attach_picker(void *picker, uint64_t window_id, int32_t *stage);
#ifdef __cplusplus
}
#endif
