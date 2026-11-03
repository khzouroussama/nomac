import Foundation
import NomacCore

/// The programs script phases start off macOS, run as macOS's `/bin/sh` would run them
/// (docs/adr/0180-scripts-run-by-path.md).
///
/// ADR 0103 gives each phase's own script nomac's shell, but the kernel runs the scripts a phase
/// starts with the interpreter their `#!` line names: CocoaPods' `[CP]` phases run their
/// `#!/bin/sh` scripts (`*-xcframeworks.sh`, `*-frameworks.sh`, `*-resources.sh`), which use
/// `set -o pipefail`, arrays and `[[ ]]`, and Ubuntu's `/bin/sh` is dash. nomac's shell preloads
/// this library into the processes of the phase; it starts nomac's shell instead of a program
/// that is `/bin/sh`, by that path or found as `sh` on `PATH`, and instead of the interpreter of a
/// script whose `#!` line names `/bin/sh`, as the kernel would pass it the script. A program started
/// by a macOS path of a tool the developer directory provides, which the machine lacks, runs the
/// developer directory's (CocoaPods' frameworks script signs with `/usr/bin/codesign` in an install
/// build; ``toolPaths``). The machine's `cp` given BSD's `-X` runs without it, which GNU cp
/// refuses and does not need (React Native 0.81's codegen phase, docs/adr/0183).
public enum ExecInterposer {
    /// Where the library is, in the developer directory, next to nomac's shell.
    public static let relativePath = "usr/libexec/nomac/libnomac-exec.so"

    /// macOS's paths of the tools nomac installs, and where they are in the developer directory
    /// (``LinuxToolchain/nomacTools``).
    static let toolPaths = [
        ("/usr/bin/codesign", "Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign"),
        ("/usr/bin/ditto", "Toolchains/XcodeDefault.xctoolchain/usr/bin/ditto"),
        ("/usr/bin/xcodebuild", "usr/bin/xcodebuild"),
        ("/usr/bin/xcrun", "usr/bin/xcrun"),
        ("/usr/libexec/PlistBuddy", "usr/libexec/PlistBuddy"),
    ]

    static var source: String {
        let table = toolPaths.map { "    {\"\($0.0)\", \"\($0.1)\"},\n" }.joined()
        return template.replacingOccurrences(of: "@TOOLS@\n", with: table)
    }

    private static let template = #"""
        /* Written by 'nomac toolchain install' (docs/adr/0180-scripts-run-by-path.md). */
        #define _GNU_SOURCE
        #include <dlfcn.h>
        #include <fcntl.h>
        #include <limits.h>
        #include <spawn.h>
        #include <string.h>
        #include <sys/stat.h>
        #include <unistd.h>

        extern char **environ;

        typedef int (*execve_t)(const char *, char *const[], char *const[]);
        typedef int (*execvpe_t)(const char *, char *const[], char *const[]);
        typedef int (*spawn_t)(pid_t *, const char *, const posix_spawn_file_actions_t *, const posix_spawnattr_t *,
                               char *const[], char *const[]);

        static execve_t real_execve;
        static execvpe_t real_execvpe;
        static spawn_t real_posix_spawn, real_posix_spawnp;
        static char shell[PATH_MAX];

        /* macOS's paths of tools the developer directory provides, and where they are in it. */
        static const char *const tools[][2] = {
        @TOOLS@
        };
        #define TOOL_COUNT (sizeof tools / sizeof tools[0])
        static char tool_paths[TOOL_COUNT][PATH_MAX];

        /* Resolved before any fork, so that a child never calls dlsym. */
        __attribute__((constructor)) static void setup(void) {
            real_execve = (execve_t)dlsym(RTLD_NEXT, "execve");
            real_execvpe = (execvpe_t)dlsym(RTLD_NEXT, "execvpe");
            real_posix_spawn = (spawn_t)dlsym(RTLD_NEXT, "posix_spawn");
            real_posix_spawnp = (spawn_t)dlsym(RTLD_NEXT, "posix_spawnp");
            Dl_info info;
            const char *slash;
            if (dladdr((void *)setup, &info) && info.dli_fname && (slash = strrchr(info.dli_fname, '/'))
                && (size_t)(slash - info.dli_fname) + sizeof "/sh" <= sizeof shell) {
                memcpy(shell, info.dli_fname, (size_t)(slash - info.dli_fname));
                strcpy(shell + (slash - info.dli_fname), "/sh");
            }
            const char *suffix = "/usr/libexec/nomac/libnomac-exec.so";
            size_t length = info.dli_fname ? strlen(info.dli_fname) : 0, prefix = length - strlen(suffix);
            if (length > strlen(suffix) && strcmp(info.dli_fname + prefix, suffix) == 0)
                for (size_t i = 0; i < TOOL_COUNT; i++)
                    if (prefix + 1 + strlen(tools[i][1]) < PATH_MAX) {
                        memcpy(tool_paths[i], info.dli_fname, prefix);
                        tool_paths[i][prefix] = '/';
                        strcpy(tool_paths[i] + prefix + 1, tools[i][1]);
                    }
        }

