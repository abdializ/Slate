// File purpose: Declares AudioToolbox conversion of supported audio files/bytes into 16-bit PCM
// WAV. This utility is built by the audio test target; the current WebKit adapter does not call it
// as a custom audio-scheme pipeline.

#pragma once
#include <string>

namespace slate {
// Decode AAC/M4A/ALAC (and other AudioToolbox file types) to 16-bit PCM WAV
// using the macOS AudioToolbox decoder. Does not ship an MPEG codec.
// Slate note: Both entry points return success and place decoded bytes or an error into the output
// arguments.
bool DecodeAudioFileToWav(const std::string& path, std::string* wav, std::string* error);
bool DecodeAudioBytesToWav(const void* data, size_t size, std::string* wav, std::string* error);
}
