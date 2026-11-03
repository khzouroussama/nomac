import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Names as `atos` prints them: Swift symbols in the Swift demangler's simplified form (the
/// toolchain's `libswiftDemangle`, `swift_demangle_getSimplifiedDemangledName`), C++ symbols
/// through `__cxa_demangle` (a block in a C++ function as `atos` words it), anything else as it
/// is (`symbolicate_experiments.py`).
public struct Demangler: Sendable {
    private typealias Simplified = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<CChar>?, Int) -> Int
    private typealias Itanium = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<CChar>?, UnsafeMutablePointer<Int>?, UnsafeMutablePointer<Int32>?) -> UnsafeMutablePointer<CChar>?
    private let simplified: Simplified?
    private let itanium: Itanium?

    /// The demangler of the toolchain at `toolchain` (its `usr`), else the one the system finds.
    public init(toolchain: String? = nil) {
        #if canImport(Darwin)
        let library = "libswiftDemangle.dylib"
        #else
        let library = "libswiftDemangle.so"
        #endif
        var handle: UnsafeMutableRawPointer?
        for path in [toolchain.map { $0 + "/lib/" + library }, library].compactMap({ $0 }) where handle == nil { handle = dlopen(path, RTLD_NOW) }
        simplified = handle.flatMap { dlsym($0, "swift_demangle_getSimplifiedDemangledName") }.map { unsafeBitCast($0, to: Simplified.self) }
        // LLVM's demangler, as Xcode's: libc++abi's where the system has it (Linux's libc++abi1),
        // else the process's (libstdc++'s on Linux, which words some names otherwise).
        var llvm: UnsafeMutableRawPointer?
        for name in ["libc++abi.so.1", "libc++abi.so"] where llvm == nil { llvm = dlopen(name, RTLD_NOW) }
        itanium = (llvm.flatMap { dlsym($0, "__cxa_demangle") } ?? dlsym(dlopen(nil, RTLD_NOW), "__cxa_demangle")).map { unsafeBitCast($0, to: Itanium.self) }
    }

    public var canDemangleSwift: Bool { simplified != nil }

    public func callAsFunction(_ name: String) -> String {
        if let simplified, ["$s", "_$s", "$S", "_$S", "_T0", "$e", "_$e"].contains(where: name.hasPrefix) {
            let mangled = name.hasPrefix("_$") ? String(name.dropFirst()) : name
            var buffer = [CChar](repeating: 0, count: 4096)
            let length = mangled.withCString { simplified($0, &buffer, buffer.count) }
            if length > 0 {
                if length >= buffer.count {
                    buffer = [CChar](repeating: 0, count: length + 1)
                    _ = mangled.withCString { simplified($0, &buffer, buffer.count) }
                }
                return String(cString: buffer)
            }
        }
        // A block in a C++ function: `___Z<function>_block_invoke`, with `_<n>` for later blocks.
        if name.hasPrefix("___Z"), let marker = name.range(of: "_block_invoke"),
           let function = itaniumName(String(name[name.index(name.startIndex, offsetBy: 2)..<marker.lowerBound])) {
            return "invocation function for block in " + function
        }
        return name.hasPrefix("_Z") ? itaniumName(name) ?? name : name
    }

    private func itaniumName(_ name: String) -> String? {
        guard let itanium else { return nil }
        var status: Int32 = 0
        guard let result = name.withCString({ itanium($0, nil, nil, &status) }), status == 0 else { return nil }
        defer { free(result) }
        return String(cString: result)
    }
}