        static int same_file(const char *a, const char *b) {
            struct stat x, y;
            return stat(a, &x) == 0 && stat(b, &y) == 0 && x.st_dev == y.st_dev && x.st_ino == y.st_ino;
        }

        /* The file a PATH search finds for `file`, in `found`; `file` itself when it has a slash. */
        static const char *search(const char *file, char *found, size_t size) {
            if (strchr(file, '/'))
                return file;
            const char *path = NULL;
            for (char **variable = environ; variable && *variable; variable++)
                if (strncmp(*variable, "PATH=", 5) == 0)
                    path = *variable + 5;
            if (!path)
                path = "/bin:/usr/bin";
            size_t length = strlen(file);
            for (const char *start = path;; ) {
                const char *end = strchrnul(start, ':');
                size_t prefix = (size_t)(end - start);
                if (prefix == 0) {
                    start = ".";
                    prefix = 1;
                }
                if (prefix + 1 + length + 1 <= size) {
                    memcpy(found, start, prefix);
                    found[prefix] = '/';
                    memcpy(found + prefix + 1, file, length + 1);
                    if (access(found, X_OK) == 0)
                        return found;
                }
                if (!*end)
                    return NULL;
                start = end + 1;
            }
        }

        /* The machine's cp with BSD's -X (no extended attributes) left out of each option cluster, which
           GNU cp refuses ("invalid option -- 'X'") and whose copy GNU cp makes without it; under -a,
           which keeps them in GNU cp, with --no-preserve=xattr. NULL when no cluster has an X. */
        static const char *bsd_cp(const char *path, char *const argv[], char **args, char *line, size_t size) {
            size_t n = 0, used = 0;
            int dropped = 0, archive = 0, options = 1;
            args[n++] = argv[0];
            for (size_t i = 1; argv[i]; i++) {
                const char *argument = argv[i];
                int cluster = options && argument[0] == '-' && argument[1] && argument[1] != '-';
                if (options && strcmp(argument, "--") == 0)
                    options = 0;
                if (cluster && strchr(argument, 'a'))
                    archive = 1;
                if (!cluster || !strchr(argument, 'X')) {
                    args[n++] = (char *)argument;
                    continue;
                }
                dropped = 1;
                size_t length = strlen(argument);
                if (used + length + 1 > size)
                    return NULL;
                char *kept = line + used;
                size_t k = 0;
                for (size_t j = 0; j < length; j++)
                    if (argument[j] != 'X')
                        kept[k++] = argument[j];
                kept[k] = '\0';
                if (k > 1) {
                    args[n++] = kept;
                    used += k + 1;
                }
            }
            if (!dropped)
                return NULL;
            if (archive) {
                memmove(args + 2, args + 1, (n - 1) * sizeof *args);
                args[1] = (char *)"--no-preserve=xattr";
                n++;
            }
            args[n] = NULL;
            return path;
        }

