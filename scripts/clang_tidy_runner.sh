#!/bin/sh
# SPDX-FileCopyrightText: 2025 Kiril V. Strezikozin, Zurab Kvachadze
#
# SPDX-License-Identifier: Apache-2.0
#
# This is a shell script to run clang-tidy on project's source files.
# Run with --help to get usage information.

clang_tidy_exe="clang-tidy"

exclude_path=""
build_path="build"
re_pattern=""
re_escape=false
parallel=false
verbose=false
verbose_nn=10 # Internal.
clang_tidy_args=""

compiler="gcc"
compile_commands_filename="compile_commands.json"

dump_config() {
    cat <<__EOF__ >"$1"
#!/bin/sh
clang_tidy_exe=${clang_tidy_exe}

exclude_path=${exclude_path}
build_path=${build_path}
re_pattern=${re_pattern}
re_escape=${re_escape}
parallel=${parallel}
verbose=${verbose}
verbose_nn=${verbose_nn} # Has effect in verbose mode only.
clang_tidy_args=${clang_tidy_args}

compiler=${compiler}
compile_commands_filename=${compile_commands_filename}
__EOF__
}

print_usage() {
    cat <<__EOF__
Usage: clang_tidy_runner [-h | --help] [--verbose] [-c | --config <path>]
                         [-e | --excludes <path>] [-b | --build <path>]
                         [-r | --re <pattern>] [-q | --re-escape]
                         [-p | --parallel] [--dump-config <path>] [-- arg...]

Configurable wrapper to execute clang-tidy on project's source files.
Use to diagnose style violations and error-prone code through static analysis.

The following options are available to adjust the runner behavior:
  -c, --config <path>    Path to the configuration file.
  -e, --exclude <path>   Path to the file with directory/file paths to exclude
                         from checks, separated by newlines. Excluded directory
                         paths must end with *.
  -b, --build <path>     A path to the directory with compilation database.
  -r, --re <pattern>     A regex pattern to filter/select files to check.
                         If --build is specified, it is applied to the
                         file-paths parsed from the compilation database.
                         Otherwise, it is applied to the files in the current
                         directory.
  -q,  --re-escape       Escape non-printable characters in --re.
  -p,  --parallel        Run checks in parallel, sequentially otherwise.
  --dump-config <path>   Dump set configuration options to the given file path.
  --verbose              Run in verbose mode.
  -h,  --help            Print this help message again.

Arguments after -- are passed to the clang-tidy executable.

A configuration file provided with --config <path> is a shell script that can
be used to set runner options otherwise available as named arguments listed
above. Any command line option following --config overwrites its value from the
sourced configuration file if present. Similarly, --config overwrites option
values provided before it on the command line.

Use --dump_config to dump all default options set for the runner and values of
those set on the command line preceding --dump_config to the specified file.
Use this as a starting point to see all available options that can be set via a
configuration file. Options like the default compiler or clang-tidy executable
can only be set via a configuration file.
__EOF__
}

echostatus() { printf "%b\n" "$@" | sed "s/^/STATUS: /"; }
echoerr() { printf "\033[0;31m%s\033[0m\n" "Error: $*" 1>&2; }

check_arg_value() {
    if [ "$2" -lt 2 ]; then
        echoerr "Option $1 requires a value"
        exit 1
    fi
}

countlines() {
    if [ -n "$1" ]; then
        printf "%s\n" "$1" | wc -l
    else
        printf "0"
    fi
}

# Parse command arguments.
while [ "$#" -gt 0 ]; do
    case "$1" in
    -h | --help)
        print_usage
        exit 0
        ;;
    -e | --exclude)
        check_arg_value "$1" "$#"
        exclude_path="$2"
        shift # Remove the value arg from processing.
        ;;
    -b | --build)
        check_arg_value "$1" "$#"
        build_path="$2"
        shift # Remove the value arg from processing.
        ;;
    -r | --re)
        check_arg_value "$1" "$#"
        re_pattern="$2"
        shift # Remove the value arg from processing.
        ;;
    -q | --re-escape)
        re_escape=true
        ;;
    -p | --parallel)
        parallel=true
        ;;
    --verbose)
        verbose=true
        ;;
    --nn) # Internal.
        check_arg_value "$1" "$#"
        verbose_nn="$2"
        shift # Remove the value arg from processing.
        ;;
    -c | --config)
        check_arg_value "$1" "$#"
        # shellcheck disable=SC1090
        . "$2" # Source the provided config file.
        shift  # Remove the value arg from processing.
        ;;
    --dump-config)
        check_arg_value "$1" "$#"
        dump_config "$2"
        exit 0
        ;;
    --)
        shift # Remove the arg from processing.
        clang_tidy_args="$*"
        break
        ;;
    *)
        echoerr "Unknown option: $1"
        exit 1
        ;;
    esac
    shift # Remove the arg from processing.
