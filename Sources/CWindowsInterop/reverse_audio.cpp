#define NOMINMAX
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <wrl/client.h>
#include <stdio.h>
#include <string.h>
#include "include/desktop.h"

using Microsoft::WRL::ComPtr;

// Keep this bridge independent of the MSVC STL: newer runner toolsets can
// require a newer Clang than the one bundled with the Swift toolchain.
class PCMBuffer {
    unsigned char *bytes;
public:
    explicit PCMBuffer(size_t size, bool zero = false)
        : bytes(static_cast<unsigned char *>(HeapAlloc(GetProcessHeap(), zero ? HEAP_ZERO_MEMORY : 0, size))) {}
    ~PCMBuffer() { if (bytes) HeapFree(GetProcessHeap(), 0, bytes); }
    PCMBuffer(const PCMBuffer &) = delete;
    PCMBuffer &operator=(const PCMBuffer &) = delete;
    unsigned char *data() const { return bytes; }
};

// PCM is decoded incrementally. Only a one-second buffer is reversed at once;
// channel order within each sample frame is preserved.
static HRESULT reverse_stream(IMFSourceReader *reader, DWORD stream, const wchar_t *vo,
                              const wchar_t *vi, double *duration, int32_t *paired,
                              int32_t (*cancelled)(void)) {
    ComPtr<IMFMediaType> native, pcm, actual;
    HRESULT hr = reader->GetNativeMediaType(stream, 0, &native);
    if (FAILED(hr)) return hr;
    UINT32 channels = 2, sampleRate = 48000;
    native->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &channels);
    native->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &sampleRate);
    if (!channels || channels > 32 || sampleRate < 8000 || sampleRate > 384000) return E_INVALIDARG;
    if (FAILED(hr = MFCreateMediaType(&pcm))) return hr;
    pcm->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    pcm->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    pcm->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, channels);
    pcm->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, sampleRate);
    pcm->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    pcm->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, channels * 2);
    pcm->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, sampleRate * channels * 2);
    pcm->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE);
    if (FAILED(hr = reader->SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS, FALSE)) ||
        FAILED(hr = reader->SetStreamSelection(stream, TRUE)) ||
        FAILED(hr = reader->SetCurrentMediaType(stream, nullptr, pcm.Get())) ||
        FAILED(hr = reader->GetCurrentMediaType(stream, &actual))) return hr;
    UINT32 actualRate = 0, bits = 0, alignment = 0, actualChannels = 0;
    actual->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &actualRate);
    actual->GetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, &bits);
    actual->GetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, &alignment);
    actual->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &actualChannels);
    if (actualRate != sampleRate || bits != 16 || actualChannels != channels || alignment != channels * 2)
        return MF_E_INVALIDMEDIATYPE;

    PCMBuffer zeros((size_t)sampleRate * alignment, true);
    if (!zeros.data()) return E_OUTOFMEMORY;
    FILE *decoded = nullptr, *outputs[2] = { nullptr, nullptr };
    wchar_t tempDirectory[MAX_PATH], tempFile[MAX_PATH];
    if (!GetTempPathW(MAX_PATH, tempDirectory) || !GetTempFileNameW(tempDirectory, L"cap", 0, tempFile))
        return HRESULT_FROM_WIN32(GetLastError());
    _wfopen_s(&decoded, tempFile, L"w+b");
    if (!decoded) { DeleteFileW(tempFile); return E_FAIL; }
    const UINT32 outputChannels = channels == 4 ? 2 : channels;
    const UINT32 outputCount = channels == 4 ? 2 : 1;
    const uint64_t maxFrames = (UINT32_MAX - 36ULL) / (outputChannels * 2);
    uint64_t frames = 0;
    auto writeSilence = [&](uint64_t target) -> HRESULT {
        if (target > maxFrames) return HRESULT_FROM_WIN32(ERROR_FILE_TOO_LARGE);
        while (frames < target) {
            if (cancelled && cancelled()) return HRESULT_FROM_WIN32(ERROR_CANCELLED);
            size_t count = (size_t)((target - frames) < sampleRate ? (target - frames) : sampleRate);
            if (fwrite(zeros.data(), alignment, count, decoded) != count) return E_FAIL;
            frames += count;
        }
        return S_OK;
    };

    do {
        for (;;) {
            if (cancelled && cancelled()) { hr = HRESULT_FROM_WIN32(ERROR_CANCELLED); break; }
            DWORD flags = 0;
            LONGLONG stamp = 0;
            ComPtr<IMFSample> sample;
            hr = reader->ReadSample(stream, 0, nullptr, &flags, &stamp, &sample);
            if (FAILED(hr)) break;
            if (flags & MF_SOURCE_READERF_ERROR) { hr = E_FAIL; break; }
            if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) {
                ComPtr<IMFMediaType> changed;
                UINT32 changedRate = 0, changedBlock = 0, changedBits = 0, changedChannels = 0;
                GUID subtype = {};
                hr = reader->GetCurrentMediaType(stream, &changed);
                if (FAILED(hr)) break;
                changed->GetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, &changedRate);
                changed->GetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, &changedBlock);
                changed->GetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, &changedBits);
                changed->GetUINT32(MF_MT_AUDIO_NUM_CHANNELS, &changedChannels);
                changed->GetGUID(MF_MT_SUBTYPE, &subtype);
                if (changedRate != sampleRate || changedBlock != alignment || changedBits != 16 ||
                    changedChannels != channels || subtype != MFAudioFormat_PCM) { hr = MF_E_INVALIDMEDIATYPE; break; }
            }
            if (sample) {
                ComPtr<IMFMediaBuffer> buffer;
                if (FAILED(hr = sample->ConvertToContiguousBuffer(&buffer))) break;
                BYTE *bytes = nullptr; DWORD length = 0;
                if (FAILED(hr = buffer->Lock(&bytes, nullptr, &length))) break;
                int64_t position = (stamp / 10000000) * sampleRate + (stamp % 10000000) * sampleRate / 10000000;
                uint64_t target = position > 0 ? (uint64_t)position : 0;
                hr = writeSilence(target);
                uint64_t skip = position < 0 ? (uint64_t)(-position) + frames : frames - target;
                uint64_t count = length / alignment;
                if (SUCCEEDED(hr) && count > skip) {
                    if (frames + count - skip > maxFrames) hr = HRESULT_FROM_WIN32(ERROR_FILE_TOO_LARGE);
                    else if (fwrite(bytes + skip * alignment, alignment, (size_t)(count - skip), decoded) != count - skip) hr = E_FAIL;
                    else frames += count - skip;
                }
                buffer->Unlock();
                if (FAILED(hr)) break;
            }
            if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
        }
        if (FAILED(hr)) break;
        // Preserve a delayed start and trailing silence, so reversed time maps
        // to the same presentation clock as the original movie/audio file.
        PROPVARIANT value;
        PropVariantInit(&value);
        if (SUCCEEDED(reader->GetPresentationAttribute(MF_SOURCE_READER_MEDIASOURCE, MF_PD_DURATION, &value))
            && value.vt == VT_UI8) {
            uint64_t tail = (value.uhVal.QuadPart / 10000000) * sampleRate
                          + (value.uhVal.QuadPart % 10000000) * sampleRate / 10000000;
            hr = writeSilence((frames > tail ? frames : tail));
        }
        PropVariantClear(&value);
        if (FAILED(hr)) break;
        for (UINT32 version = 0; version < outputCount; ++version) {
            _wfopen_s(&outputs[version], version ? vi : vo, L"wb");
            if (!outputs[version]) { hr = E_FAIL; break; }
            UINT32 size = (UINT32)(frames * outputChannels * 2), riffSize = size + 36;
            UINT32 fmtSize = 16, rate = sampleRate, byteRate = rate * outputChannels * 2;
            UINT16 format = 1, channelCount = (UINT16)outputChannels, block = channelCount * 2, depth = 16;
            FILE *file = outputs[version];
            if (fwrite("RIFF", 1, 4, file) != 4 || fwrite(&riffSize, 4, 1, file) != 1 ||
                fwrite("WAVEfmt ", 1, 8, file) != 8 || fwrite(&fmtSize, 4, 1, file) != 1 ||
                fwrite(&format, 2, 1, file) != 1 || fwrite(&channelCount, 2, 1, file) != 1 ||
                fwrite(&rate, 4, 1, file) != 1 || fwrite(&byteRate, 4, 1, file) != 1 ||
                fwrite(&block, 2, 1, file) != 1 || fwrite(&depth, 2, 1, file) != 1 ||
                fwrite("data", 1, 4, file) != 4 || fwrite(&size, 4, 1, file) != 1) { hr = E_FAIL; break; }
        }
        if (FAILED(hr)) break;
        PCMBuffer input((size_t)sampleRate * alignment), output((size_t)sampleRate * outputChannels * 2);
        if (!input.data() || !output.data()) { hr = E_OUTOFMEMORY; break; }
        uint64_t end = frames;
        while (end) {
            if (cancelled && cancelled()) { hr = HRESULT_FROM_WIN32(ERROR_CANCELLED); break; }
            size_t count = (size_t)(end < sampleRate ? end : sampleRate);
            if (_fseeki64(decoded, (__int64)((end - count) * alignment), SEEK_SET) ||
                fread(input.data(), alignment, count, decoded) != count) { hr = E_FAIL; break; }
            for (UINT32 version = 0; version < outputCount; ++version) {
                size_t block = outputChannels * 2;
                for (size_t frame = 0; frame < count; ++frame)
                    memcpy(output.data() + frame * block,
                           input.data() + (count - frame - 1) * alignment + version * block, block);
                if (fwrite(output.data(), block, count, outputs[version]) != count) { hr = E_FAIL; break; }
            }
            if (FAILED(hr)) break;
            end -= count;
        }
        if (SUCCEEDED(hr)) { *duration = (double)frames / sampleRate; *paired = outputCount == 2; }
    } while (false);
    for (FILE *file : outputs) if (file && fclose(file)) hr = E_FAIL;
    fclose(decoded); DeleteFileW(tempFile);
    if (FAILED(hr)) { DeleteFileW(vo); DeleteFileW(vi); }
    return hr;
}

