#pragma once
#include <string>

namespace slate {
// Decode AAC/M4A/ALAC (and other AudioToolbox file types) to 16-bit PCM WAV
// using the macOS AudioToolbox decoder. Does not ship an MPEG codec.
bool DecodeAudioFileToWav(const std::string& path, std::string* wav, std::string* error);
bool DecodeAudioBytesToWav(const void* data, size_t size, std::string* wav, std::string* error);
}
