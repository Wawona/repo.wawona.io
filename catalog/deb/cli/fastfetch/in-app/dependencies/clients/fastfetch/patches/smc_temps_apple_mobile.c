#include "smc_temps.h"

const char* ffDetectSmcSpecificTemp(const char* sensor, double* result) {
    (void)sensor;
    (void)result;
    return "SMC unavailable on Apple mobile";
}

const char* ffDetectSmcTemps(enum FFTempType type, double* result) {
    (void)type;
    (void)result;
    return "SMC unavailable on Apple mobile";
}
