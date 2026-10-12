#import "ExperimentalOTA.h"
#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>

NSString *TIOExperimentalOTASHA(void){return @"ad5054e3d7bda90e94d293bea882bd8dd5a125bcc8f42c13a59b2e149313c9e3";}
NSString *TIOStockOTASHA(void){return @"54eb155b1b9980c0334005c2051720879204b6b5448180ee594eb735b92e905a";}
static NSUInteger TFP1ArchiveBytes(void){return 9300112;}
static NSUInteger StockArchiveBytes(void){return 9223967;}
static id Fail(NSError **error,NSString *message){if(error)*error=[NSError errorWithDomain:@"TurboIO.ExperimentalOTA" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];return nil;}
static NSString *HexOfData(NSData *data){unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);NSMutableString *hex=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[hex appendFormat:@"%02x",digest[i]];return hex;}
NSString * _Nullable TIOExperimentalOTAKind(NSData *data){
    if(!data)return nil;
    NSUInteger bytes=data.length;
    if(bytes==TFP1ArchiveBytes()&&[HexOfData(data) isEqual:TIOExperimentalOTASHA()])return @"TFP1";
    if(bytes==StockArchiveBytes()&&[HexOfData(data) isEqual:TIOStockOTASHA()])return @"STOCK";
    return nil;
}
NSDictionary *TIOCheckExperimentalOTA(NSData *data,NSError **error){
    NSString *kind=TIOExperimentalOTAKind(data);
    if(!kind)return Fail(error,@"文件大小或 SHA-256 不匹配。只接受本次 TFP1 实验 ZIP 或原厂 1.0.4.12 归档，未保存、未发送。");
    BOOL stock=[kind isEqual:@"STOCK"];
    NSString *hex=[HexOfData(data) copy];
    return @{@"schema":@1,@"candidate":stock?@"Stock 1.0.4.12 Original":@"Turbo WeRead TFP1",
             @"kind":kind,@"baseFirmware":@"1.0.4.12",
             @"archiveSHA256":hex,@"archiveBytes":@(data.length),
             @"changedPayloads":stock?@[]:@[@"nuttx_ap.bin"],
             @"unchangedPayloadCount":@(stock?0:13),
             @"integrityPassed":@YES,@"sent":@NO,
             @"runtimeValidated":@NO,@"officialDispatchConnected":@NO};
}
static NSData *Read(NSURL *source,NSError **error){
    if(!source.isFileURL)return Fail(error,@"只接受本地文件。");
    NSInputStream *stream=[NSInputStream inputStreamWithURL:source];[stream open];
    NSMutableData *data=[NSMutableData new];uint8_t buffer[65536];NSInteger n;
    while((n=[stream read:buffer maxLength:sizeof(buffer)])>0){
        if(data.length+(NSUInteger)n>9300112){[stream close];return Fail(error,@"文件过大；未保存、未发送。");}
        [data appendBytes:buffer length:(NSUInteger)n];
    }
    NSError *readError=stream.streamError;[stream close];
    if(n<0||readError){if(error)*error=readError?:[NSError errorWithDomain:@"TurboIO.ExperimentalOTA" code:2 userInfo:@{NSLocalizedDescriptionKey:@"无法读取文件"}];return nil;}
    return TIOCheckExperimentalOTA(data,error)?data:nil;
}
NSDictionary *TIOReadExperimentalOTA(NSURL *file,NSError **error){NSData *data=Read(file,error);return data?TIOCheckExperimentalOTA(data,error):nil;}
NSDictionary *TIOImportExperimentalOTA(NSURL *source,NSURL *directory,NSError **error){
    if(!directory.isFileURL)return Fail(error,@"只接受本地目录。");
    NSData *data=Read(source,error);if(!data)return nil;
    NSDictionary *result=TIOCheckExperimentalOTA(data,error);
    NSFileManager *fm=NSFileManager.defaultManager;
    if(![fm createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return nil;
    if(![directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:error])return nil;
    NSString *sha=[result[@"kind"] isEqual:@"STOCK"]?TIOStockOTASHA():TIOExperimentalOTASHA();
    NSURL *destination=[directory URLByAppendingPathComponent:[sha stringByAppendingString:@".zip"]];
    if([fm fileExistsAtPath:destination.path]){
        if(!TIOReadExperimentalOTA(destination,error))return nil;
    }else{
        // Exclusive creation; no official cache or existing imported file replaced.
        if(![data writeToURL:destination options:NSDataWritingWithoutOverwriting error:error])return nil;
    }
    if(![fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:destination.path error:error])return nil;
#if TARGET_OS_IPHONE
    if(![fm setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:destination.path error:error])return nil;
#endif
    return result;
}

static NSDictionary *PinsForKind(NSString *kind){
    BOOL stock=[kind isEqual:@"STOCK"];
    NSMutableDictionary *base=[@{
    @"cb_fw_venus.bin":@[@114592,@"8799f12071bdac082218e3601c24ab0989275fc2f7db74e37b8314a225c2cf7d"],
    @"fac_test_img.bin":@[@1821552,@"18eb0901c3e0daeae48dd5f015252b6931ea7368f0160c2c985c4e74296d17eb"],
    @"images.bin":@[@324283,@"192fefaa70545856884c89a9186e3f86d8f99a0738b201e116a11bc63011c158"],
    @"lotties.bin":@[@651481,@"ad66d83a3394034f825a12769aad292fc03e59fa865fe06bc43536b918a0b32b"],
    @"nuttx_apc1.bin":@[@1420248,@"97d56ffc6dd575ad3d8bf7739d49e491ad7e4a959db8770b653f5302e171fb5c"],
    @"nuttx_audio.bin":@[@1461920,@"549a72c032595e3829da7d63b7e1fd13cceda1a55dfefa7a7cad02db5a9b42ab"],
    @"nuttx_bth.bin":@[@1160160,@"a8f4594868bffbd3bc08a38d1f3899571608e2d57869d147de3d06f3e4f7a12a"],
    @"ota_installer_progress.bin":@[@5616,@"6fd65d296a667e1a7d94ec129adfd26458a4008ef403b331f855192c36eb3e3f"],
    @"pil_algo_up_demo_nand.dll":@[@504388,@"e266726fe055ac6ec6f785a9440e8da7421402f2b4d3d7889039ad9b94e119c2"],
    @"pil_algo_vad_demo.dll":@[@433432,@"7ac5b5191202adea20c62642987fa0049024dde9c386ba6cd08a1f29ddd5c92c"],
    @"pil_algo_wakeup_dll_nand.dll":@[@287560,@"d1594cb8658b228e52c2606d02f1eab696d35a11ed42ddcb725e76a745f5550f"],
    @"rives.bin":@[@689431,@"836bc019f7152890b94cafafe2edaa024f317526318349f7833319e41158b104"],
    @"smf.json":@[@23510,@"2713dc3a302a65c101fa981500cd8b217766c526b6045bf02db5e9e6763d076d"]} mutableCopy];
    if(stock){
        base[@"OtaFileInfo.json"]=@[@2528,@"9cc71ebd4ec1434619638c49cee2f7089df239763f9fa1e87f081d78d3f5e997"];
        base[@"nuttx_ap.bin"]=@[@9466560,@"53afdf5298815849eafca6f315a70606d2a605aff2e563f79050f797d615a988"];
    }else{
        base[@"OtaFileInfo.json"]=@[@2515,@"21bd0f08234dfdefcad9cea63b8f2ef12cea542a9acc47de1bd832abfc910c24"];
        base[@"nuttx_ap.bin"]=@[@9558216,@"40b08299d66b08a909c9167400f2f660b17904d6b20026477ac470e860942a24"];
    }
    return base;
}
static NSString *KindOfDirectory(NSURL *directory){
    NSData *ap=[NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"nuttx_ap.bin"] options:0 error:nil];
    if(!ap)return nil;
    if(ap.length==9558216)return @"TFP1";
    if(ap.length==9466560)return @"STOCK";
    return nil;
}
static BOOL SameStat(struct stat a,struct stat b){return a.st_dev==b.st_dev&&a.st_ino==b.st_ino&&a.st_size==b.st_size&&a.st_mode==b.st_mode&&a.st_nlink==b.st_nlink&&a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec&&a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec&&a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec&&a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec;}
NSDictionary<NSString *,NSData *> *TIOCopyExperimentalOTAPayloads(NSURL *directory,NSError **error){
    if(!TIOCheckExperimentalOTADirectory(directory,error))return nil;
    NSString *kind=KindOfDirectory(directory);
    if(!kind)return Fail(error,@"待传目录 AP 与 TFP1/原厂均不匹配；未授权发送。");
    NSMutableDictionary *copy=[NSMutableDictionary new];NSDictionary *pins=PinsForKind(kind);
    for(NSString *name in pins){
        NSData *data=[NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:name] options:0 error:error];
        if(!data||data.length!=[pins[name][0] unsignedIntegerValue])return Fail(error,@"待传文件在冻结时改变；未授权发送。");
        uint8_t digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
        NSMutableString *hex=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[hex appendFormat:@"%02x",digest[i]];
        if(![hex isEqual:pins[name][1]])return Fail(error,@"待传文件在冻结时摘要不符；未授权发送。");
        copy[name]=data;
    }
    return TIOCheckExperimentalOTADirectory(directory,error)?[copy copy]:nil;
}
NSDictionary *TIOCheckExperimentalOTADirectory(NSURL *directory,NSError **error){
    if(!directory.isFileURL)return Fail(error,@"只接受本地待传目录。");
    NSString *kind=KindOfDirectory(directory);
    if(!kind)return Fail(error,@"待传目录 AP 与 TFP1/原厂均不匹配；未发送。");
    // Open a directory handle and use openat/O_NOFOLLOW for every member. Never
    // follow a member symlink, FIFO or device. Do not modify old OTA caches.
    int root=open(directory.path.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(root<0)return Fail(error,@"待传目录不存在、不可读或为符号链接；未发送。");
    struct stat before,after;BOOL ok=fstat(root,&before)==0;NSDictionary *pins=PinsForKind(kind);NSMutableSet *names=[NSMutableSet new];
    int copy=dup(root);DIR *stream=copy>=0?fdopendir(copy):NULL;if(!stream){if(copy>=0)close(copy);ok=NO;}
    if(stream){struct dirent *item;errno=0;while((item=readdir(stream))){if(!strcmp(item->d_name,".")||!strcmp(item->d_name,".."))continue;NSString *name=[NSString stringWithUTF8String:item->d_name];if(!name||names.count>=15||!pins[name]){ok=NO;break;}[names addObject:name];errno=0;}if(errno)ok=NO;closedir(stream);}
    if(names.count!=pins.count)ok=NO;
    NSMutableDictionary *identities=[NSMutableDictionary new];NSString *problem=[kind isEqual:@"STOCK"]?@"文件集合与 原厂 1.0.4.12 不符，可能是旧缓存或残缺目录；未发送。":@"文件集合与 TFP1 不符，可能是旧缓存或残缺目录；未发送。";
    for(NSString *name in [pins.allKeys sortedArrayUsingSelector:@selector(compare:)]){
        if(!ok)break;
        int fd=openat(root,name.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
        if(fd<0){ok=NO;break;}struct stat first,last;
        NSUInteger expected=[pins[name][0] unsignedIntegerValue];
        ok=fstat(fd,&first)==0&&S_ISREG(first.st_mode)&&first.st_nlink==1&&first.st_size==(off_t)expected;
        if(ok){CC_SHA256_CTX context;CC_SHA256_Init(&context);uint8_t buffer[65536],digest[CC_SHA256_DIGEST_LENGTH];NSUInteger total=0;ssize_t n=0;
            while(total<expected){n=read(fd,buffer,MIN(sizeof(buffer),expected-total));if(n<0&&errno==EINTR)continue;if(n<=0){ok=NO;break;}CC_SHA256_Update(&context,buffer,(CC_LONG)n);total+=(NSUInteger)n;}
            if(ok){n=read(fd,buffer,1);ok=n==0;}CC_SHA256_Final(digest,&context);
            NSMutableString *hash=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[hash appendFormat:@"%02x",digest[i]];
            ok=ok&&[hash isEqual:pins[name][1]]&&fstat(fd,&last)==0&&SameStat(first,last);
            if(ok)identities[name]=[NSData dataWithBytes:&last length:sizeof(last)];
        }
        close(fd);if(!ok)problem=[NSString stringWithFormat:@"%@ 与固定 %@ 不一致或读取期间改变；未发送。",name,kind];
    }
    // A second pass catches names/inodes replaced after an earlier file was read.
    for(NSString *name in identities){struct stat prior,current;[identities[name] getBytes:&prior length:sizeof(prior)];if(fstatat(root,name.fileSystemRepresentation,&current,AT_SYMLINK_NOFOLLOW)||!SameStat(prior,current))ok=NO;}
    ok=ok&&fstat(root,&after)==0&&SameStat(before,after);
    struct stat currentPath;if(lstat(directory.path.fileSystemRepresentation,&currentPath)||!SameStat(before,currentPath))ok=NO;
    close(root);if(!ok)return Fail(error,problem);
    return @{@"candidate":[kind isEqual:@"STOCK"]?@"Stock 1.0.4.12 Original":@"Turbo WeRead TFP1",@"kind":kind,@"checkedMembers":@15,@"integrityPassed":@YES,@"snapshotOnly":@YES,@"transferSessionBound":@NO,@"sent":@NO,@"flashAuthorized":@NO};
}
