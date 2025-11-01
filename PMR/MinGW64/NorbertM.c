// mydll.c
#include <windows.h>
#include "resource.h"

__declspec(dllexport)
HBITMAP LoadMyBitmap(void)
{
    HMODULE hModule = GetModuleHandle("mydll.dll");
    if (!hModule) return NULL;

//    return LoadBitmap(hModule, MAKEINTRESOURCE(IDB_IMAGE));
    return LoadBitmap(hModule, IDB_IMAGE);
}
