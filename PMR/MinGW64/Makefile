# =====================================================
# Makefile: Build a 64-bit DLL with embedded BMP resource
# Requires MinGW-w64 toolchain (x86_64-w64-mingw32)
# =====================================================

# --- Tools ---
CC      = x86_64-w64-mingw32-gcc
RC      = windres

# --- Files ---
TARGET  = NorbertM.dll
LIB     = libNorbertM.a
OBJS    = NorbertM.o NorbertM_res.o

# --- Compiler & Linker flags ---
CFLAGS  = -Wall -O2
LDFLAGS = -shared -Wl,--out-implib,$(LIB)

# --- Default target ---
all: $(TARGET)

# --- Compile C source ---
NorbertM.o: NorbertM.c resource.h
	$(CC) -c NorbertM.c -o NorbertM.o $(CFLAGS)

# --- Compile resource (embed BMP) ---
NorbertM_res.o: NorbertM.rc resource.h Norbert.bmp
	$(RC) NorbertM.rc -O coff -o NorbertM_res.o

# --- Link into DLL ---
$(TARGET): $(OBJS)
	$(CC) $(OBJS) -o $(TARGET) $(LDFLAGS)

# --- Clean up ---
clean:
	del /f /q *.o *.dll *.a 2>nul || rm -f *.o *.dll *.a
