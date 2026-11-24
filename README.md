# wifidiag


A simple but comprehensive Wi-Fi and network diagnostics script for Linux.

## Overview

`wifi-diag.sh` is a shell script that runs a sequential series of network benchmarks and diagnostic tests. It's designed to help you quickly assess the state of your Wi-Fi and internet connection.

The key feature is its sequential execution model: tests for idle latency, DNS performance, and throughput are run one after another. This ensures that load-intensive tests (like speed tests) do not interfere with and pollute the results of latency-sensitive tests.

The script saves a detailed report to a timestamped text file in your home directory, making it easy to compare network performance over time or before and after making a change.

## Features

The script performs a comprehensive check divided into four main sections:

1.  **Wi-Fi Link & RF Environment**
    *   Current link status, channel, width, and SSID.
    *   Station statistics: Tx/Rx bitrate, signal strength, retries, and failures.
    *   Channel survey data showing noise and busy time.
    *   Interface packet error counts.
    *   A scan of nearby Wi-Fi networks, summarized by channel and sorted by signal strength.

2.  **Idle Latency & Stability**
    *   `ping` tests to the local gateway and public DNS servers (1.1.1.1) for both IPv4 and IPv6.
    *   A short `traceroute` to check the first few hops.
    *   Detection of active VPNs, proxies, or tunnels.
    *   A summary of current network connections and the applications using them.
    *   Recent Wi-Fi disconnect or roam events from the system journal.

3.  **DNS Latency**
    *   Lists configured DNS resolvers.
    *   Measures the query time for uncached lookups against your gateway, public resolvers, and system-configured resolvers.

4.  **Throughput & Bufferbloat**
    *   Measures download and upload throughput using Cloudflare's speed test service.
    *   Simultaneously runs `ping` during the throughput tests to measure latency under load (bufferbloat).
    *   Reports on system settings related to ECN, L4S, and queuing disciplines (qdisc).

## Dependencies

The script requires the following command-line tools to be installed:
*   `iw`
*   `nmcli`
*   `ip` (from `iproute2`)
*   `ping`
*   `dig`
*   `curl`

Optional:
*   `traceroute` (falls back to `tracepath` if not found)

## Usage

1.  Clone this repository or download the `wifi-diag.sh` script.

2.  Make the script executable:
    ```sh
    chmod +x wifi-diag.sh
    ```

3.  Run the script with a descriptive tag. This is useful for "before and after" comparisons.

    For example, to capture the state *before* making a network change:
    ```sh
    ./wifi-diag.sh before
    ```

    After making a change (e.g., moving your router, changing a setting), run it again:
    ```sh
    ./wifi-diag.sh after
    ```

    If you don't provide a tag, it defaults to `run`.

## Output

The script prints its results to the console and simultaneously saves a complete report to a file in your home directory. The file will be named using the pattern `~/wifi-diag-<TAG>-<YYYYMMDD-HHMMSS>.txt`.

You can then use a `diff` tool to easily compare the "before" and "after" reports to see what changed.

Example:
```sh
diff ~/wifi-diag-before-*.txt ~/wifi-diag-after-*.txt
