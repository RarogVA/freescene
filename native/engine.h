#pragma once
#ifdef __cplusplus
extern "C" {
#endif
__attribute__((visibility("default"))) void* fs_engine_create(const char* config);
__attribute__((visibility("default"))) char* fs_engine_command(void* engine, const char* request);
__attribute__((visibility("default"))) void fs_engine_free(char* value);
__attribute__((visibility("default"))) void fs_engine_destroy(void* engine);
#ifdef __cplusplus
}
#endif
