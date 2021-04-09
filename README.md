# Home-Mode-Switcher-for-Synology-Surveillance-Station

A small script that triggers the Home Mode of Synology Surveillance Station whenever a choosen device results connected to the same LAN of the device that is executing the script.

It uses the MAC addresses provided by the user (as script arguments) to make a simple comparison with the currently connected devices and conseguently enable or disable Home Mode using Synology's web api for Surveillance Station. 



# Features

- **ALLOWS TO DEACTIVATE THE GEOFENCE FEATURE OF DS CAM**

     The Geofence feature included in the Surveillance Station's mobile client (DS Cam) is slow, often inaccurate and drain a huge amount of battery both in Wi-Fi and GPS mode.

     This script allows to migrate all the process elsewhere, saving precious battery life.



- **EXECUTABLE ON VIRTUALLY ANY \*NIX OS**

     The script is designed to be executed with minimal efforts on nearly any stock * nix operating system, included the heavly customized debian-bases OS installed on Synology NASes.

     For this reason almost all the code is bash, so that it can be easly executed in every CLI.

     Only a minor part of the code needs Python3 installation: this is due to the lack of an easly installable BIN providing the compatibility with the 2 factor authentication.



- **COMPATIBLE WITH EVERY MODEM/ROUTER ON THE MARKET**

     Unlike many other similar projects, this script doesn't use any modem/router API to obtain a list of the active hosts in the LAN.

     Instead, a simple mix of ARP and PING is used for this purposec (NMAP has been tested, too, but its results were not precise enough).



- **COMPATIBLE WITH THE 2 FACTOR AUTHENTICATION (TESTED ONLY WITH GOOGLE AUTHENTICATOR)**

     As anticipated, this script is able to communicate with every Synology NAS even if the 2 Factor Authentication is enabled (tested only with Google Authenticator).



- **AVOIDS CONTINUOUS CALLS TO THE SYNOLOGY APIS**

     The use of an auxiliary file allows to keep in memory the last state of the Home Mode, and consequently to avoid too much calls to the Synolgy APIs.

     This leds to less stress to the CPU, expecially for the most dated devices.

     *Please note*: enabling / disabling the Home Mode manually is not recommended. This won't allow the auxiliary file to be updated, so for the script the current Home Mode state will be the last known before the manual operation.



- **NO NEED TO CREATE A USER WITH ADMIN PRIVILEGES**

     Some full-python approaches, like the one used by Home Assistant, need to create a user with Admin priviledges, a security weakness that I couldn't accept even if the permissions for that user can be limited.

     Infact there is no way lo limit the access to the / photo directory for Admin-rank users, a problem that will surely be fixed with DSM7 but that can't be ignored for now.



# Instructions

The following instructions refers to the use of the script on the Synology NAS itself but, as stated above, you can choose to run the script on every device with a BASH shell and Python.



