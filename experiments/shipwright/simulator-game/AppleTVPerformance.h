#pragma once
#include "PerformanceSettings.h"

void RecompTVInitializePerformanceDefaults();
void RecompTVApplyPerformancePreset(RecompTV::PerformancePreset preset);
int RecompTVGetFrameTarget(int requested, bool matchRefresh);
void RecompTVPrepareFrame(int targetFps);
void RecompTVRecordFrame(int targetFps);
