# Compilation and Packaging Guide (ARM64 / 16K Page Compatible)

This guide documents how to compile **epson_print_conf** into a standalone executable and package it as native **RPM** and **DEB** installers on **ARM64 (aarch64)** architectures, with guaranteed compatibility for **16KB page size kernels** (such as Fedora Asahi Linux on Apple Silicon, Android 15, and Raspberry Pi 5 16K kernels) as well as standard 4KB and 64KB page systems.

---

## 1. Quick Start: Automated Build

An automated build script [`build.sh`](build.sh) is provided to orchestrate the entire process.

### Run the full build:
```bash
./build.sh
```

This command will:
1. Validate required Python and system dependencies.
2. Compile the standalone executable using PyInstaller with 16KB/64KB ELF segment alignment.
3. Verify the binary ELF headers with `readelf` to ensure 16K page compatibility.
4. Package an `.rpm` installer for Fedora / RHEL / openSUSE (aarch64).
5. Package a `.deb` installer for Debian / Ubuntu / Raspberry Pi OS (arm64).
6. Generate SHA256 checksums for all artifacts in `dist/`.

### Build Script Options

| Option | Description |
|---|---|
| `./build.sh` or `./build.sh --all` | Compile binary and build both RPM and DEB packages (default) |
| `./build.sh --binary-only` | Compile only the PyInstaller standalone binary (`dist/epson_print_conf`) |
| `./build.sh --rpm-only` | Build only the RPM package |
| `./build.sh --deb-only` | Build only the DEB package |
| `./build.sh --clean` | Remove previous build artifacts before compiling |
| `./build.sh --help` | Show command usage and options |

---

## 2. Prerequisites & Dependencies

### System Packages

- **Fedora / RHEL / CentOS**:
  ```bash
  sudo dnf install -y python3 python3-pip python3-tkinter rpm-build dpkg binutils
  ```

- **Debian / Ubuntu / Raspberry Pi OS**:
  ```bash
  sudo apt update
  sudo apt install -y python3 python3-pip python3-tk rpm dpkg-dev binutils
  ```

### Python Dependencies

Install the project dependencies and PyInstaller:
```bash
pip install --user pyinstaller
pip install --user -r requirements.txt
```

---

## 3. 16KB Page Size Compatibility

### The Challenge
Modern ARM64 Linux kernels (e.g. Asahi Linux on Apple Silicon, Android 15, and specialized Raspberry Pi 5 kernel configs) use a **16KB page size** (`getconf PAGE_SIZE = 16384`) rather than the legacy 4KB size.

ELF executables and shared libraries that have their `LOAD` segments aligned only to 4KB cannot be mapped by the Linux kernel loader and crash immediately with:
```
Segmentation fault (core dumped)
```

### Our Solution in `epson_print_conf.spec`
1. **Disabled UPX Compression (`upx=False`)**: UPX repacks ELF segments into 4KB boundaries by default, breaking 16KB compatibility. Disabling UPX preserves native toolchain ELF alignment (64KB / `0x10000`).
2. **Cross-Platform Font Fallback**: Avoids hard crashes on non-Windows systems when generating the splash screen.
3. **Dynamic `mypyc` Extension Discovery**: Dynamically bundles precompiled C-extensions (used by `tomli` and `black`) regardless of platform hash variations.
4. **Targeted Exclusions**: Excludes unused heavy GUI frameworks (Qt, matplotlib) to prevent conflicting library hooks.

### Verifying Alignment
You can verify the page alignment of any generated binary using `readelf`:
```bash
readelf -l dist/epson_print_conf | grep -A 1 "LOAD"
```
All `Align` fields must be `0x4000` (16KB) or `0x10000` (64KB).

---

## 4. Manual Compilation & Packaging Steps

If you prefer to run the steps manually instead of using `build.sh`:

### Step 1: Compile the Executable
```bash
python3 -m PyInstaller epson_print_conf.spec -- --default
```
The output binary will be created at `dist/epson_print_conf`.

### Step 2: Build the RPM Package (aarch64)
```bash
VERSION=$(grep -E '^VERSION = "[0-9]+\.[0-9]+\.[0-9]+"' ui.py | head -n1 | cut -d'"' -f2)
RPM_TOPDIR="$(pwd)/dist/rpmbuild"
mkdir -p "$RPM_TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cp dist/epson_print_conf "$RPM_TOPDIR/SOURCES/"

cat << 'EOF' > "$RPM_TOPDIR/SPECS/epson-print-conf.spec"
Name:           epson-print-conf
Version:        8.2.0
Release:        1%{?dist}
Summary:        Epson Printer Configuration tool
License:        EUPL-1.2
AutoReqProv:    no
BuildArch:      aarch64
%define _build_id_links none
%define debug_package %{nil}
%global __os_install_post %{nil}

%description
Epson Printer Configuration tool and waste ink counter resetter.

%install
mkdir -p %{buildroot}/usr/bin
install -m 755 %{_sourcedir}/epson_print_conf %{buildroot}/usr/bin/epson_print_conf
ln -sf epson_print_conf %{buildroot}/usr/bin/epson_print_conf_ui

%files
/usr/bin/epson_print_conf
/usr/bin/epson_print_conf_ui
EOF

rpmbuild --define "_topdir $RPM_TOPDIR" -bb "$RPM_TOPDIR/SPECS/epson-print-conf.spec"
cp "$RPM_TOPDIR"/RPMS/aarch64/*.rpm dist/
rm -rf "$RPM_TOPDIR"
```

### Step 3: Build the DEB Package (arm64)
```bash
VERSION=$(grep -E '^VERSION = "[0-9]+\.[0-9]+\.[0-9]+"' ui.py | head -n1 | cut -d'"' -f2)
DEB_DIR="$(pwd)/dist/deb_staging"
mkdir -p "$DEB_DIR"/DEBIAN "$DEB_DIR"/usr/bin

cp dist/epson_print_conf "$DEB_DIR/usr/bin/"
ln -sf epson_print_conf "$DEB_DIR/usr/bin/epson_print_conf_ui"

cat << EOF > "$DEB_DIR/DEBIAN/control"
Package: epson-print-conf
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: arm64
Maintainer: epson_print_conf contributors
Description: Epson Printer Configuration tool and waste ink counter resetter
 Built with 16KB and 4KB page size compatibility for modern ARM64 kernels.
EOF

dpkg-deb --build --root-owner-group "$DEB_DIR" "dist/epson-print-conf_${VERSION}_arm64.deb"
rm -rf "$DEB_DIR"
```

---

## 5. Installing and Running the Packages

### Installing on Fedora / RHEL:
```bash
sudo dnf install ./dist/epson-print-conf-*.rpm
```

### Installing on Debian / Ubuntu:
```bash
sudo apt install ./dist/epson-print-conf_*_arm64.deb
```

### Launching the Application:
- From application launcher: Search for **Epson Printer Configuration**
- From terminal:
  ```bash
  epson_print_conf
  ```
- Or run the standalone executable directly without installing:
  ```bash
  ./dist/epson_print_conf
  ```
