# VHDL Window Slider

This window slider design is a reusable VHDL module that performs a sliding window operation over a stream of input pixel data. This module is commonly used in image and signal processing tasks such as convolution, filtering, and feature extraction in hardware accelerators (like FPGAs).

---

## Features

- Generic sliding window operation.
- Support for configurable window size, padding, stride, and frame dimensions.
- Streaming interface using AXI-Stream-like `tdata`, `tvalid`, and `tready` handshaking.
- Outputs windowed slices in column-major order.
- Works synchronously with a clock and reset.

---

## Generics Explained

| Generic      | Description                             |
|--------------|-----------------------------------------|
| `DATA_WIDTH` | Width of a single data pixel            |
| `PAD_X`      | Horizontal padding around the frame     |
| `PAD_Y`      | Vertical padding around the frame       |
| `WINDOW_X`   | Width of the sliding window             |
| `WINDOW_Y`   | Height of the sliding window            |
| `STRIDE_X`   | Horizontal stride for sliding           |
| `STRIDE_Y`   | Vertical stride for sliding             |
| `FRAME_X`    | Width of the frame (pixels per row)     |
| `FRAME_Y`    | Height of the frame (rows per frame)    |

---

## Ports Description

### Clocking

| Port | Dir | Width | Description      |
|------|-----|-------|------------------|
| `clk` | in  | 1     | System clock     |
| `rst` | in  | 1     | Active-high reset|

### Input Stream (AXIS-like Slave)

| Port           | Dir | Width                  | Description                               |
|----------------|-----|------------------------|-------------------------------------------|
| `s_axis_tdata` | in  | `DATA_WIDTH`           | Incoming pixel data                       |
| `s_axis_tvalid`| in  | 1                      | Valid signal for input stream             |
| `s_axis_tready`| out | 1                      | Ready signal for input stream             |

### Output Stream (AXIS-like Master)

| Port           | Dir | Width                          | Description                                 |
|----------------|-----|--------------------------------|---------------------------------------------|
| `m_axis_tdata` | out | `WINDOW_Y * DATA_WIDTH`        | One column of the current window            |
| `m_axis_tvalid`| out | 1                              | Valid signal for output stream              |
| `m_axis_tready`| in  | 1                              | Ready signal from the consumer              |
| `m_axis_tlast` | out | 1                              | Indicates end of window stream              |

---

## Functional Overview

The `window_slider` buffers input pixel data and extracts a sliding window (e.g., 5x5) from the full image or frame. It handles:

- **Input streaming**: Each clock cycle (when valid & ready), a pixel is fed in pixel-by-pixel.
- **Window buffering**: Internally stores rows and columns required to form each window.
- **Output formatting**: Outputs each column of the window as a single wide data word (`WINDOW_Y * DATA_WIDTH`).
- **Padding and stride**: Applies optional zero-padding and supports adjustable strides to control the overlap between windows.

---

## Future Work

- **Comprehensive Testbench**  
  Develop a thorough testbench suite that validates all major configurations, including:
  - Various window sizes (e.g., 3x3, 5x5, 7x7)
  - Different strides and padding values
  - Edge cases like partial windows or minimal frame sizes
  - Performance under high-throughput streaming

- **Simulation and Coverage Analysis**  
  Integrate with simulation tools (e.g., ModelSim, GHDL) to measure functional coverage and timing.

- **Visualization Tools**  
  Optional tools/scripts to visualize the sliding window operation using waveform viewers or image plots.

---

## Contributing

Contributions are welcome! Whether it's fixing bugs, improving documentation, or building testbenches — it all helps.

To contribute:
1. **Fork** the repository
2. **Create a feature branch**  
   `git checkout -b your-feature-name`
3. **Commit your changes**  
   Use clear, concise commit messages
4. **Push to your fork**  
   `git push origin your-feature-name`
5. **Open a Pull Request**  
   Describe what you changed and why

> Tips:
> - If you're adding new features or configurations, try to include relevant tests.
> - For questions or suggestions, feel free to open an issue!
