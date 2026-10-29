#import <NativecadeRuntime/NativecadeRuntime.h>

extern void NativecadePresentLibrary(void);
extern void NativecadeHideLibrary(void);

int main(int argc, char **argv) {
    return NativecadeRunApplication(argc, argv, NativecadePresentLibrary, NativecadeHideLibrary);
}
