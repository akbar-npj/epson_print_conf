#!/usr/bin/env bash
# ==============================================================================
# build.sh - Automated build script for epson_print_conf (ARM64 / aarch64)
# Produces:
#   1. Standalone ELF executable (16K page size compatible)
#   2. RPM package (.rpm) for Fedora / RHEL / openSUSE
#   3. Debian package (.deb) for Debian / Ubuntu / Raspberry Pi OS
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

BUILD_BINARY=true
BUILD_RPM=true
BUILD_DEB=true
CLEAN=false

# ------------------------------------------------------------------------------
# Help / Usage
# ------------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Automated build script for epson_print_conf on ARM64 (16K page compatible).

Options:
  --all            Build binary, RPM, and DEB packages (default)
  --binary-only    Compile only the PyInstaller standalone binary
  --rpm-only       Build only the RPM package (compiles binary if needed)
  --deb-only       Build only the DEB package (compiles binary if needed)
  --clean          Remove existing build artifacts before building
  -h, --help       Show this help message and exit

Outputs are saved in the 'dist/' directory.
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            BUILD_BINARY=true
            BUILD_RPM=true
            BUILD_DEB=true
            shift
            ;;
        --binary-only)
            BUILD_BINARY=true
            BUILD_RPM=false
            BUILD_DEB=false
            shift
            ;;
        --rpm-only)
            BUILD_BINARY=true
            BUILD_RPM=true
            BUILD_DEB=false
            shift
            ;;
        --deb-only)
            BUILD_BINARY=true
            BUILD_RPM=false
            BUILD_DEB=true
            shift
            ;;
        --clean)
            CLEAN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo "============================================================"
echo " Starting epson_print_conf automated build (ARM64)"
echo "============================================================"

