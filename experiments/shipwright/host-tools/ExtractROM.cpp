#include "TorchExtract.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>

// The pinned upstream CLI still passes a filename to the newer vector API.
// Keep the adaptation here, outside the unmodified upstream checkout.
int main(int argc, char** argv) {
    if (argc != 4) {
        std::cerr << "Usage: soh-torch ROM.z64 ASSET_YML_DIRECTORY OUTPUT_DIRECTORY\n";
        return 2;
    }
    try {
        std::ifstream input(argv[1], std::ios::binary | std::ios::ate);
        if (!input) throw std::runtime_error("Could not open ROM");
        const auto length = input.tellg();
        if (length < 64 || length > 64 * 1024 * 1024 || length % 4 != 0)
            throw std::runtime_error("Invalid ROM size");
        std::vector<uint8_t> rom(static_cast<size_t>(length));
        input.seekg(0);
        if (!input.read(reinterpret_cast<char*>(rom.data()), length))
            throw std::runtime_error("Incomplete ROM read");
        if (rom[0] != 0x80 || rom[1] != 0x37 || rom[2] != 0x12 || rom[3] != 0x40)
            throw std::runtime_error("Use a verified, canonical big-endian ROM");
        std::filesystem::create_directories(argv[3]);
        const auto archive = SohTorch::Extract(std::move(rom), argv[2], argv[3], "9.3.1", nullptr);
        if (archive.empty()) throw std::runtime_error("Asset extraction failed");
        std::cout << "Created " << archive << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}