        /* nomac's shell and its arguments in `args` (room for argc + 3), when `path` is /bin/sh or a
           script whose #! line names /bin/sh; the developer directory's tool, with the same
           arguments, for a macOS path of one that the machine lacks; the machine's cp without BSD's -X
           (bsd_cp); NULL to run `path` as asked. */
        static const char *rewrite(const char *path, char *const argv[], char **args, char *line, size_t size) {
            size_t n = 0;
            for (size_t i = 0; path && i < TOOL_COUNT; i++)
                if (tool_paths[i][0] && strcmp(path, tools[i][0]) == 0 && access(path, X_OK) != 0 && access(tool_paths[i], X_OK) == 0) {
                    for (; argv && argv[n]; n++)
                        args[n] = argv[n];
                    args[n] = NULL;
                    return tool_paths[i];
                }
            if (path && argv && same_file(path, "/bin/cp"))
                return bsd_cp(path, argv, args, line, size);
            if (!shell[0] || !path || access(shell, X_OK) != 0)
                return NULL;
            const char *name = strrchr(path, '/');
            name = name ? name + 1 : path;
            if (strcmp(name, "sh") == 0 && same_file(path, "/bin/sh")) {
                for (; argv && argv[n]; n++)
                    args[n] = argv[n];
                args[n] = NULL;
                return shell;
            }
            int fd = open(path, O_RDONLY | O_CLOEXEC);
            if (fd < 0)
                return NULL;
            ssize_t count = read(fd, line, size - 1);
            close(fd);
            if (count < 9 || line[0] != '#' || line[1] != '!')
                return NULL;
            line[count] = '\0';
            line[strcspn(line, "\n")] = '\0';
            char *interpreter = line + 2 + strspn(line + 2, " \t");
            char *rest = interpreter + strcspn(interpreter, " \t");
            if (rest - interpreter != 7 || strncmp(interpreter, "/bin/sh", 7) != 0)
                return NULL;
            rest += strspn(rest, " \t");
            for (char *last = rest + strlen(rest); last > rest && (last[-1] == ' ' || last[-1] == '\t'); last--)
                last[-1] = '\0';
            args[n++] = (char *)"/bin/sh";
            if (*rest)
                args[n++] = rest;
            args[n++] = (char *)path;
            for (size_t i = 1; argv && argv[0] && argv[i]; i++)
                args[n++] = argv[i];
            args[n] = NULL;
            return shell;
        }

        static size_t count(char *const argv[]) {
            size_t n = 0;
            while (argv && argv[n])
                n++;
            return n;
        }

        int execve(const char *path, char *const argv[], char *const envp[]) {
            char *args[count(argv) + 3], line[256];
            const char *program = rewrite(path, argv, args, line, sizeof line);
            return real_execve(program ? program : path, program ? args : argv, envp);
        }

        int execv(const char *path, char *const argv[]) {
            return execve(path, argv, environ);
        }

        int execvpe(const char *file, char *const argv[], char *const envp[]) {
            char *args[count(argv) + 3], line[256], found[PATH_MAX];
            const char *program = rewrite(search(file, found, sizeof found), argv, args, line, sizeof line);
            return program ? real_execve(program, args, envp) : real_execvpe(file, argv, envp);
        }

        int execvp(const char *file, char *const argv[]) {
            return execvpe(file, argv, environ);
        }

        int posix_spawn(pid_t *pid, const char *path, const posix_spawn_file_actions_t *actions,
                        const posix_spawnattr_t *attributes, char *const argv[], char *const envp[]) {
            char *args[count(argv) + 3], line[256];
            const char *program = rewrite(path, argv, args, line, sizeof line);
            return real_posix_spawn(pid, program ? program : path, actions, attributes, program ? args : argv, envp);
        }

        int posix_spawnp(pid_t *pid, const char *file, const posix_spawn_file_actions_t *actions,
                         const posix_spawnattr_t *attributes, char *const argv[], char *const envp[]) {
            char *args[count(argv) + 3], line[256], found[PATH_MAX];
            const char *program = rewrite(search(file, found, sizeof found), argv, args, line, sizeof line);
            return program ? real_posix_spawn(pid, program, actions, attributes, args, envp)
                           : real_posix_spawnp(pid, file, actions, attributes, argv, envp);
        }

        """#

    /// Compiles the library with `clang` into `developerDirectory`, next to nomac's shell; returns its path.
    @discardableResult
    public static func install(clang: String, developerDirectory: String) throws -> String {
        let destination = FileSystem.absolute(developerDirectory) + "/" + relativePath
        let sourcePath = NSTemporaryDirectory() + "/nomac-exec-\(UUID().uuidString).c"
        try FileSystem.write(Data(source.utf8), to: sourcePath)
        defer { try? FileManager.default.removeItem(atPath: sourcePath) }
        try FileManager.default.createDirectory(atPath: (destination as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let result = try Subprocess.run(clang, ["-shared", "-fPIC", "-O2", "-Wall", "-Werror", "-o", destination, sourcePath])
        guard result.exitStatus == 0 else {
            throw NomacError("could not compile the exec interposer: \(result.errorString)", path: clang)
        }
        return destination
    }
}
