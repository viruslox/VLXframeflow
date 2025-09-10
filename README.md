# VLXframeflow

****VLXframeflow**** is a suite of shell scripts designed to configure a
Debian-based system for multi-camera video streaming and real-time GPS
tracking. It includes tools for initial system setup, OS installation on
NVMe drives, and managing **ffmpeg** streams and **gpsd** services.

This project is ideal for transforming single-board computers or other
embedded hardware into dedicated streaming and tracking devices for
mobile applications.

## Key Features

-   ****System Configuration (******system_configuration.sh******):****
    Automatically sets up Debian repositories (**testing**,
    **multimedia**), installs essential packages like **ffmpeg**,
    **gpsd**, and **v4l-utils**, and creates a dedicated user for
    running the services securely.
-   ****NVMe OS Installer (******nvme_installer.sh******):**** A utility
    to partition, format, and clone the existing operating system to a
    high-speed NVMe drive, including correct **fstab** and boot
    configuration. ****(Warning: This script will wipe the selected
    drive).****
-   ****Camera Streaming (******cameraman.sh******):**** Manages
    multiple video camera streams using **ffmpeg**. It can handle
    multiple V4L2 devices, capture audio, and stream the output to a
    configured RTSP URL.
-   ****GPS Tracking (******gps_tracker.sh******):**** Manages the
    **gpsd** service to read data from a connected GPS device (like a
    USB GPS module).
-   ****GPS API Client (******gps_api.sh******):**** Fetches the current
    speed from the **gpsd** service and sends it as a JSON payload to a
    specified API endpoint.
-   ****Centralized Configuration:**** Uses a simple
    **\~/.frameflow_profile** file for easy configuration of RTSP URLs,
    enabled devices, and API endpoints.

## Installation and Setup

Follow these steps to get VLXframeflow up and running on a fresh
Debian-based system.

### Step 1: System Configuration (Run as root)

First, you need to prepare the system by running the configuration
script. This only needs to be done once.

**sudo ./system_configuration.sh**

This script will:

1.  Update your **apt** sources to include testing and multimedia
    repositories.
2.  Install all necessary software packages.
3.  Prompt you to select an existing user or create a new dedicated user
    (**frameflow** by default) to run the services.

### Step 2: (Optional) Install OS on NVMe (Run as root)

If you want to run your operating system from a faster NVMe drive, this
script will automate the entire process.

****WARNING:**** This script will completely erase all data on the NVMe
drive you select. Proceed with caution.

**sudo ./nvme_installer.sh**

### Step 3: Initial Script Setup (Run as the dedicated user)

Log in as the user you selected or created in Step 1. Then, run the main
**frameflow.sh** script to create the initial configuration file.

**\# Switch to the dedicated user if you aren\'t already**

**su - frameflow**

**\# Navigate to the project directory**

**cd /opt/VLXframeflow**

**\# Run the setup script**

**./frameflow.sh**

### Step 4: Edit the Configuration File

Now, open the newly created profile in your home directory
(**\~/.frameflow_profile**) and edit the variables to match your setup.

**nano \~/.frameflow_profile**

****Example Configuration:****

**\# if zero means not enabled; 1 means enable only the first device
found, 2 only the first 2 devices found\...**

**ENABLED_DEVICES=2**

**\# The base URL for your RTSP server. The script will append \"\_1\",
\"\_2\", etc.**

**RTSP_URL=\"rtsps://\[your.server.com:8554/mystream\](https://your.server.com:8554/mystream)\"**

**\# Regex to find the audio input device (usually a USB HDMI adapter)**

**AUDIODEV=\'card.\*USB\'**

**\# The API endpoint for sending GPS data**

**API_URL=\"\[http://your-api-server.com:3000/update-gps\](http://your-api-server.com:3000/update-gps)\"**

## Usage

All scripts should be run by the dedicated user.

### Managing Camera Streams

Use the **cameraman.sh** script to control your video streams.

**\# Start streaming from the first camera**

**./cameraman.sh 1 start**

**\# Check the status of the first camera\'s stream**

**./cameraman.sh 1 status**

**\# Stop the stream**

**./cameraman.sh 1 stop**

### Managing GPS Tracking

First, start the GPS tracker, then run the API script to begin sending
data.

**\# Start the gpsd service**

**./gps_tracker.sh start**

**\# Check the status**

**./gps_tracker.sh status**

**\# Start sending GPS data to your API (this will run in the
foreground)**

**./gps_api.sh**

**\# Stop the gpsd service**

**./gps_tracker.sh stop**

## Future Development (To-Do)

This project is under active development. Planned features include:

-   ****Network Bonding:**** Implement network interface bonding to
    combine multiple connections (e.g., Ethernet, Wi-Fi, 4G) for
    improved reliability and bandwidth.
-   ****Systemd Integration:**** Complete the automatic creation and
    management of systemd service files for **cameraman** and
    **gps_tracker** to ensure they run on boot.
-   ****Improved Error Handling:**** Add more robust checks and error
    handling throughout all scripts.
-   ****Web Interface:**** A simple web-based dashboard for status
    monitoring and control.
