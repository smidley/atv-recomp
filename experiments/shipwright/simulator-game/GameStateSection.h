/* Nativecade starts more than one game per process. Each port's original C globals live in
   these sections so NativecadeRuntime.mm can restore their load-time values before a restart. */
#pragma clang section bss = "__DATA,__game_bss,zerofill" data = "__DATA,__game_data"