done

if [ "${verbose}" = true ]; then
    echostatus "Command line argument parsing: done"
fi

# Print option values.
if [ "${verbose}" = true ]; then
    echostatus "\
Begin option values
-e | --exclude   = ${exclude_path}
-b | --build     = ${build_path}
-r | --re        = ${re_pattern}
-q | --re-escape = ${re_escape}
-p | --parallel  = ${parallel}
   | --verbose   = ${verbose}
   | --nn        = ${verbose_nn}
End option values"
fi

# Escape non-printable characters in ${re_pattern}.
if [ "${re_escape}" = true ] && [ -n "${re_pattern}" ]; then
    # This command will fail in POSIX shells like sh or dash, where `%q` is
    # undefined. There is not a really good and easy way to escape all
    # non-printable characters in a string. See the SC3050 warning in
    # Shellcheck Wiki for details.
    # shellcheck disable=SC3050
    re_pattern="$(printf '%q' "${re_pattern}")"
    echostatus "Regexp after escaping non-printable characters: ${re_pattern}"
fi

# Check if clang-tidy executable is available.
if ! command -v "${clang_tidy_exe}" >/dev/null; then
    echoerr "${clang_tidy_exe} command not found"
    exit 1
fi

# Check if compiler executable is available.
if ! command -v "${compiler}" >/dev/null; then
    echoerr "${compiler} command not found"
    exit 1
fi

# Parse compiler include paths. This involves filtering the lines from compiler
# information that start with a space. For arm-none-eabi-gcc these lines are
# appended to clang-tidy extra args which it does not do by default.
compiler_include_paths="$(echo | "${compiler}" -E -Wp,-v - 2>&1 | sed -n '/^ / s/^ *//p')"

# Print compiler include paths.
if [ "${verbose}" = true ]; then
    echostatus "Begin compiler include paths"
    if [ -n "${compiler_include_paths}" ]; then
        echostatus "${compiler_include_paths}"
    fi
    echostatus "End compiler include paths"
fi

source_files=""
if [ -n "${build_path}" ]; then
    # Build path is set.
    # Use the compile commands file to get the list of source files,
    # filter them with ${re_pattern}.

    if [ "${verbose}" = true ]; then
        echostatus "Build path: $(realpath "${build_path}")"
    fi

    if [ ! -d "$build_path" ]; then
        echoerr "Build directory path does does not exist"
        exit 1
    fi

    # Check if compile commands file exists.
    filepath="${build_path}/${compile_commands_filename}"

    if [ ! -f "${filepath}" ]; then
        echoerr "${filepath} file does not exist"
        exit 1
    fi

    # JSON entry name to select from compile commands file.
    entry="\"file\":"

    if [ "${verbose}" = true ]; then
        echostatus "\
Using compile commands file: ${filepath}
Using compile commands entry: ${entry}"
    fi

    # This command filters lines with ${entry} in the compile commands file,
    # removes any leading white-space + ${entry} + any trailing white-space
    # from these lines, and removes the trailing `",` as well. If ${re_pattern}
    # is not empty, it also used to filter the lines.
    #
    # ${re_pattern} is a regexp or a sed-compatible syntax. For example, to
    # exclude source files the paths of which contain "pico-sdk", the following
    # script invocation is valid:
    #   $ clang_tidy_runner -b build -r "pico-sdk|b; \|."
    # Or to only collect source files from compile commands file that are
    # within the current directory:
    #   $ clang_tidy_runner -b build -r "$(pwd)"
	source_files="$(sed -n "/${entry}/ { s/^ *${entry} *\"//; s/\",$//; p }" "${filepath}" | grep "${re_pattern}")"
    # shellcheck disable=SC2181
    if [ "$?" -ne 0 ]; then
        echoerr "Command exited with an error"
        exit 1
    fi