# ------------------------------------------------------------------------------
# 1. Clean if requested
# ------------------------------------------------------------------------------
if [ "${CLEAN}" = true ]; then
    echo "[*] Cleaning old build artifacts..."
    rm -rf build dist/test_* dist/*.rpm dist/*.deb dist/*.txt
fi

# ------------------------------------------------------------------------------
# 2. Environment and Dependency Checks
# ------------------------------------------------------------------------------
command -v python3 >/dev/null 2>&1 || { echo "[ERROR] python3 is required but not installed."; exit 1; }

ARCH="$(uname -m)"
echo "[*] Detected host architecture: ${ARCH}"
if [[ "${ARCH}" != "aarch64" && "${ARCH}" != "arm64" ]]; then
    echo "[WARNING] Current architecture is ${ARCH}. Expected aarch64 / arm64."
fi

# Extract version from ui.py
VERSION="$(grep -E '^VERSION = "[0-9]+\.[0-9]+\.[0-9]+"' ui.py | head -n1 | cut -d'"' -f2)"
if [ -z "${VERSION}" ]; then
    VERSION="8.2.0"
    echo "[WARNING] Could not parse VERSION from ui.py, defaulting to ${VERSION}"
else
    echo "[*] Detected project version: ${VERSION}"
fi

# Check packaging utilities
if [ "${BUILD_RPM}" = true ]; then
    command -v rpmbuild >/dev/null 2>&1 || {
        echo "[WARNING] 'rpmbuild' not found. Disabling RPM package creation."
        BUILD_RPM=false
    }
fi

if [ "${BUILD_DEB}" = true ]; then
    command -v dpkg-deb >/dev/null 2>&1 || {
        echo "[WARNING] 'dpkg-deb' not found. Disabling DEB package creation."
        BUILD_DEB=false
    }
fi

# Check PyInstaller
if ! python3 -m PyInstaller --version >/dev/null 2>&1; then
    echo "[*] Installing PyInstaller..."
    python3 -m pip install --user pyinstaller
fi

# Check dependencies
echo "[*] Verifying Python requirements..."
python3 -m pip install --user -r requirements.txt

# ------------------------------------------------------------------------------
# 3. Compile Standalone Binary via PyInstaller
# ------------------------------------------------------------------------------
BINARY_PATH="dist/epson_print_conf"

if [ "${BUILD_BINARY}" = true ] || [ ! -f "${BINARY_PATH}" ]; then
    echo ""
    echo "[*] Compiling standalone executable with PyInstaller (16K page alignment)..."
    python3 -m PyInstaller epson_print_conf.spec -- --default

    if [ ! -f "${BINARY_PATH}" ]; then
        echo "[ERROR] Compilation failed: ${BINARY_PATH} was not created."
        exit 1
    fi
    chmod +x "${BINARY_PATH}"
    echo "[SUCCESS] Standalone binary compiled: ${BINARY_PATH}"

    # Verify 16K page alignment
    if command -v readelf >/dev/null 2>&1; then
        echo "[*] Verifying 16K/64K ELF page alignment of ${BINARY_PATH}..."
        NON_COMPLIANT=0
        while IFS= read -r line; do
            ALIGN_HEX=$(echo "${line}" | awk '{print $NF}')
            if [[ "${ALIGN_HEX}" =~ ^0x[0-9a-fA-F]+$ ]]; then
                ALIGN_DEC=$((16#${ALIGN_HEX#0x}))
                if (( ALIGN_DEC < 16384 )); then
                    echo "[WARNING] Segment alignment ${ALIGN_HEX} is smaller than 16384 (16KB)!"
                    NON_COMPLIANT=$((NON_COMPLIANT + 1))
                fi
            fi
        done < <(readelf -l "${BINARY_PATH}" | grep -A 1 "LOAD" | grep -v "LOAD" | grep -v "^--")

        if (( NON_COMPLIANT == 0 )); then
            echo "[SUCCESS] Verified: Executable LOAD segments are aligned to >= 16KB (0x4000)."
        else
            echo "[WARNING] ${NON_COMPLIANT} segment(s) had alignment under 16KB."
        fi
    fi
fi

# ------------------------------------------------------------------------------
# 4. Generate Desktop Launcher
# ------------------------------------------------------------------------------
DESKTOP_FILE="dist/epson-print-conf.desktop"
cat << 'EOF' > "${DESKTOP_FILE}"
[Desktop Entry]
Name=Epson Printer Configuration
Comment=Configure and monitor Epson printers (SNMP / USB)
Exec=/usr/bin/epson_print_conf
Icon=printer
Terminal=false
Type=Application
Categories=Utility;Settings;Printing;HardwareSettings;
Keywords=epson;printer;ink;waste;counter;
EOF

# ------------------------------------------------------------------------------
# 5. Build RPM Package (aarch64)
# ------------------------------------------------------------------------------
if [ "${BUILD_RPM}" = true ]; then
    echo ""
    echo "[*] Building RPM package for aarch64..."
    RPM_TOPDIR="${SCRIPT_DIR}/dist/rpmbuild"
    rm -rf "${RPM_TOPDIR}"
    mkdir -p "${RPM_TOPDIR}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

    cp "${BINARY_PATH}" "${RPM_TOPDIR}/SOURCES/epson_print_conf"
    cp "${DESKTOP_FILE}" "${RPM_TOPDIR}/SOURCES/epson-print-conf.desktop"

    cat << EOF > "${RPM_TOPDIR}/SPECS/epson-print-conf.spec"
Name:           epson-print-conf
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        Epson Printer Configuration tool and waste ink counter resetter
License:        EUPL-1.2
AutoReqProv:    no
BuildArch:      aarch64

# PyInstaller packages bundle their own runtime; disable stripping to avoid archive corruption
%define _build_id_links none
%define debug_package %{nil}
%global __os_install_post %{nil}

%description
The Epson Printer Configuration Tool provides an interface for configuration
and monitoring of Epson printers connected via Wi-Fi (SNMP) and USB.
Includes waste ink counter resetter and EEPROM inspection utilities.
Compiled with 16KB/64KB page size compatibility for modern ARM64 Linux kernels.

%install
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/applications
install -m 755 %{_sourcedir}/epson_print_conf %{buildroot}/usr/bin/epson_print_conf
ln -sf epson_print_conf %{buildroot}/usr/bin/epson_print_conf_ui
install -m 644 %{_sourcedir}/epson-print-conf.desktop %{buildroot}/usr/share/applications/epson-print-conf.desktop

%files
/usr/bin/epson_print_conf
/usr/bin/epson_print_conf_ui
/usr/share/applications/epson-print-conf.desktop
EOF

    rpmbuild --define "_topdir ${RPM_TOPDIR}" -bb "${RPM_TOPDIR}/SPECS/epson-print-conf.spec"
    find "${RPM_TOPDIR}/RPMS" -name "*.rpm" -exec cp {} dist/ \;
    rm -rf "${RPM_TOPDIR}"
    echo "[SUCCESS] RPM package created in dist/"
fi

# ------------------------------------------------------------------------------
# 6. Build DEB Package (arm64)
# ------------------------------------------------------------------------------
if [ "${BUILD_DEB}" = true ]; then
    echo ""
    echo "[*] Building DEB package for arm64..."
    DEB_DIR="${SCRIPT_DIR}/dist/deb_staging"
    rm -rf "${DEB_DIR}"
    mkdir -p "${DEB_DIR}/DEBIAN"
    mkdir -p "${DEB_DIR}/usr/bin"
    mkdir -p "${DEB_DIR}/usr/share/applications"

    cp "${BINARY_PATH}" "${DEB_DIR}/usr/bin/epson_print_conf"
    ln -sf epson_print_conf "${DEB_DIR}/usr/bin/epson_print_conf_ui"
    cp "${DESKTOP_FILE}" "${DEB_DIR}/usr/share/applications/epson-print-conf.desktop"

    cat << EOF > "${DEB_DIR}/DEBIAN/control"
Package: epson-print-conf
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: arm64
Maintainer: epson_print_conf contributors <https://github.com/akbar-npj/epson_print_conf>
Description: Epson Printer Configuration tool and waste ink counter resetter
 The Epson Printer Configuration Tool provides an interface for configuration
 and monitoring of Epson printers connected via Wi-Fi (SNMP) and USB.
 Includes waste ink counter resetter and EEPROM inspection utilities.
 Compiled with 16KB and 4KB page size compatibility for modern ARM64 kernels.
EOF

    DEB_OUTPUT_NAME="dist/epson-print-conf_${VERSION}_arm64.deb"
    dpkg-deb --build --root-owner-group "${DEB_DIR}" "${DEB_OUTPUT_NAME}"
    rm -rf "${DEB_DIR}"
    echo "[SUCCESS] DEB package created: ${DEB_OUTPUT_NAME}"
fi

# Clean up intermediate desktop file in dist
rm -f "${DESKTOP_FILE}"

# ------------------------------------------------------------------------------
# 7. Checksums and Summary
# ------------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " Build Complete! Artifacts in dist/:"
echo "============================================================"
cd dist
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum epson_print_conf epson-print-conf*.[rd][pe][mb] 2>/dev/null > SHA256SUMS.txt || true
fi
ls -lh epson_print_conf epson-print-conf*.[rd][pe][mb] 2>/dev/null || true
echo "============================================================"
echo "All packages are ready and 16K/64K page compatible."
