#include "x86_64/efibind.h"
#include <efi.h>
#include <efilib.h>

#define LOADING_COUNT 50

#define SIGNED_MIN(T) ((~(1 << ((sizeof(T) * 8) - 1))) + 1)
#define SIGNED_MAX(T) (~(1 << ((sizeof(T) * 8) - 1)))

EFI_STATUS
EFIAPI
efi_main(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE *SystemTable) {
  EFI_STATUS Status;
  EFI_INPUT_KEY Key;

  Print(L"BOOTING UP AWESOMENESS [%d]\r\n", LOADING_COUNT);

  int i = LOADING_COUNT;
  while (i-- > 0) {
    Print(L"=");
    WaitForSingleEvent(ST->ConIn->WaitForKey, 1);
    // BS->Stall(10);
  }

  Print(L"\r\n");

  return EFI_SUCCESS;
}