1. **CREATE A NEW USER WITH LIMITED PRIVILEGES** 

     ![new_user](https://user-images.githubusercontent.com/40309637/114241727-f2529600-9989-11eb-8fee-7efe03737744.png)

     In **Surveillance Station**:

     - Menu  →  User  →  List  →  Add
     - Input "*User Name*" and "*Password*"  →  Create new privilege profile
     - Insert a name for the profile and select "*Spectator*"  →  in "*Advanced Privilege*" uncheck ALL except "*Manually switch to Home Mode*"
     - Finish 

     Return to **DSM** and remove every priviege for the newly created user (both for shared folders and applications), allowing only the use of Surveillance Station.

     If your NAS is configured with **2FA** continue to read, if not jump to point 2.

     1. Logout your main account from DSM and login using the newly created account; you will be prompted with the 2FA configuration page with a QR code

     2. **IMPORTANT!** Make a screenshot of the provided QR code, go to [zxing.org](https://zxing.org/w/decode.jspx) (an open source QR reader) and upload the screenshot
	
     3. Take note of the 16 characters that compose the ***secret*** key contained in the raw text returned by the website: 

            otpauth://totp/User@Device?secret=1234567890abcdef 



2. **DOWNLOAD THE SCRIPT**

     Download the file [`homemode_switcher.sh`](https://github.com/dtypo/Home-Mode-Switcher-for-Synology-Surveillance-Station/blob/main/homemode_switcher.sh) from this GIT to you PC.



3. **`[OPTIONAL]` INSTALL PYTHON, PIP AND PYOTP**

     If your NAS is configured with 2FA, continue to read, if not jump to point 5.

     Install Python3 from the Package Center, then login to the NAS via SSH (use Putty on Windows) and give the following commands:

       sudo -i
       wget https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py 
       python3 /tmp/get-pip.py
       python3 /volume1/@appstore/py3k/usr/local/bin/pip install pyotp

     *Please note*: the command `sudo -i` will give you root access; for this reason it's required you to reinsert the same password of your main admin-ranked account.
     
     
     
4. **EDIT THE SCRIPT**

     Open the script with your favourite text editor in order to configure it.

     The mandatory configuration parameters... well are mandatory :D 

     Just use the newly created user to compile the `SYNO_USER` and `SYNO_PASS` fields, then insert the IP and the port used by the NAS.

     `[OPTIONAL]` If your NAS is configured with 2FA, insert the just obtained secret key in the field `SYNO_SECRET_KEY` (inside the quotes → "") and if require edit the volume in which Python, pip and pyotp have been installed; if not leave those fields totally blank.

     `[OPTIONAL]` If, for whatever reason (for example devices not pinging that slow down the script), you need to block a MAC address or an IP address, insert the MAC or the IP in the `BLACKLISTED_IPS_OR_MACS` field (use a space as separator).
     
     This way those IPs/MACs won't be pinged even if present in the arp table.



5. **PLACE THE SCRIPT WHEREVER YOU DESIRE IN YOUR NAS.**

     Copy the file `homemode_switcher.sh` in your preferred path on the NAS.

     It'a raccomanded to put the file in an uncrypted shared folder so that the script can run even after an unexpected reboot.



6. **GIVE THE EXECUTION PERMITS** 

     Using SSH, give the execution permits to the script with a:

       chmod +x path/to/homemode_switcher.sh



7. **TAKE NOTE OF THE AUTHORIZED MAC ADDRESSES**

     You can choose one or mode devices that will be able to trigger the Home Mode.

     Take note of their MAC addresses, you will need them in the next point.



8. **SCHEDULE THE EXECUTION OF THE SCRIPT**

     ![task](https://user-images.githubusercontent.com/40309637/114242173-bec43b80-998a-11eb-9fc7-20ddf36b390c.png)

     Open DSM, go to the Control Panel  →  Task Scheduler  →  Create  →  Scheduled task  →  User-defined script: 

     * Task name: homemode_switcher
     * User: root 
     * Enabled: checked
     * Run daily 
     * First time run: 00:00
     * Frequency: every 1/5 minutes (it's your choice)
     * Last run time: 23:59/23:55
     * Check "Send run details by email" and insert your email
     * Check "Send run details only when the script terminats abnormally" 
     * Run command: 
    
           bash /path/to/homemode_switcher.sh AA:BB:CC:11:22:33 DD:EE:FF:44:55:66

     Note that the argument of the ***command***  (`AA:BB:CC:11:22:33 DD:EE:FF:44:55:66`) must be replaced with one or more MAC addresses (space as separator) from the point 7.



# Credits

   Thanks to the whole community from which I've grabbed knowledge at full hands, but in particular to: 

   @mschippr for his great [***bash script***](https://github.com/mschippr/AVMFritz-Box7490-SynologySurveillance-Automation) I used as base, in particular the `switchHomemode` function.

   @welbornprod for the great [***tutorial***](https://gist.github.com/welbornprod/ccbf43393ecd610032f4) "*A little trick to embed python code in a BASH script*"

   @pyauth for the great Python module [***pyotp***](https://github.com/pyauth/pyotp)
