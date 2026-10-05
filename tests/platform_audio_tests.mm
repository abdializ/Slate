#include "engine/platform_audio.h"
#import <Foundation/Foundation.h>
#include <cmath>
#include <cstdio>
#include <string>
#include <vector>

namespace {
std::string WriteWav(const std::vector<int16_t>& pcm, int rate) {
 std::string out;
 auto le32=[&](uint32_t v){ out.push_back(v); out.push_back(v>>8); out.push_back(v>>16); out.push_back(v>>24); };
 auto le16=[&](uint16_t v){ out.push_back(v); out.push_back(v>>8); };
 out.append("RIFF",4);
 le32(static_cast<uint32_t>(36+pcm.size()*2));
 out.append("WAVEfmt ",8);
 le32(16); le16(1); le16(1); le32(rate); le32(rate*2); le16(2); le16(16);
 out.append("data",4);
 le32(static_cast<uint32_t>(pcm.size()*2));
 for(int16_t s:pcm) le16(static_cast<uint16_t>(s));
 return out;
}
}

int main() {
 std::vector<int16_t> pcm(4410);
 for(size_t i=0;i<pcm.size();++i)
  pcm[i]=static_cast<int16_t>(std::sin(2*3.1415926535*440.0*i/44100.0)*30000);
 NSString* dir=NSTemporaryDirectory();
 NSString* wavPath=[dir stringByAppendingPathComponent:@"slate-tone.wav"];
 NSString* m4aPath=[dir stringByAppendingPathComponent:@"slate-tone.m4a"];
 std::string wav=WriteWav(pcm,44100);
 NSData* wavData=[NSData dataWithBytes:wav.data() length:wav.size()];
 if(![wavData writeToFile:wavPath atomically:YES]) { fprintf(stderr,"write wav failed\n"); return 1; }
 NSTask* convert=[NSTask new];
 convert.launchPath=@"/usr/bin/afconvert";
 // Use a format reported by afconvert for m4af on this host. AAC encoding
 // is not available in every macOS environment where this test runs.
 convert.arguments=@[@"-f",@"m4af",@"-d",@"LEI16",wavPath,m4aPath];
 [convert launch]; [convert waitUntilExit];
 if(convert.terminationStatus!=0) { fprintf(stderr,"afconvert failed\n"); return 1; }
 std::string decoded, error;
 if(!slate::DecodeAudioFileToWav(m4aPath.fileSystemRepresentation,&decoded,&error)) {
  fprintf(stderr,"decode failed: %s\n",error.c_str()); return 1;
 }
 if(decoded.size()<1000 || decoded.compare(0,4,"RIFF")!=0 || decoded.compare(8,4,"WAVE")!=0) {
  fprintf(stderr,"decoded wav malformed size=%zu\n",decoded.size()); return 1;
 }
 NSData* bytes=[NSData dataWithContentsOfFile:m4aPath];
 std::string fromBytes;
 if(!slate::DecodeAudioBytesToWav(bytes.bytes,bytes.length,&fromBytes,&error) || fromBytes.size()<1000) {
  fprintf(stderr,"bytes decode failed: %s\n",error.c_str()); return 1;
 }
 fprintf(stdout,"platform_audio_ok wav=%zu m4a=%zu\n",decoded.size(),(size_t)bytes.length);
 return 0;
}
