# UTM → Parallels Import Script (macOS / Apple Silicon)

A small, no-nonsense shell script that imports **UTM virtual machines** (typically distributed as a `.utm` bundle inside a `.zip`) into **Parallels Desktop** on macOS — with a focus on **Apple Silicon (ARM64)** workflows.

If you have a UTM export (for example a Linux security distro packaged as `Something_arm64.utm.zip`) and you want it running under Parallels without rebuilding the VM by hand, this script automates the entire process.

---

## What it does

The script performs the following steps end-to-end:

1. **Validates inputs**
   - Checks that the provided `.zip` file exists
   - Ensures `prlctl` (Parallels CLI) is available
   - Ensures `qemu-img` is installed

2. **Unpacks the archive**
   - Extracts the `.zip` into a temporary directory

3. **Finds the UTM bundle**
   - Locates the first `*.utm` bundle inside the extracted contents

4. **Detects the disk image**
   - Locates the first disk image in the UTM bundle with one of:
     - `.qcow2`, `.raw`, `.img`, `.bin`

5. **Converts disk to RAW (if needed)**
   - If the source is already RAW → it’s copied
   - Otherwise → `qemu-img convert -O raw` is used

6. **Calculates the correct disk size**
   - Reads the **virtual disk size** via `qemu-img info`
   - Creates a Parallels HDD sized to match (rounded up)

7. **Creates a new Parallels VM**
   - Creates a Linux VM with no HDD attached
   - Adds a new **plain** HDD (SATA, position 0)

8. **Locates the created `.pvm` bundle**
   - Attempts to resolve the VM path reliably via Parallels metadata
   - Falls back to typical Parallels directories (and a shallow search under `~/`)

9. **Backs up the new Parallels disk**
   - Copies the created `.hds` to `*.bak.<timestamp>` before modification

10. **Writes the RAW image into the Parallels disk**
    - Uses `qemu-img convert -O raw` to write the RAW disk data into the `.hds`

✅ Output: a ready-to-boot Parallels VM you can start immediately via `prlctl`.

---

## Requirements

- **macOS**
- **Parallels Desktop** (provides `prlctl`)
- **QEMU** tools (for `qemu-img`)

Install QEMU with Homebrew:

```bash
brew install qemu
```
## Usage

- **Make the script executable:**
chmod +x utm2parallels.sh

- **Run with a UTM zip export:**

./utm2parallels.sh /path/to/YourVM.utm.zip
