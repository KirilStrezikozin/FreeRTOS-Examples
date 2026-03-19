#!/bin/sh
# SPDX-FileCopyrightText: 2025 Kiril V. Strezikozin, Zurab Kvachadze
#
# SPDX-License-Identifier: Apache-2.0
#
# This is a code format shell script that runs the `clang-format` command on
# arguments to format C/C++ code, common Nix formatters for *.nix code, and
# `shellcheck` for shell scripts.
#
# The contents of this file are embedded into the formatter script source for
# the `nix fmt` command. Users are allowed to execute this script directly.
# Run with --help to get usage information.

# Glob pattern options for the `fd` command with files/directories to exclude.
# `!(*)` would mean to not exclude anything.
glob_excludes=""

targets=""

clang_format_args=""
nix_format_on=false
c_cxx_format_on=false
shell_format_on=false

exit_code=0

print_usage() {
    cat <<__EOF__
Usage: format [<file> | <directory>]...
              [-E <exclude_glob>]...
              [--[nix|c-cxx|shell]-format]
              -- [<clang-format-option>]...

Formats C/C++, Nix, and shell script code files. Use to transform files to an
established styling convention. If no <file> or <directory> positional argument
is given, a default directory "." is used.

The following options are available to adjust the formatting behavior:
  -E <exclude_glob>            A glob pattern of files/directorires to exclude
                               from checks. If a file argument is given
                               directly, it is checked regardless of this
                               option.
  --[nix|c-cxx|shell]-format]  Perform formatting for Nix, C/C++, or shell
                               script files only. Combination of multiple such
                               options is allowed.

Invalid options supplied will be interpreted as a <file> or <directory>
positional arguments.

"--" indicates the start of the arguments to pass to the clang-format command,
such as --dry-run to avoid formatting the files in place:

  ./format . -- --dry-run

Examples:

  1. Format all C/C++, Nix, and shell script files, but ignore everything in
     the build directory:

     ./format . -E build

  2. Show formatting issues in C/C++ files only without editing them:
     the build directory:

     ./format . --c_cxx_format -E build -- --dry-run

  3. Skip formatting Nix code files. Useful for non-Nix users who may not have
     dependencies for formatting Nix code installed:

     ./format --c_cxx_format --shell-format

File searching inside directory arguments relies on the fd command.
As a result, .gitignore is automatically respected.

See also:
  - ClangFormat documentation for the usage of the .clang-format-ignore file.
  - Shellcheck documentation for guides to ignoring shellcheck errors.
__EOF__
}

echoerr() { printf "%b\n" "\033[0;31mError: $*\033[0m" 1>&2; }

check_arg_value() {
    if [ "$2" -lt 2 ]; then
        echoerr "Option $1 requires a value"
        exit 1
    fi
}

nix_format() {
    if [ "${nix_format_on}" = false ]; then return; fi

    if [ "$#" -eq 0 ]; then
        # No arguments, assume ".".
        # shellcheck disable=SC2086
        fd '.*\.nix' . ${glob_excludes} -x statix fix -- {} \;
        # shellcheck disable=SC2086
        fd '.*\.nix' . ${glob_excludes} -X deadnix -e -- {} \; -X alejandra {} \;
    elif [ -d "$1" ]; then
        # Directory argument, search for *.nix files.
        # shellcheck disable=SC2086
        fd '.*\.nix' "$1" ${glob_excludes} -i -x statix fix -- {} \;
        # shellcheck disable=SC2086
        fd '.*\.nix' "$1" ${glob_excludes} -i -X deadnix -e -- {} \; -X alejandra {} \;
    else
        # File argument, format directly.
        statix fix -- "$1"
        deadnix -e "$1"
        alejandra "$1"
    fi

    ret="$?"
    if [ "${exit_code}" -eq 0 ] && [ "${ret}" -ne 0 ]; then exit_code=1; fi
}

c_cxx_format() {
    if [ "${c_cxx_format_on}" = false ]; then return; fi

    if [ "$#" -eq 0 ]; then
        # No arguments, assume ".".
        # shellcheck disable=SC2086
        fd '\.c$|\.cpp$' . ${glob_excludes} -X clang-format --verbose -i ${clang_format_args}
    elif [ -d "$1" ]; then
        # Directory argument, search for *.nix files.
        # shellcheck disable=SC2086
        fd '\.c$|\.cpp$' "$1" ${glob_excludes} -X clang-format --verbose -i ${clang_format_args}
    else
        # File argument, format directly.
        # shellcheck disable=SC2086
        clang-format --verbose -i ${clang_format_args}
    fi

    ret="$?"
    if [ "${exit_code}" -eq 0 ] && [ "${ret}" -ne 0 ]; then exit_code=1; fi
}

shell_format() {
    if [ "${shell_format_on}" = false ]; then return; fi

    # LICENSE file has not extension, explicitly exclude
    # it to avoid it being detected as a shell script.
    local_glob_excludes="${glob_excludes} -E LICENSE"

    if [ "$#" -eq 0 ]; then
        # No arguments, assume ".".
        # shellcheck disable=SC2086
        fd '^[^.]*$' . ${local_glob_excludes} -t file -x shellcheck --color=always
    elif [ -d "$1" ]; then
        # Directory argument, search for *.nix files.
        # shellcheck disable=SC2086
        fd '^[^.]*$' "$1" ${local_glob_excludes} -t file -x shellcheck --color=always
    else
        # File argument, format directly.
        shellcheck --color=always "$1"
    fi

    ret="$?"
    if [ "${exit_code}" -eq 0 ] && [ "${ret}" -ne 0 ]; then exit_code=1; fi
}

all_format_on=true
while [ "$#" -gt 0 ]; do
    case "$1" in
    -h | --help)
        print_usage
        exit 0
        ;;
    -E)
        check_arg_value "$1" "$#"
        glob_excludes="${glob_excludes} -E $2"
        shift # Remove the value arg from processing.
        ;;
    --nix-format)
        all_format_on=false
        nix_format_on=true
        ;;
    --c-cxx-format)
        all_format_on=false
        c_cxx_format_on=true
        ;;
    --shell-format)
        all_format_on=false
        shell_format_on=true
        ;;
    --)
        shift # Remove the value arg from processing.
        clang_format_args="$*"
        break
        ;;
    *)
        targets="${targets} $1"
        ;;
    esac
    shift
done

if [ "${all_format_on}" = true ]; then
    nix_format_on=true
    c_cxx_format_on=true
    shell_format_on=true
fi

if [ -z "${targets}" ]; then targets="."; fi

oldIFS="${IFS}"
IFS=" "
for i in ${targets}; do
    if [ "${i##*.}" = "$i" ]; then
        # No file extension, may be a shell script.
        shell_format "$i"
        continue
    fi
    case "${i##*.}" in
    "nix")
        nix_format "$i"
        ;;
    "cpp" | "c")
        c_cxx_format "$i"
        ;;
    *)
        nix_format "$i"
        c_cxx_format "$i"
        shell_format "$i"
        ;;
    esac
done
IFS="${oldIFS}"

exit "${exit_code}"
