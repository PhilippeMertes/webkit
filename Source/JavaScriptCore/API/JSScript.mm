/*
 * Copyright (C) 2019 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "config.h"
#import "JSScriptInternal.h"

#import "APICast.h"
#import "CachedTypes.h"
#import "CodeCache.h"
#import "Identifier.h"
#import "JSContextInternal.h"
#import "JSScriptSourceProvider.h"
#import "JSSourceCode.h"
#import "JSValuePrivate.h"
#import "JSVirtualMachineInternal.h"
#import "ParserError.h"
#import "Symbol.h"
#include <sys/stat.h>
#include <wtf/FileMetadata.h>
#include <wtf/FileSystem.h>
#include <wtf/Scope.h>
#include <wtf/spi/darwin/DataVaultSPI.h>

#if JSC_OBJC_API_ENABLED

@implementation JSScript {
    __weak JSVirtualMachine* m_virtualMachine;
    JSScriptType m_type;
    FileSystem::MappedFileData m_mappedSource;
    String m_source;
    RetainPtr<NSURL> m_sourceURL;
    RetainPtr<NSURL> m_cachePath;
    RefPtr<JSC::CachedBytecode> m_cachedBytecode;
}

static JSScript *createError(NSString *message, NSError** error)
{
    if (error)
        *error = [NSError errorWithDomain:@"JSScriptErrorDomain" code:1 userInfo:@{ @"message": message }];
    return nil;
}

static bool validateBytecodeCachePath(NSURL* cachePath, NSError** error)
{
    if (!cachePath)
        return true;

    URL cachePathURL([cachePath absoluteURL]);
    if (!cachePathURL.isLocalFile()) {
        createError([NSString stringWithFormat:@"Cache path `%@` is not a local file", static_cast<NSString *>(cachePathURL)], error);
        return false;
    }

    String systemPath = cachePathURL.fileSystemPath();

    if (auto metadata = FileSystem::fileMetadata(systemPath)) {
        if (metadata->type != FileMetadata::Type::File) {
            createError([NSString stringWithFormat:@"Cache path `%@` already exists and is not a file", static_cast<NSString *>(systemPath)], error);
            return false;
        }
    }

    String directory = FileSystem::directoryName(systemPath);
    if (directory.isNull()) {
        createError([NSString stringWithFormat:@"Cache path `%@` does not contain in a valid directory", static_cast<NSString *>(systemPath)], error);
        return false;
    }

    if (!FileSystem::fileIsDirectory(directory, FileSystem::ShouldFollowSymbolicLinks::No)) {
        createError([NSString stringWithFormat:@"Cache directory `%@` is not a directory or does not exist", static_cast<NSString *>(directory)], error);
        return false;
    }

#if USE(APPLE_INTERNAL_SDK)
    if (rootless_check_datavault_flag(FileSystem::fileSystemRepresentation(directory).data(), nullptr)) {
        createError([NSString stringWithFormat:@"Cache directory `%@` is not a data vault", static_cast<NSString *>(directory)], error);
        return false;
    }
#endif

    return true;
}

+ (instancetype)scriptOfType:(JSScriptType)type withSource:(NSString *)source andSourceURL:(NSURL *)sourceURL andBytecodeCache:(NSURL *)cachePath inVirtualMachine:(JSVirtualMachine *)vm error:(out NSError **)error
{
    if (!validateBytecodeCachePath(cachePath, error))
        return nil;

    JSScript *result = [[[JSScript alloc] init] autorelease];
    result->m_virtualMachine = vm;
    result->m_type = type;
    result->m_source = source;
    result->m_sourceURL = sourceURL;
    result->m_cachePath = cachePath;
    [result readCache];
    return result;
}

+ (instancetype)scriptOfType:(JSScriptType)type memoryMappedFromASCIIFile:(NSURL *)filePath withSourceURL:(NSURL *)sourceURL andBytecodeCache:(NSURL *)cachePath inVirtualMachine:(JSVirtualMachine *)vm error:(out NSError **)error
{
    if (!validateBytecodeCachePath(cachePath, error))
        return nil;

    URL filePathURL([filePath absoluteURL]);
    if (!filePathURL.isLocalFile())
        return createError([NSString stringWithFormat:@"File path %@ is not a local file", static_cast<NSString *>(filePathURL)], error);

    bool success = false;
    String systemPath = filePathURL.fileSystemPath();
    FileSystem::MappedFileData fileData(systemPath, success);
    if (!success)
        return createError([NSString stringWithFormat:@"File at path %@ could not be mapped.", static_cast<NSString *>(systemPath)], error);

    if (!charactersAreAllASCII(reinterpret_cast<const LChar*>(fileData.data()), fileData.size()))
        return createError([NSString stringWithFormat:@"Not all characters in file at %@ are ASCII.", static_cast<NSString *>(systemPath)], error);

    JSScript *result = [[[JSScript alloc] init] autorelease];
    result->m_virtualMachine = vm;
    result->m_type = type;
    result->m_source = String(StringImpl::createWithoutCopying(bitwise_cast<const LChar*>(fileData.data()), fileData.size()));
    result->m_mappedSource = WTFMove(fileData);
    result->m_sourceURL = sourceURL;
    result->m_cachePath = cachePath;
    [result readCache];
    return result;
}

- (void)readCache
{
    if (!m_cachePath)
        return;

    int fd = open([m_cachePath path].UTF8String, O_RDONLY | O_EXLOCK | O_NONBLOCK, 0666);
    if (fd == -1)
        return;
    auto closeFD = makeScopeExit([&] {
        close(fd);
    });

    struct stat sb;
    int res = fstat(fd, &sb);
    size_t size = static_cast<size_t>(sb.st_size);
    if (res || !size)
        return;

    void* buffer = mmap(nullptr, size, PROT_READ, MAP_PRIVATE, fd, 0);

    Ref<JSC::CachedBytecode> cachedBytecode = JSC::CachedBytecode::create(buffer, size);

    JSC::VM& vm = m_virtualMachine.vm;
    JSC::SourceCode sourceCode = [self sourceCode];
    JSC::SourceCodeKey key = m_type == kJSScriptTypeProgram ? sourceCodeKeyForSerializedProgram(vm, sourceCode) : sourceCodeKeyForSerializedModule(vm, sourceCode);
    if (isCachedBytecodeStillValid(vm, cachedBytecode.copyRef(), key, m_type == kJSScriptTypeProgram ? JSC::SourceCodeType::ProgramType : JSC::SourceCodeType::ModuleType))
        m_cachedBytecode = WTFMove(cachedBytecode);
    else
        ftruncate(fd, 0);
}

- (BOOL)cacheBytecodeWithError:(NSError **)error
{
    String errorString { };
    [self writeCache:errorString];
    if (!errorString.isNull()) {
        createError(errorString, error);
        return NO;
    }

    return YES;
}

- (BOOL)isUsingBytecodeCache
{
    return !!m_cachedBytecode->size();
}

- (NSURL *)sourceURL
{
    return m_sourceURL.get();
}

- (JSScriptType)type
{
    return m_type;
}

@end

@implementation JSScript(Internal)

- (instancetype)init
{
    self = [super init];
    if (!self)
        return nil;

    self->m_cachedBytecode = JSC::CachedBytecode::create();

    return self;
}

- (unsigned)hash
{
    return m_source.hash();
}

- (const String&)source
{
    return m_source;
}

- (RefPtr<JSC::CachedBytecode>)cachedBytecode
{
    return m_cachedBytecode;
}

- (JSC::SourceCode)sourceCode
{
    JSC::VM& vm = m_virtualMachine.vm;
    JSC::JSLockHolder locker(vm);

    TextPosition startPosition { };
    String url = String { [[self sourceURL] absoluteString] };
    auto type = m_type == kJSScriptTypeModule ? JSC::SourceProviderSourceType::Module : JSC::SourceProviderSourceType::Program;
    Ref<JSScriptSourceProvider> sourceProvider = JSScriptSourceProvider::create(self, JSC::SourceOrigin(url), URL({ }, url), startPosition, type);
    JSC::SourceCode sourceCode(WTFMove(sourceProvider), startPosition.m_line.oneBasedInt(), startPosition.m_column.oneBasedInt());
    return sourceCode;
}

- (JSC::JSSourceCode*)jsSourceCode
{
    JSC::VM& vm = m_virtualMachine.vm;
    JSC::JSLockHolder locker(vm);
    JSC::JSSourceCode* jsSourceCode = JSC::JSSourceCode::create(vm, [self sourceCode]);
    return jsSourceCode;
}

- (BOOL)writeCache:(String&)error
{
    if (self.isUsingBytecodeCache) {
        error = "Cache for JSScript is already non-empty. Can not override it."_s;
        return NO;
    }

    if (!m_cachePath) {
        error = "No cache path was provided during construction of this JSScript."_s;
        return NO;
    }

    int fd = open([m_cachePath path].UTF8String, O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK, 0666);
    if (fd == -1) {
        error = makeString("Could not open or lock the bytecode cache file. It's likely another VM or process is already using it. Error: ", strerror(errno));
        return NO;
    }
    auto closeFD = makeScopeExit([&] {
        close(fd);
    });

    JSC::ParserError parserError;
    JSC::SourceCode sourceCode = [self sourceCode];
    switch (m_type) {
    case kJSScriptTypeModule:
        m_cachedBytecode = JSC::generateModuleBytecode(m_virtualMachine.vm, sourceCode, parserError);
        break;
    case kJSScriptTypeProgram:
        m_cachedBytecode = JSC::generateProgramBytecode(m_virtualMachine.vm, sourceCode, parserError);
        break;
    }

    if (parserError.isValid()) {
        m_cachedBytecode = JSC::CachedBytecode::create();
        error = makeString("Unable to generate bytecode for this JSScript because of a parser error: ", parserError.message());
        return NO;
    }

    ssize_t bytesWritten = write(fd, m_cachedBytecode->data(), m_cachedBytecode->size());
    if (bytesWritten == -1) {
        error = makeString("Could not write cache file to disk: ", strerror(errno));
        return NO;
    }

    if (static_cast<size_t>(bytesWritten) != m_cachedBytecode->size()) {
        ftruncate(fd, 0);
        error = makeString("Could not write the full cache file to disk. Only wrote ", String::number(bytesWritten), " of the expected ", String::number(m_cachedBytecode->size()), " bytes.");
        return NO;
    }

    return YES;
}

@end

#endif
