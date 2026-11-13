// lidguard-helper — tiny native helper used by lidguard.sh
//   lidguard-helper thermal   → prints macOS heat level: 0 normal, 1 fair, 2 serious, 3 critical
//   lidguard-helper lock      → locks the screen now (like Apple menu → Lock Screen); doesn't sleep
import Foundation

switch CommandLine.arguments.dropFirst().first {
case "thermal":
  print(ProcessInfo.processInfo.thermalState.rawValue)
case "lock":
  guard let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
        let sym = dlsym(h, "SACLockScreenImmediate") else { exit(1) }
  typealias Fn = @convention(c) () -> Void
  unsafeBitCast(sym, to: Fn.self)()
default:
  FileHandle.standardError.write("usage: lidguard-helper thermal|lock\n".data(using: .utf8)!)
  exit(2)
}
