#import "platform/macos/download_manager.h"
#import <sys/xattr.h>
#import <sys/stat.h>
#include <cassert>
#include <cstdio>
@interface SlateDownloadManager (Testing)
- (void)finishStagedItem:(SlateDownloadItem*)item;
- (void)saveHistory;
@end
static void Wait(SlateDownloadItem* item) {
 NSDate* deadline=[NSDate dateWithTimeIntervalSinceNow:5];
 while(item.state==SlateDownloadStateFinishing && deadline.timeIntervalSinceNow>0)
  [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
 assert(item.state!=SlateDownloadStateFinishing);
}
int main() { @autoreleasepool {
 NSString* root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
 NSString* folder=[root stringByAppendingPathComponent:@"Downloads"];
 [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
 setenv("SLATE_DATA_DIR",root.UTF8String,1); setenv("SLATE_DOWNLOADS_DIR",folder.UTF8String,1);
 SlateDownloadManager* manager=SlateDownloadManager.sharedManager;
 assert([manager startDownloadFromURL:[NSURL URLWithString:@"file:///etc/passwd"] suggestedFilename:nil]==nil);
 assert([manager startDownloadFromURL:[NSURL URLWithString:@"ftp://example.com/file"] suggestedFilename:nil]==nil);
 NSMutableArray* items=[manager valueForKey:@"_items"];
 NSString* existing=[folder stringByAppendingPathComponent:@"report.txt"];
 [@"existing file" writeToFile:existing atomically:YES encoding:NSUTF8StringEncoding error:nil];
 SlateDownloadItem* item=[[SlateDownloadItem alloc] init]; item.filename=@"report.txt"; item.targetDirectory=folder;
 item.stagingURL=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@".staged"]];
 [@"complete payload" writeToURL:item.stagingURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
 NSString* other=[root stringByAppendingPathComponent:@"OtherSpace"];
 [NSFileManager.defaultManager createDirectoryAtPath:other withIntermediateDirectories:YES attributes:nil error:nil];
 manager.downloadsDirectory=other;
 [items addObject:item]; [manager finishStagedItem:item];
 assert(!item.fileAvailable); Wait(item);
 assert(item.state==SlateDownloadStateCompleted && item.fileAvailable);
 assert([item.filename isEqual:@"report (1).txt"]);
 assert([item.destinationURL.path.stringByDeletingLastPathComponent.stringByResolvingSymlinksInPath isEqual:folder.stringByResolvingSymlinksInPath]);
 assert([[NSString stringWithContentsOfFile:existing encoding:NSUTF8StringEncoding error:nil] isEqual:@"existing file"]);
 assert([[NSString stringWithContentsOfURL:item.destinationURL encoding:NSUTF8StringEncoding error:nil] isEqual:@"complete payload"]);
 char quarantine[512]; assert(getxattr(item.destinationURL.path.fileSystemRepresentation,"com.apple.quarantine",quarantine,sizeof(quarantine),0,XATTR_NOFOLLOW)>0);
 struct stat st; assert(stat(item.destinationURL.path.fileSystemRepresentation,&st)==0 && (st.st_mode&0777)==0600);
 NSURL* spoof=[SlateDownloadManager uniqueDestinationURLForFilename:@"receipt\u202Etxt.exe" inDirectory:folder];
 assert([spoof.lastPathComponent rangeOfString:@"\u202E"].location==NSNotFound && [spoof.pathExtension isEqual:@"exe"]);
 NSString* longName=[[@"文" stringByPaddingToLength:180 withString:@"文" startingAtIndex:0] stringByAppendingString:@".pdf"];
 NSURL* shortened=[SlateDownloadManager uniqueDestinationURLForFilename:longName inDirectory:folder];
 assert([shortened.lastPathComponent lengthOfBytesUsingEncoding:NSUTF8StringEncoding]<=240 && [shortened.pathExtension isEqual:@"pdf"]);
 // A staged symlink must fail closed and leave its target untouched.
 SlateDownloadItem* unsafe=[[SlateDownloadItem alloc] init]; unsafe.filename=@"unsafe.txt";
 unsafe.stagingURL=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@".symlink"]];
 [NSFileManager.defaultManager createSymbolicLinkAtPath:unsafe.stagingURL.path withDestinationPath:existing error:nil];
 [items addObject:unsafe]; [manager finishStagedItem:unsafe]; Wait(unsafe);
 assert(unsafe.state==SlateDownloadStateFailed && !unsafe.fileAvailable);
 assert([[NSString stringWithContentsOfFile:existing encoding:NSUTF8StringEncoding error:nil] isEqual:@"existing file"]);
 // Cancellation retains a history entry; clearing history never deletes files.
 SlateDownloadItem* cancelled=[[SlateDownloadItem alloc] init]; cancelled.filename=@"cancelled.txt"; [items addObject:cancelled];
 [cancelled cancel]; assert(cancelled.state==SlateDownloadStateCancelled && [manager.items containsObject:cancelled]);
 SlateDownloadItem* privateItem=[[SlateDownloadItem alloc] init]; privateItem.privateDownload=YES; privateItem.filename=@"PRIVATE_SECRET"; privateItem.state=SlateDownloadStateCompleted; [items addObject:privateItem];
 [manager saveHistory];
 NSString* history=[NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"downloads.json"] encoding:NSUTF8StringEncoding error:nil];
 assert([history rangeOfString:@"PRIVATE_SECRET"].location==NSNotFound);
 assert([history rangeOfString:@"cancelled.txt"].location!=NSNotFound);
 assert(([SlateDownloadItem fromDictionary:@{@"filename":@42,@"state":@99}]==nil));
 assert(([SlateDownloadItem fromDictionary:@{@"filename":@"ok",@"state":@{},@"destinationPath":NSNull.null}]==nil));
 assert(([SlateDownloadItem fromDictionary:@{@"filename":@"paused",@"state":@(SlateDownloadStatePaused)}].state==SlateDownloadStateCancelled));
 [manager clearCompleted]; assert(manager.items.count==0);
 assert([NSFileManager.defaultManager fileExistsAtPath:item.destinationURL.path]);
 // Opening/revealing a replacement symlink is unavailable.
 [NSFileManager.defaultManager removeItemAtURL:item.destinationURL error:nil];
 [NSFileManager.defaultManager createSymbolicLinkAtPath:item.destinationURL.path withDestinationPath:existing error:nil];
 assert(!item.fileAvailable);
 [NSFileManager.defaultManager removeItemAtPath:root error:nil];
 puts("Download publication, quarantine, collision, cancellation, private history, and symlink tests passed.");
} }