else
    # Build path is not set.
    # Filter files in the current directory using ${re_pattern}.

    if [ "${verbose}" = true ]; then
        echostatus "Build path is empty"
    fi

    # This command lists files in the current directory and filters them with
    # ${re_pattern} which is is a regexp or a sed-compatible syntax. For
    # example, to collect source files with .c or .h extensions but not .pio.h,
    # that are not in build or .* directories, run the script like so:
    #   $ clang_tidy_runner -r "\.c$\|\.h$/\!b; /^\.\/build\|^\.\/\.\|.pio.h$/b; /."
    source_files="$(find . -type f | sed -n "/${re_pattern:-.}/p" | xargs realpath)"
    # shellcheck disable=SC2181
    if [ "$?" -ne 0 ]; then
        echoerr "Command exited with an error"
        exit 1
    fi
fi

# Print parsed and filtered source files.
if [ "${verbose}" = true ]; then
    n="$(countlines "${source_files}")"
    echostatus "Begin source files (${verbose_nn} max, ${n} total)"
    if [ -n "${source_files}" ]; then
        echostatus "${source_files}" | head -n"${verbose_nn}"
    fi
    echostatus "End source files"
fi

# Filter source files with expressions from ${exclude_path} if it is set.
if [ -n "${exclude_path}" ]; then
    if [ ! -f "${exclude_path}" ]; then
        echoerr "${exclude_path} file does not exist"
        exit 1
    fi

    # The `sed` command below prepends `^` to all expressions and
    # appends `$` to non-directory expressions from ${exclude_path}.
    # The `grep` command filters the source files.
    tmp="$(mktemp)"
    sed "s/^/^/; /*$/b; s/$/$/" "${exclude_path}" >"${tmp}"
    source_files="$(printf "%s" "${source_files}" | grep -vf "${tmp}")"
    rm "${tmp}"

    # Print source files filtered with expressions from ${exclude_path}.
    if [ "${verbose}" = true ]; then
        n="$(countlines "${source_files}")"
        echostatus "Begin source files after excludes (${verbose_nn} max, ${n} total)"
        if [ -n "${source_files}" ]; then
            echostatus "${source_files}" | head -n"${verbose_nn}"
        fi
        echostatus "End source files after excludes"
    fi
fi

n="$(countlines "${source_files}")"
echo "Number of files to check: ${n}"

if [ "${verbose}" = true ]; then
    echostatus "Begin clang-tidy"
    if [ "${n}" -ne 0 ]; then
        echostatus "Using clang-tidy command: " | tr -d "\n"
    fi
fi

# Run clang-tidy through `xargs` on every source file.
tmp="$(mktemp)"
# Avoid quoting conditions and ${clang_tidy_args}
# below, argument splitting is desired.
# shellcheck disable=SC2086,SC2046
printf "%s" "${source_files}" |
    xargs \
        --delimiter "\n" \
        --no-run-if-empty \
        $(if [ "${verbose}" = true ]; then echo "--verbose"; fi) \
        $(if [ "${parallel}" = true ]; then echo "-P0"; fi) \
        "${clang_tidy_exe}" \
        $(if [ -n "${build_path}" ]; then echo "-p ${build_path}"; fi) \
        $(printf "%s" "${compiler_include_paths}" | sed "s/^/--extra-arg=-I/") \
        ${clang_tidy_args} |
    tee "${tmp}"

# Count errors to determine script exit code.
error_count="$(grep -e '-warnings-as-errors' --count "${tmp}")"
rm "${tmp}"

if [ "${verbose}" = true ]; then echostatus "End clang-tidy"; fi

if [ "${error_count}" -gt 0 ]; then
    echoerr "found ${error_count} errors"
    exit 1
fi

if [ "${verbose}" = true ]; then echostatus "Done"; fi

printf "\033[0;32mDone.\033[0m\n"
exit 0
