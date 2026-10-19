#define COBJMACROS
#include <windows.h>
#include <unknwn.h>
#include <shobjidl.h>
#include "include/desktop.h"

// Same ABI and conversion used by Microsoft.UI.Interop.GetWindowFromWindowId.
typedef struct CappellaWindowId { UINT64 value; } CappellaWindowId;
typedef HRESULT (STDAPICALLTYPE *GetWindowFromId)(CappellaWindowId, HWND *);

int32_t cappella_attach_picker(void *picker, uint64_t window_id, int32_t *stage) {
    const IID pickerIID = {0x3E68D4BD,0x7135,0x4D10,{0x80,0x18,0x9F,0xB6,0xD9,0xF3,0x3F,0xA1}};
    *stage = 1;
    if (!picker || !window_id) return E_INVALIDARG;
    // Use AppWindow.Id instead of querying the Swift-projected XAML Window.
    // The Windows App SDK bootstrap has already loaded this runtime dependency.
    HMODULE module = GetModuleHandleW(L"Microsoft.Internal.FrameworkUdk.dll");
    if (!module) module = LoadLibraryW(L"Microsoft.Internal.FrameworkUdk.dll");
    if (!module) return HRESULT_FROM_WIN32(GetLastError());
    *stage = 2;
    GetWindowFromId convert = (GetWindowFromId)GetProcAddress(module, "Windowing_GetWindowFromWindowId");
    if (!convert) return HRESULT_FROM_WIN32(GetLastError());
    HWND handle = NULL;
    CappellaWindowId id = {window_id};
    HRESULT hr = convert(id, &handle);
    if (FAILED(hr)) return hr;
    if (!handle) return E_HANDLE;
    *stage = 3;
    IInitializeWithWindow *initializable = NULL;
    hr = IUnknown_QueryInterface((IUnknown *)picker, &pickerIID, (void **)&initializable);
    if (FAILED(hr)) return hr;
    *stage = 4;
    hr = IInitializeWithWindow_Initialize(initializable, handle);
    IInitializeWithWindow_Release(initializable);
    return hr;
}
