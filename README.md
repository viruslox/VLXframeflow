# VLXframeflow: 
# All-in-One Video Streaming and GPS Tracking

****VLXframeflow**** is a suite of shell scripts designed to transform 
any Debian-based single-board computer (SBC) into an high-availabilty
router, multi-camera video streaming and real-time GPS tracking device.

This suite is built for work on mobility, streaming and tracking.

## Features

-   ****Multi Network Bonding:**** Self-recognizes and configure multiple
      internet connections to increase bandwitch and fault tollerance.
-   ****Multi-Camera Support:**** Manage and stream from multiple USB
      and HDMI-IN V4L2 video devices.
-   ****Streaming:**** Utilizes ffmpeg to encode and stream video and
      audio to RTSP or RTMP servers.
-   ****GPS Tracking:**** Can recognize GPS antenna then capture, send
      GPS data (position, speed, altitude) to API relay.
-   ****Simplified Setup:**** Includes scripts to install the operating
      system on a high-speed NVMe or eMMc.

****VLXframeflow**** is designed for anyone who needs reliable video and data
transmission from a mobile environment.
****Be Dynamic**** thanks Multi-Camera Content to switch between.
****Stay Stable**** combining multiple internet connections (requires 4G/5G modems).
****Location-Aware**** built-in GPS tracking to create location data overlays.

## For the Commuting Professional
Stay productive and connected when traveling. You can attend meetings
while on a train or in a vehicle trip.

## For IRL Streamers
Take your live streams to the PRO level. With VLXframeflow on an SBC, You can
connect your cameras in a pre-assembled and compact, wearable streaming rig.

## For Transportation and Fleet Management
Equip your fleet with a monitoring solution. Track the precise location of every
vehicle through the integrated GPS tracker, sending data to your own API endpoint.

## Enhanced Phisical Security and Compliance
Use the multi-camera system as a sophisticated dashcam setup to record all angles,
providing evidence in case of issues, events, encounters.

## Getting Started
### (Optional) Install OS on NVMe (Run as root)
00_nvme_installer.sh clones your OS to a fast NVMe drive. 
Warning: This will erase the target drive.

### System Configuration: (Run as root)
01_system_configuration.sh will update your system, install all required packages 
like ffmpeg, gpsd, hostapd and create a dedicated user to run the services.

### Network Configuration: (Run as root)
02_network_configuration.sh creates networks and systemd network profiles

### Suite configuration
03_frameflow_update.sh creates the initial configuration file at ~/.frameflow_profile

### Edit Configuration
Open ~/.frameflow_profile with a text editor and customize the variables 
(RTSP server URL, enabled devices, API endpoints) to match your setup.

### Run the Services: start, stop, and check the status
- VLX_cameraman.sh (video input devices)
- VLX_gps_tracker.sh (sends positions via API)
- VLX_netflow.sh (switch network profiles)


## Future Development
This project is under active development. Planned features include:
- Web Interface: A web-based dashboard for status monitoring and control.
- Improved Error Handling: More robust checks and error reporting.
- Increase the automation and improve the automatisms. 
