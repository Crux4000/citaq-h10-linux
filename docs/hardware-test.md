# Hardware test: modern kernel on the H10-3

Goal: Linux 6.18 boots from the recovery slot to a busybox shell on the serial console.

You need: the terminal on the bench with the backup LiPo connected (inline switch fitted),
a 3.3 V USB-serial adapter on TP17 (board TX) / TP18 (board RX) / TP19 (GND) with VCC left
unconnected, PuTTY at 115200 8N1 with logging on, and root adb.

Commands are PowerShell on Windows. `adb` means whichever adb reaches the terminal
(network `-s <ip>:5555` or the internal USB).

## 1. Build the two images (on the PC / WSL)

```sh
python3 tools/build_mainline.py recovery.img out/Image-stub  out/rk3368-citaq-h10.dtb linux-a-stub.img
python3 tools/build_mainline.py recovery.img out/Image-plain out/rk3368-citaq-h10.dtb linux-b-plain.img
```

Write down the `md5` and the `(N x 16384)` block count each one prints. The plain image
gives a TEXT_OFFSET warning. That's expected, because it's plan B.

## 2. Back up whatever is in the recovery slot now

Find the partition node first. It's named differently on stock Android 5.1 and the
Android 10 port:

```powershell
adb root
adb shell 'ls -l /dev/block/by-name/recovery /dev/block/platform/*/by-name/recovery 2>/dev/null'
```

Use the path that exists as `$REC` below. Then:

```powershell
$REC = '/dev/block/by-name/recovery'      # or the platform/... path
adb shell "dd if=$REC of=/data/local/tmp/recovery-backup.img bs=16384"
adb pull /data/local/tmp/recovery-backup.img .
```

Keep `recovery-backup.img`. It's your undo.

## 3. Flash image A (stub)

```powershell
adb push linux-a-stub.img /data/local/tmp/
adb shell 'md5sum /data/local/tmp/linux-a-stub.img'
adb shell "dd if=/data/local/tmp/linux-a-stub.img of=$REC bs=16384 && sync"
adb shell "dd if=$REC bs=16384 count=<N> 2>/dev/null | md5sum"
```

Both MD5s must match the one `build_mainline.py` printed (`<N>` is its block count).
If the box has no `md5sum`, use `busybox md5sum`.

## 4. Boot it

Start PuTTY logging, then:

```powershell
adb reboot recovery
```

What a good run looks like:

```
... U-Boot lines ...
[citaq-stub] relocation stub v1
[citaq-stub] dtb=0x... src=0x0000000000281000 len=0x...
[citaq-stub] dest=0x0000000000200000 image_size=0x...
[citaq-stub] jumping to 0x0000000000200000
[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x410fd034]
[    0.000000] Linux version 6.18.65 ...
...
 Citaq H10-3: mainline Linux
 uptime: ...  cpus: 8
```

Type `reboot -f` to go back to normal boot.

## 5. Reading a bad run

| Last thing on serial | Meaning | Next |
|---|---|---|
| `sha mismatch` / `bad image magic` / rockusb | U-Boot rejected the image | Check the MD5s. Make sure the stock recovery.img was the template |
| `Starting kernel ...` then nothing | Stub never printed. UART base or U-Boot hand-off differs from what we expect | Send the log |
| `[citaq-stub] ERROR ...` | Stub refused (bad magic or layout) | Send the log |
| `[citaq-stub] jumping ...` then nothing | Kernel died before earlycon | Try image B. Send the log |
| Linux log, then stops | Kernel problem (clocks, PSCI, ...) | Send the log, then `reboot -f` or power cycle |

A hang needs the LiPo switch **and** the 24 V supply cycled. After that, normal boot comes
back (U-Boot only loads recovery when asked to).

## 6. Plan B: image B (plain, unaligned)

Same as step 3 with `linux-b-plain.img`. The expected extra line is
`[Firmware Bug]: Kernel image misaligned at boot`. If B works but A doesn't, the stub is the
problem, which is a useful result too.

## 7. Undo

```powershell
adb push recovery-backup.img /data/local/tmp/
adb shell "dd if=/data/local/tmp/recovery-backup.img of=$REC bs=16384 && sync"
```
