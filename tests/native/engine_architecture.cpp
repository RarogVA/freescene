#include "../../native/engine.h"
#include <nlohmann/json.hpp>
#include <filesystem>
#include <iostream>

// Execute against each packaged architecture, using only a fresh isolated profile.
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    const auto root = std::filesystem::absolute(argv[1]);
    std::filesystem::create_directories(root);
    const auto config = nlohmann::json{{"profile", (root / "profile").string()},
                                     {"downloads", (root / "downloads").string()},
                                     {"isolated", true}};
    void *engine = fs_engine_create(config.dump().c_str());
    if (!engine) return 3;
    char *raw = fs_engine_command(engine, "{\"method\":\"status\"}");
    const auto status = nlohmann::json::parse(raw ? raw : "null");
    fs_engine_free(raw);
    const bool passed = status.contains("result") &&
                        status["result"].contains("tasks") &&
                        status["result"]["tasks"].is_array() &&
                        status["result"]["tasks"].empty();
    fs_engine_destroy(engine);
    std::cout << nlohmann::json{{"passed", passed}, {"isolatedProfile", true},
                               {"engineCreateStatusDestroy", passed}}.dump() << '\n';
    return passed ? 0 : 1;
}
