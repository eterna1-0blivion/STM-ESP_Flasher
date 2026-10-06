# FC Passthrough RX flasher

`flash_bin_bfpassthrough.exe` is the user-supplied RX flasher by the Barvinok-5 team, version 0.8. It is used for the separate ESP32 RX workflow through a compatible Betaflight flight controller. It is not the ROI-specific direct-esptool workflow.

The application invokes it with the selected FC COM port, `--baud 921600`, `--esp32`, and the user-selected BIN via `--file`. The application does not request a full-chip erase (`--erase`).

SHA-256: `99DE06743F6F49E91325C44A90BF86AAD105766D6BEA8A28EA8CC81928E865BA`

No license or source code accompanied the supplied executable. Confirm redistribution permission before publishing a package containing it. Hardware flashing was not validated; compatibility depends on the flight-controller firmware, receiver wiring, and target module.
