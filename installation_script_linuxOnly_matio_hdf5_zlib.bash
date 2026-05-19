#!/usr/bin/env bash
set -Eeuo pipefail

trap 'die "Command failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
START_DIR="${PWD}"

BASE_DIR="${SCRIPT_DIR}/geant4"
JOBS=""
DRY_RUN=false
CLEAN=false
UPDATE_SHELL_RC=true

# Known-compatible stack: current zlib/matio with the HDF5 1.14.x API line.
ZLIB_VERSION="1.3.2"
HDF5_VERSION="1.14.6"
MATIO_VERSION="1.5.30"

ZLIB_SOURCE_NAME="zlib-${ZLIB_VERSION}"
ZLIB_ARCHIVE="${ZLIB_SOURCE_NAME}.tar.gz"
ZLIB_URL="https://zlib.net/${ZLIB_ARCHIVE}"
ZLIB_SHA256="bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16"

HDF5_SOURCE_NAME="hdf5-${HDF5_VERSION}"
HDF5_ARCHIVE="${HDF5_SOURCE_NAME}.tar.gz"
HDF5_URL="https://github.com/HDFGroup/hdf5/releases/download/hdf5_${HDF5_VERSION}/${HDF5_ARCHIVE}"
HDF5_SHA256="e4defbac30f50d64e1556374aa49e574417c9e72c6b1de7a4ff88c4b1bea6e9b"

MATIO_SOURCE_NAME="matio-${MATIO_VERSION}"
MATIO_ARCHIVE="${MATIO_SOURCE_NAME}.tar.gz"
MATIO_URL="https://github.com/tbeu/matio/releases/download/v${MATIO_VERSION}/${MATIO_ARCHIVE}"
MATIO_SHA256="8bd3b9477042ecc00dd71c04762fa58468e14cccc32fd8c6826c2da1e8bc3107"

ZLIB_SOURCE_DIR=""
ZLIB_INSTALL_DIR=""
HDF5_SOURCE_DIR=""
HDF5_BUILD_DIR=""
HDF5_INSTALL_DIR=""
MATIO_SOURCE_DIR=""
MATIO_BUILD_DIR=""
MATIO_INSTALL_DIR=""
ENV_FILE=""

log() {
    printf '[matio-install] %s\n' "$*"
}

warn() {
    printf '[matio-install] warning: %s\n' "$*" >&2
}

die() {
    printf '[matio-install] error: %s\n' "$*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $0 [options]

Build and install a known-compatible zlib/HDF5/matio stack for MAT v7.3 output.

Options:
  --base-dir PATH         Build/install workspace. Default: ${SCRIPT_DIR}/geant4
  --jobs N               Number of parallel build jobs. Default: auto-detect.
  --clean                Remove previous generated zlib/HDF5/matio outputs first.
  --dry-run              Print configuration and planned actions without building.
  --no-update-shell-rc   Do not modify ~/.bashrc.
  -h, --help             Show this help message.
EOF
}

