#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// WinUI desktop pickers require their owning Window's native handle. This
// controls remain WinUI/Swift-WinRT; audio decoding uses Media Foundation.
int32_t cappella_attach_picker(void *picker, uint64_t window_id, int32_t *stage);
// Decode an audio stream and reverse PCM sample frames into VO/VI WAV files.
// Returns S_FALSE when the requested audio stream does not exist.
int32_t cappella_reverse_audio(const uint16_t *source, const uint16_t *vo, const uint16_t *vi,
    int32_t ordinal, int32_t *streams, int32_t *paired, double *duration, int32_t (*cancelled)(void));
#ifdef __cplusplus
}
#endif