int32_t cappella_reverse_audio(const uint16_t *source, const uint16_t *vo, const uint16_t *vi,
                              int32_t ordinal, int32_t *streams, int32_t *paired, double *duration,
                              int32_t (*cancelled)(void)) {
    if (!source || !vo || !vi || !streams || !paired || !duration || ordinal < 0) return E_INVALIDARG;
    *streams = 0; *paired = 0; *duration = 0;
    HRESULT apartment = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(apartment) && apartment != RPC_E_CHANGED_MODE) return apartment;
    HRESULT hr = MFStartup(MF_VERSION, MFSTARTUP_FULL);
    if (SUCCEEDED(hr)) {
        {
            ComPtr<IMFSourceReader> reader;
            hr = MFCreateSourceReaderFromURL((const wchar_t *)source, nullptr, &reader);
            if (SUCCEEDED(hr)) {
                DWORD chosen = MF_SOURCE_READER_INVALID_STREAM_INDEX;
                for (DWORD index = 0;; ++index) {
                    ComPtr<IMFMediaType> type;
                    HRESULT status = reader->GetNativeMediaType(index, 0, &type);
                    if (status == MF_E_INVALIDSTREAMNUMBER) break;
                    if (FAILED(status)) { hr = status; break; }
                    GUID major;
                    if (SUCCEEDED(type->GetGUID(MF_MT_MAJOR_TYPE, &major)) && major == MFMediaType_Audio) {
                        if ((*streams)++ == ordinal) chosen = index;
                    }
                }
                if (SUCCEEDED(hr)) {
                    if (chosen == MF_SOURCE_READER_INVALID_STREAM_INDEX) hr = S_FALSE;
                    else hr = reverse_stream(reader.Get(), chosen, (const wchar_t *)vo, (const wchar_t *)vi,
                                             duration, paired, cancelled);
                }
            }
        }
        MFShutdown();
    }
    if (SUCCEEDED(apartment)) CoUninitialize();
    return hr;
}