absolute_path() {
    local path="$1"

    if [[ "$path" == "/" ]]; then
        printf '/\n'
    elif [[ "$path" == /* ]]; then
        printf '%s\n' "${path%/}"
    else
        printf '%s/%s\n' "${START_DIR}" "${path%/}"
    fi
}

parse_args() {
    while (($#)); do
        case "$1" in
            --base-dir)
                [[ $# -ge 2 && -n "$2" ]] || die "--base-dir requires a path"
                BASE_DIR="$2"
                shift 2
                ;;
            --jobs)
                [[ $# -ge 2 && -n "$2" ]] || die "--jobs requires a positive integer"
                [[ "$2" =~ ^[1-9][0-9]*$ ]] || die "--jobs requires a positive integer"
                JOBS="$2"
                shift 2
                ;;
            --clean)
                CLEAN=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-update-shell-rc)
                UPDATE_SHELL_RC=false
                shift
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                die "Unknown option: $1"
                ;;
        esac
    done
}

run() {
    if [[ "$DRY_RUN" == true ]]; then
        printf '[matio-install] dry-run:'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

run_in_dir() {
    local dir="$1"
    shift

    if [[ "$DRY_RUN" == true ]]; then
        printf '[matio-install] dry-run: cd %q &&' "$dir"
        printf ' %q' "$@"
        printf '\n'
    else
        (cd "$dir" && "$@")
    fi
}

detect_jobs() {
    if [[ -n "$JOBS" ]]; then
        return
    fi

    if command -v nproc >/dev/null 2>&1; then
        JOBS="$(nproc)"
    elif [[ -r /proc/cpuinfo ]]; then
        JOBS="$(grep -c '^processor' /proc/cpuinfo || true)"
    fi

    if [[ -z "$JOBS" || ! "$JOBS" =~ ^[1-9][0-9]*$ ]]; then
        JOBS="1"
    fi
}

configure_paths() {
    BASE_DIR="$(absolute_path "$BASE_DIR")"
    [[ "$BASE_DIR" != "/" ]] || die "Refusing to use / as the base directory"

    ZLIB_SOURCE_DIR="${BASE_DIR}/source_${ZLIB_SOURCE_NAME}"
    ZLIB_INSTALL_DIR="${BASE_DIR}/install_zlib"

    HDF5_SOURCE_DIR="${BASE_DIR}/source_${HDF5_SOURCE_NAME}"
    HDF5_BUILD_DIR="${BASE_DIR}/build_hdf5_${HDF5_VERSION}"
    HDF5_INSTALL_DIR="${BASE_DIR}/install_hdf5"

    MATIO_SOURCE_DIR="${BASE_DIR}/source_${MATIO_SOURCE_NAME}"
    MATIO_BUILD_DIR="${BASE_DIR}/build_matio_${MATIO_VERSION}"
    MATIO_INSTALL_DIR="${BASE_DIR}/install_matio"

    ENV_FILE="${BASE_DIR}/matio_hdf5_zlib_env.sh"
}

print_configuration() {
    cat <<EOF
[matio-install] Configuration
  Base dir:      ${BASE_DIR}
  zlib:          ${ZLIB_VERSION}
  HDF5:          ${HDF5_VERSION}
  matio:         ${MATIO_VERSION}
  zlib install:  ${ZLIB_INSTALL_DIR}
  HDF5 install:  ${HDF5_INSTALL_DIR}
  matio install: ${MATIO_INSTALL_DIR}
  Env file:      ${ENV_FILE}
  Jobs:          ${JOBS}
  Clean first:   ${CLEAN}
  Update bashrc: ${UPDATE_SHELL_RC}
EOF
}

print_dry_run_plan() {
    cat <<EOF
[matio-install] Dry-run major actions
  1. Validate required build tools.
  2. Download zlib ${ZLIB_VERSION}, verify SHA256, build, and install it.
  3. Download HDF5 ${HDF5_VERSION}, verify SHA256, build it against local zlib, and install it.
  4. Download matio ${MATIO_VERSION}, verify SHA256, build it with MAT v7.3 support against local HDF5/zlib, and install it.
  5. Write environment file: ${ENV_FILE}
  6. Update ~/.bashrc: ${UPDATE_SHELL_RC}
EOF
}

ensure_inside_base() {
    local target="$1"

    case "$target" in
        "${BASE_DIR}/"*) ;;
        *) die "Refusing to remove path outside base directory: ${target}" ;;
    esac
}

remove_generated_path() {
    local target="$1"
    ensure_inside_base "$target"

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run: would remove ${target}"
        return
    fi

    if [[ -e "$target" || -L "$target" ]]; then
        rm -rf -- "$target"
    fi
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

check_prerequisites() {
    local command
    for command in wget tar gzip make gcc g++ gfortran sha256sum; do
        require_command "$command"
    done
}

prepare_base_dir() {
    run mkdir -p "$BASE_DIR"
}

clean_previous_outputs() {
    log "Cleaning previous zlib/HDF5/matio outputs."

    remove_generated_path "${BASE_DIR}/${ZLIB_ARCHIVE}"
    remove_generated_path "${BASE_DIR}/${HDF5_ARCHIVE}"
    remove_generated_path "${BASE_DIR}/${MATIO_ARCHIVE}"

    remove_generated_path "$ZLIB_SOURCE_DIR"
    remove_generated_path "$HDF5_SOURCE_DIR"
    remove_generated_path "$HDF5_BUILD_DIR"
    remove_generated_path "$MATIO_SOURCE_DIR"
    remove_generated_path "$MATIO_BUILD_DIR"

    remove_generated_path "$ZLIB_INSTALL_DIR"
    remove_generated_path "$HDF5_INSTALL_DIR"
    remove_generated_path "$MATIO_INSTALL_DIR"
    remove_generated_path "$ENV_FILE"

    # Legacy paths from the previous installer.
    remove_generated_path "${BASE_DIR}/zlib-1.2.11"
    remove_generated_path "${BASE_DIR}/zlib-1.2.11.tar.gz"
    remove_generated_path "${BASE_DIR}/hdf5-hdf5-1_10_1"
    remove_generated_path "${BASE_DIR}/hdf5-hdf5-1_10_1.tar.gz"
    remove_generated_path "${BASE_DIR}/matio"
    remove_generated_path "${BASE_DIR}/build_zlib"
    remove_generated_path "${BASE_DIR}/build_hdf5"
    remove_generated_path "${BASE_DIR}/build_matio"
}

verify_sha256() {
    local file="$1"
    local expected="$2"

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run: would verify SHA256 for ${file}"
        return
    fi

    local actual
    actual="$(sha256sum "$file" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || die "SHA256 mismatch for ${file}: expected ${expected}, got ${actual}"
}

download_file() {
    local url="$1"
    local output="$2"
    local sha256="${3:-}"

    ensure_inside_base "$output"
    log "Downloading ${url}"
    remove_generated_path "$output"
    run wget --tries=3 --timeout=30 -O "$output" "$url"

    if [[ -n "$sha256" ]]; then
        verify_sha256 "$output" "$sha256"
    fi
}

extract_archive() {
    local archive="$1"
    local extracted_name="$2"
    local source_dir="$3"

    ensure_inside_base "$archive"
    ensure_inside_base "$source_dir"

    remove_generated_path "$source_dir"
    remove_generated_path "${BASE_DIR}/${extracted_name}"
    run_in_dir "$BASE_DIR" tar -xzf "$archive"
    run mv "${BASE_DIR}/${extracted_name}" "$source_dir"

    [[ "$DRY_RUN" == true || -d "$source_dir" ]] || die "Source directory missing after extraction: ${source_dir}"
}

runtime_path() {
    local first="$1"
    local second="${2:-}"

    if [[ -n "$second" ]]; then
        printf '%s:%s%s' "$first" "$second" "${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    else
        printf '%s%s' "$first" "${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    fi
}

build_zlib() {
    log "Building zlib ${ZLIB_VERSION}."

    download_file "$ZLIB_URL" "${BASE_DIR}/${ZLIB_ARCHIVE}" "$ZLIB_SHA256"
    extract_archive "${BASE_DIR}/${ZLIB_ARCHIVE}" "$ZLIB_SOURCE_NAME" "$ZLIB_SOURCE_DIR"
    remove_generated_path "$ZLIB_INSTALL_DIR"

    run_in_dir "$ZLIB_SOURCE_DIR" env CC=gcc CXX=g++ ./configure --prefix="$ZLIB_INSTALL_DIR"
    run_in_dir "$ZLIB_SOURCE_DIR" make -j"$JOBS"
    run_in_dir "$ZLIB_SOURCE_DIR" make install
}

build_hdf5() {
    log "Building HDF5 ${HDF5_VERSION}."

    download_file "$HDF5_URL" "${BASE_DIR}/${HDF5_ARCHIVE}" "$HDF5_SHA256"
    extract_archive "${BASE_DIR}/${HDF5_ARCHIVE}" "$HDF5_SOURCE_NAME" "$HDF5_SOURCE_DIR"
    remove_generated_path "$HDF5_BUILD_DIR"
    remove_generated_path "$HDF5_INSTALL_DIR"
    run mkdir -p "$HDF5_BUILD_DIR"

    run_in_dir "$HDF5_BUILD_DIR" env \
        CC=gcc \
        CXX=g++ \
        FC=gfortran \
        LD_LIBRARY_PATH="$(runtime_path "${ZLIB_INSTALL_DIR}/lib")" \
        "${HDF5_SOURCE_DIR}/configure" \
        --prefix="$HDF5_INSTALL_DIR" \
        --with-zlib="$ZLIB_INSTALL_DIR" \
        --enable-cxx \
        --enable-fortran \
        --enable-shared \
        --enable-static \
        --enable-build-mode=production \
        --disable-parallel \
        --disable-tests \
        --with-pic \
        --with-default-api-version=v110
    run_in_dir "$HDF5_BUILD_DIR" env LD_LIBRARY_PATH="$(runtime_path "${ZLIB_INSTALL_DIR}/lib")" make -j"$JOBS"
    run_in_dir "$HDF5_BUILD_DIR" make install
}

build_matio() {
    log "Building matio ${MATIO_VERSION}."

    download_file "$MATIO_URL" "${BASE_DIR}/${MATIO_ARCHIVE}" "$MATIO_SHA256"
    extract_archive "${BASE_DIR}/${MATIO_ARCHIVE}" "$MATIO_SOURCE_NAME" "$MATIO_SOURCE_DIR"
    remove_generated_path "$MATIO_BUILD_DIR"
    remove_generated_path "$MATIO_INSTALL_DIR"
    run mkdir -p "$MATIO_BUILD_DIR"

    local library_path="${HDF5_INSTALL_DIR}/lib:${ZLIB_INSTALL_DIR}/lib"
    local pkg_config_path="${HDF5_INSTALL_DIR}/lib/pkgconfig:${ZLIB_INSTALL_DIR}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}"

    run_in_dir "$MATIO_BUILD_DIR" env \
        CC=gcc \
        CXX=g++ \
        CPPFLAGS="-I${HDF5_INSTALL_DIR}/include -I${ZLIB_INSTALL_DIR}/include" \
        LDFLAGS="-L${HDF5_INSTALL_DIR}/lib -L${ZLIB_INSTALL_DIR}/lib -Wl,-rpath,${HDF5_INSTALL_DIR}/lib -Wl,-rpath,${ZLIB_INSTALL_DIR}/lib" \
        LD_LIBRARY_PATH="$(runtime_path "$library_path")" \
        PKG_CONFIG_PATH="$pkg_config_path" \
        "${MATIO_SOURCE_DIR}/configure" \
        --prefix="$MATIO_INSTALL_DIR" \
        --with-default-file-ver=7.3 \
        --enable-mat73=yes \
        --with-hdf5="$HDF5_INSTALL_DIR" \
        --with-zlib="$ZLIB_INSTALL_DIR"
    run_in_dir "$MATIO_BUILD_DIR" env LD_LIBRARY_PATH="$(runtime_path "$library_path")" make -j"$JOBS"
    run_in_dir "$MATIO_BUILD_DIR" make install
}

write_environment_file() {
    log "Writing environment file: ${ENV_FILE}"

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run: would write ${ENV_FILE}"
        return
    fi

    cat >"$ENV_FILE" <<EOF
# Generated by installation_script_linuxOnly_matio_hdf5_zlib.bash
# shellcheck shell=bash

export ZLIB_ROOT="${ZLIB_INSTALL_DIR}"
export HDF5_ROOT="${HDF5_INSTALL_DIR}"
export HDF5_DIR="${HDF5_INSTALL_DIR}"
export MATIO_ROOT="${MATIO_INSTALL_DIR}"

export PATH="${MATIO_INSTALL_DIR}/bin:${HDF5_INSTALL_DIR}/bin:${ZLIB_INSTALL_DIR}/bin\${PATH:+:\${PATH}}"
export C_INCLUDE_PATH="${MATIO_INSTALL_DIR}/include:${HDF5_INSTALL_DIR}/include:${ZLIB_INSTALL_DIR}/include\${C_INCLUDE_PATH:+:\${C_INCLUDE_PATH}}"
export CPLUS_INCLUDE_PATH="${MATIO_INSTALL_DIR}/include:${HDF5_INSTALL_DIR}/include:${ZLIB_INSTALL_DIR}/include\${CPLUS_INCLUDE_PATH:+:\${CPLUS_INCLUDE_PATH}}"
export LIBRARY_PATH="${MATIO_INSTALL_DIR}/lib:${HDF5_INSTALL_DIR}/lib:${ZLIB_INSTALL_DIR}/lib\${LIBRARY_PATH:+:\${LIBRARY_PATH}}"
export LD_LIBRARY_PATH="${MATIO_INSTALL_DIR}/lib:${HDF5_INSTALL_DIR}/lib:${ZLIB_INSTALL_DIR}/lib\${LD_LIBRARY_PATH:+:\${LD_LIBRARY_PATH}}"
export PKG_CONFIG_PATH="${MATIO_INSTALL_DIR}/lib/pkgconfig:${HDF5_INSTALL_DIR}/lib/pkgconfig:${ZLIB_INSTALL_DIR}/lib/pkgconfig\${PKG_CONFIG_PATH:+:\${PKG_CONFIG_PATH}}"
EOF
}

remove_marker_block() {
    local file="$1"
    local start_marker="$2"
    local end_marker="$3"
    local first_line=""
    local last_line=""

    while true; do
        first_line="$(grep -nF "$start_marker" "$file" | head -n1 | cut -d: -f1 || true)"
        last_line="$(grep -nF "$end_marker" "$file" | head -n1 | cut -d: -f1 || true)"

        if [[ -z "$first_line" || -z "$last_line" ]]; then
            break
        fi

        if ((first_line > last_line)); then
            warn "Found malformed shell rc marker block in ${file}; leaving it unchanged"
            break
        fi

        sed -i.bak "${first_line},${last_line}d" "$file"
    done
}

update_shell_rc() {
    if [[ "$UPDATE_SHELL_RC" != true ]]; then
        log "Skipping ~/.bashrc update."
        return
    fi

    local bashrc="${HOME}/.bashrc"
    local start_marker="## --> Added by hdf5 zlib matio installation script"
    local end_marker="## <-- Added by hdf5 zlib matio installation script"

    log "Updating ${bashrc} with managed matio/HDF5/zlib environment block."

    if [[ "$DRY_RUN" == true ]]; then
        log "Dry run: would update ${bashrc} to source ${ENV_FILE}"
        return
    fi

    touch "$bashrc"
    remove_marker_block "$bashrc" "$start_marker" "$end_marker"

    {
        printf '\n%s\n' "$start_marker"
        printf 'source %q\n' "$ENV_FILE"
        printf '%s\n' "$end_marker"
    } >>"$bashrc"
}

main() {
    parse_args "$@"
    detect_jobs
    configure_paths
    print_configuration
    check_prerequisites

    if [[ "$DRY_RUN" == true ]]; then
        print_dry_run_plan
        log "Dry run complete."
        return
    fi

    prepare_base_dir

    if [[ "$CLEAN" == true ]]; then
        clean_previous_outputs
        prepare_base_dir
    fi

    build_zlib
    build_hdf5
    build_matio
    write_environment_file
    update_shell_rc

    log "Done. Run 'source ~/.bashrc' or open a new terminal to load matio/HDF5/zlib."
}

main "$@"
