#include "platform_audio.h"
#import <AudioToolbox/AudioToolbox.h>
#import <Foundation/Foundation.h>
#include <cstdint>
#include <string>
#include <vector>

namespace {
void WriteLE32(std::string& out, uint32_t value) {
 out.push_back(static_cast<char>(value));
 out.push_back(static_cast<char>(value>>8));
 out.push_back(static_cast<char>(value>>16));
 out.push_back(static_cast<char>(value>>24));
}
void WriteLE16(std::string& out, uint16_t value) {
 out.push_back(static_cast<char>(value));
 out.push_back(static_cast<char>(value>>8));
}
void SetError(std::string* error, const char* text) {
 if(error) *error=text;
}

bool DecodeExtAudioFile(ExtAudioFileRef ext, std::string* wav, std::string* error) {
 AudioStreamBasicDescription file_format{};
 UInt32 size=sizeof(file_format);
 OSStatus status=ExtAudioFileGetProperty(ext,kExtAudioFileProperty_FileDataFormat,&size,&file_format);
 if(status!=noErr) { SetError(error,"audio file format unavailable"); return false; }
 AudioStreamBasicDescription client{};
 client.mSampleRate=file_format.mSampleRate>1 ? file_format.mSampleRate : 44100;
 client.mFormatID=kAudioFormatLinearPCM;
 client.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;
 client.mBitsPerChannel=16;
 client.mChannelsPerFrame=file_format.mChannelsPerFrame ? file_format.mChannelsPerFrame : 1;
 if(client.mChannelsPerFrame>2) client.mChannelsPerFrame=2;
 client.mFramesPerPacket=1;
 client.mBytesPerFrame=client.mChannelsPerFrame*2;
 client.mBytesPerPacket=client.mBytesPerFrame;
 status=ExtAudioFileSetProperty(ext,kExtAudioFileProperty_ClientDataFormat,sizeof(client),&client);
 if(status!=noErr) { SetError(error,"audio converter unavailable"); return false; }
 SInt64 frames=0;
 size=sizeof(frames);
 ExtAudioFileGetProperty(ext,kExtAudioFileProperty_FileLengthFrames,&size,&frames);
 std::string pcm;
 if(frames>0 && frames<48000*60*30)
  pcm.reserve(static_cast<size_t>(frames)*client.mBytesPerFrame);
 const UInt32 chunk=4096;
 std::vector<char> buffer(static_cast<size_t>(chunk)*client.mBytesPerFrame);
 while(true) {
  AudioBufferList list{};
  list.mNumberBuffers=1;
  list.mBuffers[0].mNumberChannels=client.mChannelsPerFrame;
  list.mBuffers[0].mDataByteSize=static_cast<UInt32>(buffer.size());
  list.mBuffers[0].mData=buffer.data();
  UInt32 count=chunk;
  status=ExtAudioFileRead(ext,&count,&list);
  if(status!=noErr) { SetError(error,"audio decode failed"); return false; }
  if(count==0) break;
  pcm.append(buffer.data(),static_cast<size_t>(count)*client.mBytesPerFrame);
  if(pcm.size()>16ull*1024*1024) { SetError(error,"decoded audio too large"); return false; }
 }
 if(pcm.empty()) { SetError(error,"decoded audio empty"); return false; }
 std::string out;
 out.reserve(44+pcm.size());
 out.append("RIFF",4);
 WriteLE32(out,static_cast<uint32_t>(36+pcm.size()));
 out.append("WAVEfmt ",8);
 WriteLE32(out,16);
 WriteLE16(out,1);
 WriteLE16(out,static_cast<uint16_t>(client.mChannelsPerFrame));
 WriteLE32(out,static_cast<uint32_t>(client.mSampleRate));
 WriteLE32(out,static_cast<uint32_t>(client.mSampleRate)*client.mBytesPerFrame);
 WriteLE16(out,static_cast<uint16_t>(client.mBytesPerFrame));
 WriteLE16(out,16);
 out.append("data",4);
 WriteLE32(out,static_cast<uint32_t>(pcm.size()));
 out.append(pcm);
 *wav=std::move(out);
 return true;
}
}

namespace slate {
bool DecodeAudioFileToWav(const std::string& path, std::string* wav, std::string* error) {
 if(!wav || path.empty()) { SetError(error,"invalid decode arguments"); return false; }
 @autoreleasepool {
  NSURL* url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]];
  ExtAudioFileRef ext=nullptr;
  OSStatus status=ExtAudioFileOpenURL((__bridge CFURLRef)url,&ext);
  if(status!=noErr || !ext) { SetError(error,"could not open audio file"); return false; }
  const bool ok=DecodeExtAudioFile(ext,wav,error);
  ExtAudioFileDispose(ext);
  return ok;
 }
}

bool DecodeAudioBytesToWav(const void* data, size_t size, std::string* wav, std::string* error) {
 if(!data || size<16 || !wav) { SetError(error,"invalid audio bytes"); return false; }
 if(size>32ull*1024*1024) { SetError(error,"audio source too large"); return false; }
 @autoreleasepool {
  NSString* dir=NSTemporaryDirectory();
  NSString* path=[[dir stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]]
   stringByAppendingPathExtension:@"m4a"];
  NSData* payload=[NSData dataWithBytes:data length:size];
  if(![payload writeToFile:path atomically:YES]) { SetError(error,"could not stage audio"); return false; }
  const bool ok=DecodeAudioFileToWav(path.fileSystemRepresentation,wav,error);
  [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
  return ok;
 }
}
}
